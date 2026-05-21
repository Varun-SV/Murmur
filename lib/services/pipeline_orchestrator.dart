import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:murmur/core/audio/audio_capture_service.dart';
import 'package:murmur/core/audio/ring_buffer.dart';
import 'package:murmur/core/nlp/rule_engine.dart';
import 'package:murmur/core/nlp/time_parser.dart';
import 'package:murmur/core/result.dart';
import 'package:murmur/core/stt/speaker_registry.dart';
import 'package:murmur/core/stt/whisper_service.dart';
import 'package:murmur/data/database/reminder_dao.dart';
import 'package:murmur/data/models/reminder.dart';
import 'package:murmur/features/reminders/reminders_provider.dart';
import 'package:murmur/features/settings/settings_provider.dart';
import 'package:murmur/features/speakers/speakers_provider.dart';
import 'package:murmur/features/transcript/transcript_provider.dart';
import 'package:murmur/services/llm_extractor.dart';
import 'package:murmur/services/model_manager.dart';
import 'package:murmur/services/notification_service.dart';
import 'package:murmur/services/scheduler_service.dart';

final _log = Logger('PipelineOrchestrator');

// ── State ─────────────────────────────────────────────────────────────────────

sealed class PipelineState {
  const PipelineState();
}

class PipelineIdle extends PipelineState {
  const PipelineIdle();
}

/// Active recording. [degradedFeatures] lists optional features that failed
/// to load (VAD, speaker encoder, LLM) so the UI can warn the user.
class PipelineRecording extends PipelineState {
  const PipelineRecording({this.degradedFeatures = const []});
  final List<String> degradedFeatures;
}

class PipelineTranscribing extends PipelineState {
  const PipelineTranscribing();
}

/// Paused automatically when the app goes to background.
class PipelinePaused extends PipelineState {
  const PipelinePaused();
}

class PipelineError extends PipelineState {
  const PipelineError(this.message);
  final String message;
}

// ── Private service providers ─────────────────────────────────────────────────

final _ringBufferProvider = Provider<RingBuffer>((ref) => RingBuffer());
final _audioCaptureProvider = Provider<AudioCaptureService>((ref) => AudioCaptureService());
final _whisperServiceProvider = Provider<WhisperService>((ref) {
  final svc = WhisperService();
  ref.onDispose(() => svc.dispose());
  return svc;
});
final _ruleEngineProvider = Provider<RuleEngine>((ref) => RuleEngine());

// ── Notifier ──────────────────────────────────────────────────────────────────

class PipelineNotifier extends Notifier<PipelineState> {
  late final AudioCaptureService _audioSvc;
  late final WhisperService _whisperSvc;
  late final RingBuffer _ringBuffer;
  late final RuleEngine _ruleEngine;
  late final SpeakerRegistry _speakerRegistry;
  LlmExtractor? _llmExtractor;

  StreamSubscription<Uint8List>? _pcmSub;
  Timer? _flushTimer;
  bool _isTranscribing = false;

  static const _flushInterval = Duration(seconds: 30);

  @override
  PipelineState build() {
    _audioSvc = ref.read(_audioCaptureProvider);
    _whisperSvc = ref.read(_whisperServiceProvider);
    _ringBuffer = ref.read(_ringBufferProvider);
    _ruleEngine = ref.read(_ruleEngineProvider);
    _speakerRegistry = SpeakerRegistry();
    ref.onDispose(_cleanup);
    return const PipelineIdle();
  }

