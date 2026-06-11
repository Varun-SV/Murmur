import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:mediapipe_llm_inference/mediapipe_llm_inference.dart';

import 'package:murmur/core/nlp/rule_engine.dart';
import 'package:murmur/core/result.dart';

final _log = Logger('LlmExtractor');

// Refines a RuleEngine match using an on-device Gemma model.
// Gemma is NEVER loaded eagerly — it loads on the first call and
// is released after 60 s of idle to free RAM.
class LlmExtractionResult {
  const LlmExtractionResult({
    required this.task,
    this.timeStr,
    required this.confidence,
  });

  final String task;
  final String? timeStr;
  final double confidence; // [0, 1]
}

// Internal work item for the serialised request queue.
class _PendingRequest {
  _PendingRequest(this.transcript, this.match, this.completer);

  final String transcript;
  final RuleMatch match;
  final Completer<Result<LlmExtractionResult>> completer;
}

class LlmExtractor {
  LlmExtractor({required this.modelPath});

  final String modelPath;

  LlmInference? _inference;
  Timer? _idleTimer;
  bool _loading = false;
  Completer<void>? _loadCompleter;

  bool _isRefining = false;
  final Queue<_PendingRequest> _pendingQueue = Queue();
  static const _maxQueueDepth = 3;

  static const _idleTimeout = Duration(seconds: 60);

  static const _systemPrompt = '''
You are a reminder extraction assistant. Given a speech transcript and an initial extraction, output improved JSON.

Rules:
- task: concise, actionable imperative phrase (e.g. "Call John", "Buy groceries")
- time_str: raw time expression as spoken, or null if not mentioned
- confidence: float 0.0-1.0 reflecting extraction certainty
- If no clear reminder is present, set task to null

Respond ONLY with JSON. No explanation.
''';

  /// Refines a [RuleMatch] using the LLM.
  ///
  /// Falls back to the original [match] if the LLM is unavailable or produces
  /// unparseable output.
  Future<Result<LlmExtractionResult>> refine(
    String transcript,
    RuleMatch match,
  ) async {
    _resetIdleTimer();

    if (_isRefining) {
      // Enforce max queue depth — drop oldest if at capacity.
      if (_pendingQueue.length >= _maxQueueDepth) {
        final dropped = _pendingQueue.removeFirst();
        _log.warning(
            'LLM queue at capacity, dropping oldest request; '
            'using rule match fallback');
        dropped.completer.complete(Ok(_ruleMatchResult(match: dropped.match)));
      }
      final completer = Completer<Result<LlmExtractionResult>>();
      _pendingQueue.addLast(_PendingRequest(transcript, match, completer));
      return completer.future;
    }

    return _doRefine(transcript, match);
  }

  Future<Result<LlmExtractionResult>> _doRefine(
    String transcript,
    RuleMatch match,
  ) async {
    _isRefining = true;
    try {
      final loadResult = await _ensureLoaded();
      if (loadResult is Err) {
        _log.warning(
            'LLM unavailable, using rule match: ${(loadResult as Err).message}');
        return Ok(_ruleMatchResult(match: match));
      }

      final prompt = _buildPrompt(transcript, match);
      try {
        final raw = await _inference!.generateResponse(prompt);
        return _parseResponse(raw, match);
      } catch (e, st) {
        _log.severe('LLM inference failed', e, st);
        _log.warning('LLM extraction failed, using rule match: $e');
        return Ok(_ruleMatchResult(match: match));
      }
    } finally {
      _isRefining = false;
      _drainQueue();
    }
  }

  void _drainQueue() {
    if (_pendingQueue.isEmpty) return;
    final next = _pendingQueue.removeFirst();
    // Schedule the next item without blocking the current call stack.
    Future.microtask(() async {
      final result = await _doRefine(next.transcript, next.match);
      if (!next.completer.isCompleted) {
        next.completer.complete(result);
      }
    });
  }

