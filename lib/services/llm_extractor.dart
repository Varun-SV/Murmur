import 'dart:async';

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

class LlmExtractor {
  LlmExtractor({required this.modelPath});

  final String modelPath;

  LlmInference? _inference;
  Timer? _idleTimer;
  bool _loading = false;

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

    final loadResult = await _ensureLoaded();
    if (loadResult is Err) {
      // Graceful degradation: return the rule-engine result unchanged.
      _log.warning('LLM unavailable, using rule match directly');
      return Ok(LlmExtractionResult(
        task: match.task,
        timeStr: match.timeStr,
        confidence: 0.7,
      ));
    }

    final prompt = _buildPrompt(transcript, match);

    try {
      final raw = await _inference!.generateResponse(prompt);
      return _parseResponse(raw, match);
    } catch (e, st) {
      _log.severe('LLM inference failed', e, st);
      return Ok(LlmExtractionResult(
        task: match.task,
        timeStr: match.timeStr,
        confidence: 0.7,
      ));
    }
  }

  Future<Result<void>> _ensureLoaded() async {
    if (_inference != null) return const Ok(null);
    if (_loading) {
      // Wait for the in-flight load.
      while (_loading) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return _inference != null ? const Ok(null) : const Err('LLM load failed');
    }

    _loading = true;
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
    // Extract the first JSON object from the response.
    final jsonStart = raw.indexOf('{');
    final jsonEnd = raw.lastIndexOf('}');
    if (jsonStart == -1 || jsonEnd == -1 || jsonEnd <= jsonStart) {
      _log.warning('LLM produced non-JSON response, using rule match');
      return Ok(LlmExtractionResult(
        task: fallback.task,
        timeStr: fallback.timeStr,
        confidence: 0.7,
      ));
    }

    final jsonStr = raw.substring(jsonStart, jsonEnd + 1);
    try {
      // Minimal JSON parsing to avoid dart:convert dependency issues in isolates.
      final task = _extractJsonString(jsonStr, 'task');
      final timeStr = _extractJsonString(jsonStr, 'time_str');
      final confidenceStr = _extractJsonValue(jsonStr, 'confidence');
      final confidence = double.tryParse(confidenceStr ?? '0.8') ?? 0.8;

      if (task == null || task.isEmpty || task == 'null') {
        return Ok(LlmExtractionResult(
          task: fallback.task,
          timeStr: fallback.timeStr,
          confidence: 0.6,
        ));
      }

      return Ok(LlmExtractionResult(
        task: task,
        timeStr: (timeStr == null || timeStr == 'null') ? fallback.timeStr : timeStr,
        confidence: confidence.clamp(0.0, 1.0),
      ));
    } catch (e) {
      _log.warning('Failed to parse LLM JSON: $e');
      return Ok(LlmExtractionResult(
        task: fallback.task,
        timeStr: fallback.timeStr,
        confidence: 0.7,
      ));
    }
  }

  // Simple key extraction from JSON without a full parser.
  String? _extractJsonString(String json, String key) {
    final pattern = RegExp('"$key"\\s*:\\s*(?:"([^"]*)"|(null))');
    final m = pattern.firstMatch(json);
    if (m == null) return null;
    if (m.group(2) == 'null') return null;
    return m.group(1);
  }

  String? _extractJsonValue(String json, String key) {
    final pattern = RegExp('"$key"\\s*:\\s*([\\d.]+)');
    return pattern.firstMatch(json)?.group(1);
  }

  void dispose() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _inference?.close();
    _inference = null;
  }
}
