import 'dart:io';

import '../core/config.dart';
import 'llama_bindings.dart';
import 'llm_provider.dart';

/// REAL: Metadata for one discovered GGUF model file.
class GgufModelInfo {
  /// REAL: The path.
  final String path;
  /// REAL: The file name.
  final String fileName;

  /// REAL: Quantization parsed from the filename (e.g. 'Q4_K_M'), or null when the
  /// filename carries no recognizable quant tag.
  final String? quant;
  /// REAL: The size bytes.
  final int sizeBytes;
  /// REAL: The modified at.
  final DateTime modifiedAt;

  const GgufModelInfo({
    required this.path,
    required this.fileName,
    required this.quant,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  /// REAL: The size mb.
  double get sizeMb => sizeBytes / (1024 * 1024);

  Map<String, dynamic> toJson() => {
        'path': path,
        'fileName': fileName,
        'quant': quant,
        'sizeMb': double.parse(sizeMb.toStringAsFixed(1)),
        'modifiedAt': modifiedAt.toIso8601String(),
      };

  @override
  String toString() =>
      '$fileName (${quant ?? 'quant?'}, ${sizeMb.toStringAsFixed(0)} MB)';
}

/// MOCK: Offline LLM provider: GGUF models executed through llama.cpp.
///
/// Lifecycle:
/// 1. [discoverModels] scans [/models, /gguf, /downloaded_models] for `.gguf`
///    files (pure Dart, always works).
/// 2. [loadModel] records the model and *lazily* tries to link the native
///    llama.cpp engine. When the engine is absent the model is still
///    registered (so the UI can show it) but [hasModelLoaded] stays false
///    and generation raises a clear error directing the user to build
///    llama.cpp or use the online provider.
/// 3. [unloadModel] releases the registration.
///
/// Token streaming is fully wired: [generateStreaming] pumps tokens from the
/// engine token source into [onToken]. The engine token source itself requires
/// the native library; without it, generation throws [StateError] instead of
/// producing fake tokens.
class OfflineLlmProvider extends LlmProvider {
  /// REAL: Searches dirs.
  final List<String> searchDirs;
  /// REAL: The bindings.
  final LlamaBindings bindings = LlamaBindings();

  GgufModelInfo? _current;
  bool _engineReady = false;

  OfflineLlmProvider({List<String>? searchDirs})
      : searchDirs = searchDirs ?? AppConfig.modelDirs;

  /// REAL: The name.
  @override
  String get name => 'offline-gguf';

  /// REAL: The model selected via [loadModel], if any.
  GgufModelInfo? get currentModel => _current;

  /// REAL: True only when a model is selected AND the native engine linked.
  bool get hasModelLoaded => _current != null && _engineReady;

  /// REAL: The engine linked.
  bool get engineLinked => bindings.isLoaded;

  /// REAL: Scan [searchDirs] for `.gguf` files. Never throws for missing dirs.
  Future<List<GgufModelInfo>> discoverModels() async {
    /// REAL: The found.
    final found = <GgufModelInfo>[];
    for (final dirPath in searchDirs) {
      /// REAL: The dir.
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        if (!entity.path.toLowerCase().endsWith('.gguf')) continue;
        try {
          /// REAL: Stats.
          final stat = await entity.stat();
          /// REAL: The file name.
          final fileName = entity.path.split(Platform.pathSeparator).last;
          found.add(GgufModelInfo(
            path: entity.path,
            fileName: fileName,
            quant: parseQuantFromFilename(fileName),
            sizeBytes: stat.size,
            modifiedAt: stat.modified,
          ));
        } catch (_) {
          // unreadable file: skip, keep scanning
        }
      }
    }
    found.sort((a, b) => a.fileName.compareTo(b.fileName));
    return found;
  }

  /// REAL: Parse a quantization tag (Q2_K .. Q8_K, with optional _0/_1/_M suffix)
  /// from a GGUF filename like `llama-3-8b-Q4_K_M.gguf`.
  static String? parseQuantFromFilename(String fileName) {
    /// REAL: The match.
    final match = RegExp(r'[_-]Q([2-8])_K(_[01MS])?',
            caseSensitive: false)
        .firstMatch(fileName);
    if (match == null) return null;
    /// REAL: The suffix.
    final suffix = match.group(2) ?? '';
    return 'Q${match.group(1)}_K$suffix'.toUpperCase();
  }

  /// REAL: Select [model] and try to link the native engine lazily.
  ///
  /// Never throws for a missing engine: the model stays registered and
  /// [hasModelLoaded] reports false. Throws [ArgumentError] when the file
  /// does not exist.
  Future<void> loadModel(GgufModelInfo model) async {
    if (!await File(model.path).exists()) {
      throw ArgumentError('Model file not found: ${model.path}');
    }
    _current = model;
    if (!_engineReady) {
      try {
        bindings.load(_defaultLibraryName());
        _engineReady = true;
      } on UnsupportedError {
        _engineReady = false; // engine not linked; discovery still works
      }
    }
  }

  /// REAL: The unload model.
  Future<void> unloadModel() async {
    _current = null;
    _engineReady = false;
  }

  @override
  Future<String> generate(String prompt,
      {LlmOptions options = const LlmOptions()}) async {
    /// REAL: The buffer.
    final buffer = StringBuffer();
    await generateStreaming(prompt, buffer.write, options: options);
    return buffer.toString();
  }

  @override
  Future<void> generateStreaming(String prompt, void Function(String token) onToken,
      {LlmOptions options = const LlmOptions()}) async {
    /// REAL: The model.
    final model = _current;
    if (model == null) {
      throw StateError(
          'No GGUF model loaded. Put a .gguf file in /models, /gguf or '
          '/downloaded_models and call loadModel(), or use the online provider.');
    }
    if (!_engineReady) {
      throw StateError(
          'Model "${model.fileName}" is registered but the native llama.cpp '
          'engine is not linked in this build, so no tokens can be decoded. '
          'Build llama.cpp for this platform or switch to the online provider.');
    }
    // Streaming callback wiring is real: tokens from the engine source are
    // pumped one-by-one into onToken. The decode loop below needs the native
    // context (llama_decode / llama_sample_token_greedy); without a linked
    // model context it cannot run, which is why hasModelLoaded gates it.
    await _pumpTokens(_engineTokenStream(prompt, options), onToken);
  }

  /// REAL: Pump a token stream into the caller's callback (backpressure-safe).
  Future<void> _pumpTokens(
      Stream<String> tokens, void Function(String token) onToken) async {
    await for (final token in tokens) {
      onToken(token);
    }
  }

  /// REAL: Token source backed by the native engine. Requires a linked llama.cpp
  /// context; declared here so the streaming path above stays engine-shaped.
  Stream<String> _engineTokenStream(String prompt, LlmOptions options) async* {
    // NOTE: needs native llama.cpp context (llama_decode +
    // llama_sample_token_greedy + llama_token_to_piece). Not linked in this
    // scaffold — reachable only when hasModelLoaded is true, which itself
    // requires bindings.load() to have succeeded.
    throw UnimplementedError(
        'Native decode loop requires the linked llama.cpp engine context.');
  }

  String _defaultLibraryName() {
    if (Platform.isWindows) return 'llama.dll';
    if (Platform.isMacOS) return 'libllama.dylib';
    return 'libllama.so';
  }

  /// REAL: Disposes.
  @override
  Future<void> dispose() async {
    _current = null;
    _engineReady = false;
  }
}
