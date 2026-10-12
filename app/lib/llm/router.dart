import 'dart:io';

import 'llm_provider.dart';
import 'mock_provider.dart';
import 'offline_provider.dart';
import 'online_provider.dart';

/// REAL: Routes generation to the offline GGUF provider, the online
/// provider, or the mock provider.
///
/// Selection policy ([selectProvider]):
/// 1. If an offline model is loaded AND the native engine is linked -> offline.
/// 2. Else, if a GGUF model file is actually discovered on disk -> load it
///    into the offline provider and use it (real path; generation raises a
///    clear error when the native engine is not linked).
/// 3. Else, if an online provider is configured (API key set) and the
///    network is reachable -> online.
/// 4. Else -> [MockStreamingProvider]: always-available simulated replies
///    with realistic streaming, so NP keeps working fully offline.
///
/// [checkOnlineConnectivity] does a real DNS probe with a short timeout —
/// no state is cached, so airplane-mode toggles are honored immediately.
class LlmRouter extends LlmProvider {
  /// REAL: The offline GGUF provider.
  final OfflineLlmProvider offline;

  /// REAL: The optional online provider (needs an API key).
  final OnlineLlmProvider? online;

  /// MOCK: Final fallback when nothing real can serve the request.
  final MockStreamingProvider mock;

  LlmRouter({
    required this.offline,
    this.online,
    MockStreamingProvider? mock,
  }) : mock = mock ?? MockStreamingProvider();

  /// REAL: The name.
  @override
  String get name => 'router';

  /// REAL: Connectivity probe — DNS lookup with a short timeout.
  Future<bool> checkOnlineConnectivity(
      {Duration timeout = const Duration(seconds: 3)}) async {
    try {
      /// REAL: The addresses.
      final addresses = await InternetAddress.lookup('huggingface.co')
          .timeout(timeout);
      return addresses.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// REAL: Whether the online provider is usable (key configured).
  bool get onlineConfigured {
    /// REAL: The o.
    final o = online;
    if (o is OpenAICompatibleProvider) {
      /// REAL: The key.
      final key = o.apiKey;
      return key != null && key.isNotEmpty;
    }
    return o != null;
  }

  /// REAL: Pick the provider for the next request, per the policy above.
  Future<LlmProvider> selectProvider() async {
    if (offline.hasModelLoaded) return offline;
    // A GGUF file on disk means the real offline provider owns the request,
    // even if the native engine is missing (it raises the actionable error).
    try {
      if (offline.currentModel == null) {
        /// REAL: The models.
        final models = await offline.discoverModels();
        if (models.isNotEmpty) {
          await offline.loadModel(models.first);
        }
      }
      if (offline.currentModel != null) return offline;
    } catch (_) {
      // Discovery/load failed; fall through to online/mock.
    }
    if (online != null && onlineConfigured && await checkOnlineConnectivity()) {
      return online!;
    }
    return mock;
  }

  /// REAL: Human-readable explanation of the current routing decision.
  Future<String> routingDecision() async {
    if (offline.hasModelLoaded) {
      return 'offline (${offline.currentModel!.fileName})';
    }
    try {
      /// REAL: The models.
      final models = await offline.discoverModels();
      if (models.isNotEmpty) {
        return 'offline-gguf-on-disk (${models.first.fileName})';
      }
    } catch (_) {}
    if (online != null && onlineConfigured && await checkOnlineConnectivity()) {
      return 'online (${online!.model})';
    }
    return 'mock (no GGUF on disk, online unavailable)';
  }

  @override
  Future<String> generate(String prompt,
      {LlmOptions options = const LlmOptions()}) async {
    /// REAL: The provider.
    final provider = await selectProvider();
    return provider.generate(prompt, options: options);
  }

  @override
  Future<void> generateStreaming(String prompt, void Function(String token) onToken,
      {LlmOptions options = const LlmOptions()}) async {
    /// REAL: The provider.
    final provider = await selectProvider();
    return provider.generateStreaming(prompt, onToken, options: options);
  }

  /// REAL: Disposes.
  @override
  Future<void> dispose() async {
    await offline.dispose();
    await online?.dispose();
    await mock.dispose();
  }
}
