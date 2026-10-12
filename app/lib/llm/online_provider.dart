import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_provider.dart';

/// Contract for cloud LLM providers: an [LlmProvider] with an HTTP endpoint.
abstract class OnlineLlmProvider extends LlmProvider {
  String get baseUrl;
  String get model;
}

/// OpenAI-compatible chat-completions provider (works with OpenAI, Azure
/// OpenAI, llama.cpp server, Ollama, vLLM, etc.).
///
/// Real HTTP implementation via package:http. The API key is read from the
/// constructor (NP core passes `NP_API_KEY`); streaming is currently
/// implemented as "generate, then emit as one token" and documented as such.
class OpenAICompatibleProvider extends OnlineLlmProvider {
  final String? apiKey;
  @override
  final String baseUrl;
  @override
  final String model;

  final http.Client _client = http.Client();

  OpenAICompatibleProvider({
    required this.apiKey,
    required this.baseUrl,
    required this.model,
  });

  @override
  String get name => 'online-openai-compatible';

  @override
  Future<String> generate(String prompt,
      {LlmOptions options = const LlmOptions()}) async {
    final key = apiKey;
    if (key == null || key.isEmpty) {
      throw StateError(
          'Online provider has no API key. Set the NP_API_KEY environment '
          'variable or load an offline GGUF model.');
    }
    final messages = <Map<String, String>>[];
    if (options.systemPrompt != null && options.systemPrompt!.isNotEmpty) {
      messages.add({'role': 'system', 'content': options.systemPrompt!});
    }
    messages.add({'role': 'user', 'content': prompt});

    final response = await _client.post(
      Uri.parse('$baseUrl/chat/completions'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $key',
      },
      body: jsonEncode({
        'model': model,
        'messages': messages,
        'max_tokens': options.maxTokens,
        'temperature': options.temperature,
        if (options.stopSequences.isNotEmpty) 'stop': options.stopSequences,
      }),
    );

    if (response.statusCode != 200) {
      throw StateError(
          'Online LLM request failed (${response.statusCode}): '
          '${response.body.length > 300 ? response.body.substring(0, 300) : response.body}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw StateError('Online LLM returned no choices.');
    }
    final message = (choices.first as Map)['message'] as Map?;
    return (message?['content'] as String?)?.trim() ?? '';
  }

  @override
  Future<void> generateStreaming(String prompt, void Function(String token) onToken,
      {LlmOptions options = const LlmOptions()}) async {
    // Simplification: no SSE parsing yet — generate fully, then emit once.
    // The callback wiring is real; chunking will arrive with SSE support.
    final full = await generate(prompt, options: options);
    onToken(full);
  }

  @override
  Future<void> dispose() async => _client.close();
}