  Future<void> startPipeline() async {
    if (state is PipelineRecording || state is PipelineTranscribing) return;

    state = const PipelineRecording();

    // Load settings first — all model paths come from here.
    final settings = await ref.read(settingsProvider.future);

    _log.info('Initialising Whisper with model: ${settings.whisperModelPath}');
    final initResult = await _whisperSvc.initialize(settings.whisperModelPath);

    switch (initResult) {
      case Err(:final message):
        state = PipelineError(message);
        _log.severe('Whisper init failed: $message');
        return;
      case Ok():
        break;
    }

    final degraded = <String>[];

    // Load VAD model if enabled — failures degrade gracefully (no VAD gate).
    if (settings.vadEnabled) {
      final modelResult =
          await ref.read(modelManagerProvider).getVadModelPath();
      switch (modelResult) {
        case Ok(:final value):
          final vadInit = await _whisperSvc.initVad(value);
          switch (vadInit) {
            case Err(:final message):
              _log.warning('VAD init failed: $message — running without VAD');
              degraded.add('VAD');
            case Ok():
              break;
          }
        case Err(:final message):
          _log.warning('VAD model unavailable: $message — running without VAD');
          degraded.add('VAD');
      }
    }

    // Init speaker encoder if enabled.
    if (settings.speakerEncoderEnabled) {
      final encResult =
          await _whisperSvc.initSpeakerEncoder(settings.speakerModelPath);
      switch (encResult) {
        case Err(:final message):
          _log.warning(
              'Speaker encoder init failed: $message — running without diarization');
          degraded.add('Speaker encoder');
        case Ok():
          break;
      }
    }

    // Prepare LLM extractor (lazy — not loaded until first use).
    if (settings.llmEnabled) {
      _llmExtractor = LlmExtractor(modelPath: settings.gemmaModelPath);
    }

    // Load rule engine patterns.
    final engineResult = await _ruleEngine.load(rootBundle);
    switch (engineResult) {
      case Err(:final message):
        _log.warning('Rule engine load failed: $message');
        degraded.add('Rule engine');
      case Ok():
        break;
    }

    // Subscribe before starting capture to avoid losing early frames.
    _pcmSub = _audioSvc.pcmStream.listen(
      (chunk) => _ringBuffer.write(chunk),
      onError: (Object e, StackTrace st) {
        _log.severe('PCM stream error', e, st);
        state = PipelineError('Audio stream error: $e');
      },
    );

    final startResult = await _audioSvc.start();
    switch (startResult) {
      case Err(:final message):
        await _pcmSub?.cancel();
        _pcmSub = null;
        state = PipelineError(message);
        _log.severe('Audio capture start failed: $message');
        return;
      case Ok():
        break;
    }

    _flushTimer = Timer.periodic(_flushInterval, _onFlushTick);
    state = PipelineRecording(degradedFeatures: degraded);
    _log.info(
        'Pipeline started — flushing every ${_flushInterval.inSeconds}s'
        '${degraded.isEmpty ? '' : ' (degraded: ${degraded.join(', ')})'}');
  }

  Future<void> stopPipeline() async {
    await _cleanup();
    state = const PipelineIdle();
    _log.info('Pipeline stopped');
  }

  /// Pause when the app goes to background: cancel the timer and PCM
  /// subscription but leave the Whisper isolate alive for fast resume.
  Future<void> pausePipeline() async {
    if (state is! PipelineRecording && state is! PipelineTranscribing) return;
    _flushTimer?.cancel();
    _flushTimer = null;
    await _pcmSub?.cancel();
    _pcmSub = null;
    await _audioSvc.stop();
    _ringBuffer.flush(); // discard stale audio
    state = const PipelinePaused();
    _log.info('Pipeline paused');
  }

  /// Resume after returning to the foreground.
  Future<void> resumePipeline() async {
    if (state is! PipelinePaused) return;
    state = const PipelineRecording();

    _pcmSub = _audioSvc.pcmStream.listen(
      (chunk) => _ringBuffer.write(chunk),
      onError: (Object e, StackTrace st) {
        _log.severe('PCM stream error on resume', e, st);
        state = PipelineError('Audio stream error: $e');
      },
    );

    final startResult = await _audioSvc.start();
    switch (startResult) {
      case Err(:final message):
        await _pcmSub?.cancel();
        _pcmSub = null;
        state = PipelineError(message);
        _log.severe('Audio resume failed: $message');
        return;
      case Ok():
        break;
    }

    _flushTimer = Timer.periodic(_flushInterval, _onFlushTick);
    _log.info('Pipeline resumed');
  }

