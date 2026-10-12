import 'dart:io';

/// App-wide constants and environment-derived configuration for NP.
class AppConfig {
  static const String appName = 'NP';
  static const String version = '0.1.0';
  static const String dbFileName = 'np_agent.db';

  /// Directories scanned (in order) for GGUF model files by the offline
  /// LLM provider. Models are never bundled as Flutter assets.
  static const List<String> modelDirs = <String>[
    '/models',
    '/gguf',
    '/downloaded_models',
  ];

  /// Dimensionality of the local hashing embeddings (offline, no network).
  static const int embeddingDim = 256;

  /// Default number of memories returned per retrieval call.
  static const int retrievalTopK = 5;

  static const String hfApiBase = 'https://huggingface.co';

  /// Default timeout for a single tool execution.
  static const Duration toolTimeout = Duration(seconds: 60);

  /// Safety cap for a single browser fetch body.
  static const int maxBrowserFetchBytes = 512 * 1024;

  /// Model directories that actually exist on this machine, in scan order.
  static List<String> existingModelDirs() =>
      modelDirs.where((d) => Directory(d).existsSync()).toList();

  /// Writable per-user data root for NP (db, downloads, registry files).
  static Directory dataRoot() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    final dir = Directory('$home/.np');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Default download directory for HuggingFace models.
  static Directory downloadDir() {
    final dir = Directory('${dataRoot().path}/downloaded_models');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }
}