  Future<Result<void>> _ensureLoaded() async {
    if (_inference != null) return const Ok(null);

    if (_loading) {
      // Wait for the in-flight load via the Completer.
      await _loadCompleter!.future;
      return _inference != null ? const Ok(null) : const Err('LLM load failed');
    }

    _loading = true;
    _loadCompleter = Completer<void>();
    try {
      _log.info('Loading Gemma model from $modelPath');
      _inference = await LlmInference.createFromOptions(
        LlmInferenceOptions(
          modelPath: modelPath,
          maxTokens: 256,
        ),
      );
      _log.info('Gemma model loaded');
      return const Ok(null);
    } catch (e, st) {
      _log.severe('Failed to load Gemma model', e, st);
      return Err('Failed to load Gemma: $e', cause: e as Object);
    } finally {
      _loading = false;
      _loadCompleter!.complete();
    }
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, _unload);
  }

  void _unload() {
    _log.info('Gemma idle timeout — releasing model');
    _inference?.close();
    _inference = null;
  }

  String _buildPrompt(String transcript, RuleMatch match) {
    return '''$_systemPrompt
Transcript: "$transcript"
Initial extraction: task="${match.task}", time_str="${match.timeStr ?? 'null'}"

Output JSON:''';
  }

  Result<LlmExtractionResult> _parseResponse(String raw, RuleMatch fallback) {
    // Attempt 1: decode the full response string.
    Map<String, dynamic>? decoded;
    try {
      decoded = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      // Attempt 2: find the first '{' and last '}' and extract that substring.
      final jsonStart = raw.indexOf('{');
      final jsonEnd = raw.lastIndexOf('}');
      if (jsonStart != -1 && jsonEnd != -1 && jsonEnd > jsonStart) {
        try {
          decoded =
              jsonDecode(raw.substring(jsonStart, jsonEnd + 1))
                  as Map<String, dynamic>;
        } catch (e) {
          _log.warning(
              'LLM extraction failed, using rule match: could not parse JSON — $e');
          return Ok(_ruleMatchResult(match: fallback));
        }
      } else {
        _log.warning(
            'LLM extraction failed, using rule match: no JSON object found in response');
        return Ok(_ruleMatchResult(match: fallback));
      }
    }

    try {
      final taskRaw = decoded['task'];
      final task = taskRaw is String ? taskRaw.trim() : null;

      if (task == null || task.isEmpty || task == 'null') {
        _log.warning(
            'LLM extraction failed, using rule match: task is null/empty');
        return Ok(LlmExtractionResult(
          task: fallback.task,
          timeStr: fallback.timeStr,
          confidence: 0.6,
        ));
      }

      final timeRaw = decoded['time_str'];
      final timeStr =
          (timeRaw is String && timeRaw != 'null' && timeRaw.isNotEmpty)
              ? timeRaw
              : fallback.timeStr;

      final confidenceRaw = decoded['confidence'];
      final confidence =
          (confidenceRaw is num ? confidenceRaw.toDouble() : 0.8)
              .clamp(0.3, 1.0);

      return Ok(LlmExtractionResult(
        task: task,
        timeStr: timeStr,
        confidence: confidence,
      ));
    } catch (e) {
      _log.warning('LLM extraction failed, using rule match: $e');
      return Ok(_ruleMatchResult(match: fallback));
    }
  }

  LlmExtractionResult _ruleMatchResult({
    required RuleMatch match,
    double confidence = 0.7,
  }) =>
      LlmExtractionResult(
        task: match.task,
        timeStr: match.timeStr,
        confidence: confidence,
      );

  void dispose() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _inference?.close();
    _inference = null;
    // Complete any pending requests with fallback.
    for (final req in _pendingQueue) {
      if (!req.completer.isCompleted) {
        req.completer.complete(Ok(_ruleMatchResult(match: req.match)));
      }
    }
    _pendingQueue.clear();
  }
}