  void _onFlushTick(Timer _) async {
    if (_isTranscribing) {
      _log.warning('Flush skipped — previous transcription still running');
      return;
    }

    final pcm = _ringBuffer.flush();
    if (pcm.isEmpty) {
      _log.fine('Flush tick: buffer empty, nothing to transcribe');
      return;
    }

    _isTranscribing = true;
    state = const PipelineTranscribing();
    _log.info(
        'Transcribing ${pcm.length} samples (${(pcm.length / 16000).toStringAsFixed(1)}s)');

    final settings =
        ref.read(settingsProvider).valueOrNull ?? const AppSettings();
    final result = await _whisperSvc.detectAndTranscribe(
      pcm,
      vadThreshold: settings.vadEnabled ? settings.vadThreshold : 0.0,
    );

    _isTranscribing = false;

    switch (result) {
      case Ok(:final value):
        if (value == null) {
          _log.fine('VAD: silent segment, skipping transcription');
          break;
        }
        await _onTranscript(value);
      case Err(:final message):
        _log.warning('Transcription failed: $message');
    }

    if (state is PipelineTranscribing) {
      state = const PipelineRecording();
    }
  }

  Future<void> _onTranscript(TranscriptResult tr) async {
    _log.info(
        'Transcript: "${tr.text}" (${tr.language}, conf=${tr.confidence.toStringAsFixed(2)})');

    // Resolve speaker from embedding (if speaker encoder produced one).
    var speakerId = 'unknown';
    if (tr.speakerEmbedding != null) {
      final (id, isNew) = _speakerRegistry.identify(tr.speakerEmbedding!);
      speakerId = id;
      if (isNew) {
        final speaker = _speakerRegistry.speaker(id);
        if (speaker != null) {
          ref.read(speakersProvider.notifier).add(speaker);
        }
      }
    }

    ref.read(transcriptProvider.notifier).add(TranscriptEntry(
          text: tr.text,
          language: tr.language,
          confidence: tr.confidence,
          timestamp: DateTime.now(),
        ));

    final match = _ruleEngine.match(tr.text, tr.language);
    if (match == null) {
      _log.fine('No rule match for: "${tr.text}"');
      return;
    }
    _log.info('Rule match: task="${match.task}", timeStr="${match.timeStr}"');

    // Refine with LLM when available — falls back to rule match on any failure.
    String task = match.task;
    String? timeStr = match.timeStr;
    double confidence = tr.confidence;

    final extractor = _llmExtractor;
    if (extractor != null) {
      final llmResult = await extractor.refine(tr.text, match);
      switch (llmResult) {
        case Ok(:final value):
          task = value.task;
          timeStr = value.timeStr;
          confidence = value.confidence;
          _log.info(
              'LLM refined: task="$task", timeStr="$timeStr", conf=${confidence.toStringAsFixed(2)}');
        case Err(:final message):
          _log.warning('LLM refinement failed: $message — using rule match');
      }
    }

    final scheduledAt = timeStr != null ? TimeParser.parse(timeStr) : null;

    final reminder = Reminder(
      task: task,
      timeStr: timeStr,
      scheduledAt: scheduledAt,
      speakerId: speakerId,
      language: tr.language,
      confidence: confidence,
      transcriptSnippet: tr.text,
      status: ReminderStatus.pending,
      createdAt: DateTime.now(),
    );

    final dao = ref.read(reminderDaoProvider);
    final insertResult = await dao.insert(reminder);

    switch (insertResult) {
      case Err(:final message):
        _log.severe('Failed to insert reminder: $message');
        return;
      case Ok(:final value):
        ref.read(remindersProvider.notifier).refresh();

        if (scheduledAt != null) {
          await ref
              .read(schedulerServiceProvider)
              .scheduleReminder(value, task, scheduledAt);
        } else {
          await ref
              .read(notificationServiceProvider)
              .showImmediate(value, task);
        }
    }
  }

  Future<void> _cleanup() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _pcmSub?.cancel();
    _pcmSub = null;
    await _audioSvc.stop();
    _speakerRegistry.clear();
    _llmExtractor?.dispose();
    _llmExtractor = null;
    ref.read(speakersProvider.notifier).clear();
  }
}

final pipelineProvider = NotifierProvider<PipelineNotifier, PipelineState>(
  PipelineNotifier.new,
);
