import 'dart:math';

import 'llm_provider.dart';

/// MOCK: Simulated LLM provider — produces plausible assistant text with
/// realistic token streaming, without any model.
///
/// [generateStreaming] emits the response word-by-word with ~30-60 ms
/// delays per token. The reply text is chosen by cheap intent matching:
/// greetings, farewells, identity questions, and help requests get tailored
/// answers; anything else gets a generic assistant reply that echoes the
/// prompt topic. Tool use is NOT performed here — that is the pipeline's
/// job (the planner + ToolAgent).
///
/// This is the router's final fallback: it guarantees NP can always answer
/// something, even fully offline with no GGUF model on disk.
class MockStreamingProvider extends LlmProvider {
  final Random _random;

  /// MOCK: Create the mock provider (optional [seed] for deterministic tests).
  MockStreamingProvider({int? seed}) : _random = Random(seed);

  @override
  String get name => 'mock-streaming';

  /// MOCK: Build the full response, then return it at once.
  @override
  Future<String> generate(String prompt,
      {LlmOptions options = const LlmOptions()}) async {
    final buffer = StringBuffer();
    await generateStreaming(prompt, buffer.write, options: options);
    return buffer.toString();
  }

  /// MOCK: Stream the reply word-by-word with 30-60 ms per token.
  @override
  Future<void> generateStreaming(String prompt,
      void Function(String token) onToken,
      {LlmOptions options = const LlmOptions()}) async {
    final reply = _replyFor(prompt, options);
    final words = reply.split(' ');
    for (var i = 0; i < words.length; i++) {
      await Future.delayed(
          Duration(milliseconds: 30 + _random.nextInt(31)));
      onToken(i == 0 ? words[i] : ' ${words[i]}');
    }
  }

  /// MOCK: No native resources to release.
  @override
  Future<void> dispose() async {}

  /// MOCK: Cheap intent matching for plausible assistant text.
  String _replyFor(String prompt, LlmOptions options) {
    final lower = prompt.toLowerCase().trim();
    if (RegExp(r'^(hi|hey|hello|yo|namaste)\b').hasMatch(lower)) {
      return 'Hello! I am NP, your AI operating-system agent. '
          'I am running on the mock language model right now — no GGUF model '
          'is loaded — but my tools, memory, and pipeline are fully working. '
          'Try asking me to list files, run a command, or remember something.';
    }
    if (lower.contains('bye') || lower.contains('good night')) {
      return 'Goodbye! I will keep your memories safe until next time.';
    }
    if (lower.contains('who are you') || lower.contains('your name')) {
      return 'I am NP — a hybrid offline+online AI operating-system agent. '
          'Right now you are talking to my mock provider, which stands in '
          'for the real language model when none is available.';
    }
    if (lower.contains('what can you do') || lower.contains('help')) {
      return 'I can work with files, run terminal commands, fetch web pages, '
          'analyze Dart code, manage tasks, keep a calendar, extract PDF '
          'text, and remember things across sessions. Tell me what to do '
          'and I will plan the steps and run them through my safety gate.';
    }
    if (lower.contains('thank')) {
      return 'You are welcome! Anything else I can do for you?';
    }
    final snippet =
        prompt.length > 80 ? '${prompt.substring(0, 80)}...' : prompt;
    return 'Understood — "$snippet". '
        'I am running on the mock language model, so I cannot reason deeply '
        'about this, but my pipeline, tools, and memory are fully operational. '
        'Ask me to do something concrete (list files, run a command, save a '
        'memory) and I will get it done.';
  }
}
