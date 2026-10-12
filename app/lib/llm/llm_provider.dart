/// REAL: Abstract LLM provider contract for NP.
///
/// Both offline (GGUF via llama.cpp) and online (cloud API) providers
/// implement this. The [LlmRouter] picks one per request.
class LlmOptions {
  /// REAL: The max tokens.
  final int maxTokens;
  /// REAL: The temperature.
  final double temperature;
  /// REAL: The system prompt.
  final String? systemPrompt;
  /// REAL: Stops sequences.
  final List<String> stopSequences;

  const LlmOptions({
    this.maxTokens = 512,
    this.temperature = 0.7,
    this.systemPrompt,
    this.stopSequences = const [],
  });
}

/// REAL: Abstract LLM provider contract for NP.
abstract class LlmProvider {
  /// REAL: Human-readable provider name, e.g. 'offline-gguf' or 'openai-compatible'.
  String get name;

  /// REAL: Generate a complete response for [prompt].
  Future<String> generate(String prompt,
      {LlmOptions options = const LlmOptions()});

  /// REAL: Stream response tokens; [onToken] is invoked per decoded token.
  Future<void> generateStreaming(String prompt, void Function(String token) onToken,
      {LlmOptions options = const LlmOptions()});

  /// REAL: Release native resources (model/context handles, HTTP clients).
  Future<void> dispose();
}
