import 'dart:io';

import 'llm_provider.dart';
import 'offline_provider.dart';
import 'online_provider.dart';

/// Routes generation to the offline GGUF provider or the online provider.
///
/// Selection policy ([selectProvider]):
/// 1. If an offline model is loaded AND the native engine is linked -> offline.
/// 2. Else, if an online provider is configured and the network is reachable
///    -> online.
/// 3. Else, if an offline model is registered but the engine is missing ->
///    offline anyway (it raises a clear, actionable error).
/// 4. Else throw: nothing can serve the request.
///
/// [checkOnlineConnectivity] does a real DNS probe with a short timeout —
/// no state is cached, so airplane-mode toggles are honored immediately.
class LlmRouter extends LlmProvider {
  final OfflineLlmProvider offline;
  final OnlineLlmProvider? online;

  LlmRouter({required this.offline, this.online});

  @override
  String get name => 'router';

  /// Real connectivity probe: DNS lookup with a short timeout.
  Future<bool> checkOnlineConnectivity(
      {Duration timeout = const Duration(seconds: 3)}) async {
    try {
      final addresses = await InternetAddress.lookup('huggingface.co')
          .timeout(timeout);
      return addresses.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Pick the provider for the next request, per the policy above.
  Future<LlmProvider> selectProvider() async {
    if (offline.hasModelLoaded) return offline;
    if (online != null && await checkOnlineConnectivity()) return online!;
    if (offline.currentModel != null) return offline; // clear error path
    throw StateError(
        'No LLM available: no GGUF model is loaded and the network is '
        'unreachable for the online provider.');
  }

  /// Human-readable explanation of the current routing decision.
  Future<String> routingDecision() async {
    if (offline.hasModelLoaded) {
      return 'offline (${offline.currentModel!.fileName})';
    }
    if (online != null && await checkOnlineConnectivity()) {
      return 'online (${online!.model})';
    }
    if (offline.currentModel != null) {
      return 'offline-registered-but-engine-missing '
          '(${offline.currentModel!.fileName})';
    }
    return 'none-available';
  }

  @override
  Future<String> generate(String prompt,
      {LlmOptions options = const LlmOptions()}) async {
    final provider = await selectProvider();
    return provider.generate(prompt, options: options);
  }

  @override
  Future<void> generateStreaming(String prompt, void Function(String token) onToken,
      {LlmOptions options = const LlmOptions()}) async {
    final provider = await selectProvider();
    return provider.generateStreaming(prompt, onToken, options: options);
  }

  @override
  Future<void> dispose() async {
    await offline.dispose();
    await online?.dispose();
  }
}
