import 'dart:io';

/// REAL: App-wide constants and environment-derived configuration for NP.
class AppConfig {
  /// REAL: The app name.
  static const String appName = 'NP';
  /// REAL: The version.
  static const String version = '0.1.0';
  /// REAL: The db file name.
  static const String dbFileName = 'np_agent.db';

  /// REAL: Directories scanned (in order) for GGUF model files by the offline
  /// LLM provider. Models are never bundled as Flutter assets.
  static const List<String> modelDirs = <String>[
    '/models',
    '/gguf',
    '/downloaded_models',
  ];

  /// REAL: Dimensionality of the local hashing embeddings (offline, no network).
  static const int embeddingDim = 256;

  /// REAL: Default number of memories returned per retrieval call.
  static const int retrievalTopK = 5;

  /// REAL: The hf api base.
  static const String hfApiBase = 'https://huggingface.co';

  /// REAL: Default timeout for a single tool execution.
  static const Duration toolTimeout = Duration(seconds: 60);

  /// REAL: Safety cap for a single browser fetch body.
  static const int maxBrowserFetchBytes = 512 * 1024;

  /// REAL: Model directories that actually exist on this machine, in scan order.
  static List<String> existingModelDirs() =>
      modelDirs.where((d) => Directory(d).existsSync()).toList();

  /// REAL: Writable per-user data root for NP (db, downloads, registry files).
  static Directory dataRoot() {
    /// REAL: The home.
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    /// REAL: The dir.
    final dir = Directory('$home/.np');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// REAL: Default download directory for HuggingFace models.
  static Directory downloadDir() {
    /// REAL: The dir.
    final dir = Directory('${dataRoot().path}/downloaded_models');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }
}
