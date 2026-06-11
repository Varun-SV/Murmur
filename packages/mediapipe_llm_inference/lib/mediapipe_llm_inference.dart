/// Stub implementation of the MediaPipe LLM Inference API.
///
/// The real plugin is a native MediaPipe binding that is not published to
/// pub.dev. This stub satisfies `dart analyze` and lets unit tests run on CI.
/// On device, replace this path dependency with the real native plugin.
library mediapipe_llm_inference;

class LlmInferenceOptions {
  const LlmInferenceOptions({
    required this.modelPath,
    this.maxTokens = 512,
  });

  final String modelPath;
  final int maxTokens;
}

class LlmInference {
  LlmInference._();

  /// Throws [UnsupportedError] on non-device targets (CI, desktop).
  /// [LlmExtractor] catches this and falls back to rule-match results.
  static Future<LlmInference> createFromOptions(
    LlmInferenceOptions options,
  ) async {
    throw UnsupportedError(
      'MediaPipe LLM inference is only available on Android/iOS devices. '
      'LlmExtractor will fall back to rule-based extraction.',
    );
  }

  Future<String> generateResponse(String prompt) async {
    throw UnsupportedError('LlmInference stub: generateResponse not available.');
  }

  void close() {}
}
