import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:murmur/core/audio/audio_capture_service.dart';
import 'package:murmur/core/audio/ring_buffer.dart';
import 'package:murmur/core/result.dart';
import 'package:murmur/core/stt/whisper_service.dart';
import 'package:murmur/features/transcript/transcript_provider.dart';

final _log = Logger('PipelineOrchestrator');

// ── State ─────────────────────────────────────────────────────────────────────

sealed class PipelineState {
  const PipelineState();
}

class PipelineIdle extends PipelineState {
  const PipelineIdle();
}

class PipelineRecording extends PipelineState {
  const PipelineRecording();
}

class PipelineTranscribing extends PipelineState {
  const PipelineTranscribing();
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

// ── Notifier ──────────────────────────────────────────────────────────────────

class PipelineNotifier extends Notifier<PipelineState> {
  late final AudioCaptureService _audioSvc;
  late final WhisperService _whisperSvc;
  late final RingBuffer _ringBuffer;

  StreamSubscription<Uint8List>? _pcmSub;
  Timer? _flushTimer;
  bool _isTranscribing = false;

  static const _flushInterval = Duration(seconds: 30);
  static const _defaultModelPath = '/sdcard/Download/whisper-base.bin';

  @override
  PipelineState build() {
    _audioSvc = ref.read(_audioCaptureProvider);
    _whisperSvc = ref.read(_whisperServiceProvider);
    _ringBuffer = ref.read(_ringBufferProvider);
    ref.onDispose(_cleanup);
    return const PipelineIdle();
  }

  Future<void> startPipeline() async {
    if (state is PipelineRecording || state is PipelineTranscribing) return;

    state = const PipelineRecording();

    final prefs = await SharedPreferences.getInstance();
    final modelPath = prefs.getString('model_path') ?? _defaultModelPath;

    _log.info('Initialising Whisper with model: $modelPath');
    final initResult = await _whisperSvc.initialize(modelPath);

    switch (initResult) {
      case Err(:final message):
        state = PipelineError(message);
        _log.severe('Whisper init failed: $message');
        return;
      case Ok():
        break;
    }

    // Subscribe to PCM stream before starting capture to avoid losing frames.
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
    _log.info('Pipeline started — flushing every ${_flushInterval.inSeconds}s');
  }

  Future<void> stopPipeline() async {
    await _cleanup();
    state = const PipelineIdle();
    _log.info('Pipeline stopped');
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

    final result = await _whisperSvc.transcribe(pcm);

    _isTranscribing = false;

    result.fold(
      ok: (tr) {
        _log.info(
            'Transcript: "${tr.text}" (${tr.language}, conf=${tr.confidence.toStringAsFixed(2)})');
        ref.read(transcriptProvider.notifier).add(TranscriptEntry(
              text: tr.text,
              language: tr.language,
              confidence: tr.confidence,
              timestamp: DateTime.now(),
            ));
      },
      err: (msg) => _log.warning('Transcription failed: $msg'),
    );

    // Only update state if we're still recording (stopPipeline may have been called).
    if (state is PipelineTranscribing) {
      state = const PipelineRecording();
    }
  }

  Future<void> _cleanup() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _pcmSub?.cancel();
    _pcmSub = null;
    await _audioSvc.stop();
  }
}

final pipelineProvider = NotifierProvider<PipelineNotifier, PipelineState>(
  PipelineNotifier.new,
);
