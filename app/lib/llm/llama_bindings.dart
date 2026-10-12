import 'dart:ffi';

/// dart:ffi binding signatures for llama.cpp.
///
/// These are the *signatures* the offline provider needs. The native library
/// (`libllama.so` / `llama.dll` / `libllama.dylib`, built from llama.cpp) is
/// NOT bundled with this scaffold — [LlamaBindings.load] looks it up lazily
/// at runtime and throws a clear error when it is absent, so the rest of the
/// app keeps working (model discovery, router fallback) without it.
///
/// Reference: https://github.com/ggerganov/llama.cpp (llama.h)
library;

// --- native signatures -------------------------------------------------------
// llama_model* llama_model_load_from_file(const char* path, llama_model_params params)
typedef _LlamaModelLoadFromFileNative = Pointer<Void> Function(
    Pointer<Utf8> pathModel, Pointer<Void> params);
typedef _LlamaModelLoadFromFileDart = Pointer<Void> Function(
    Pointer<Utf8> pathModel, Pointer<Void> params);

// void llama_model_free(llama_model* model)
typedef _LlamaModelFreeNative = Void Function(Pointer<Void> model);
typedef _LlamaModelFreeDart = void Function(Pointer<Void> model);

// llama_context* llama_init_from_model(llama_model* model, llama_context_params params)
typedef _LlamaInitFromModelNative = Pointer<Void> Function(
    Pointer<Void> model, Pointer<Void> params);
typedef _LlamaInitFromModelDart = Pointer<Void> Function(
    Pointer<Void> model, Pointer<Void> params);

// void llama_free(llama_context* ctx)
typedef _LlamaFreeNative = Void Function(Pointer<Void> ctx);
typedef _LlamaFreeDart = void Function(Pointer<Void> ctx);

// int32_t llama_decode(llama_context* ctx, llama_batch batch)
typedef _LlamaDecodeNative = Int32 Function(
    Pointer<Void> ctx, Pointer<Void> batch);
typedef _LlamaDecodeDart = int Function(Pointer<Void> ctx, Pointer<Void> batch);

// int32_t llama_n_vocab(const llama_model* model)
typedef _LlamaNVocabNative = Int32 Function(Pointer<Void> model);
typedef _LlamaNVocabDart = int Function(Pointer<Void> model);

// int32_t llama_token_to_piece(const llama_model* model, llama_token token,
//                              char* buf, int32_t length, int32_t lstrip,
//                              bool special)
typedef _LlamaTokenToPieceNative = Int32 Function(
    Pointer<Void> model,
    Int32 token,
    Pointer<Utf8> buf,
    Int32 length,
    Int32 lstrip,
    Bool special);
typedef _LlamaTokenToPieceDart = int Function(
    Pointer<Void> model,
    int token,
    Pointer<Utf8> buf,
    int length,
    int lstrip,
    bool special);

// llama_token llama_sample_token(llama_context* ctx, llama_sampler* sampler)
// (simplified: greedy variant llama_sample_token_greedy)
typedef _LlamaSampleTokenGreedyNative = Int32 Function(Pointer<Void> ctx);
typedef _LlamaSampleTokenGreedyDart = int Function(Pointer<Void> ctx);

/// Lazy loader + typed accessors for the llama.cpp shared library.
class LlamaBindings {
  DynamicLibrary? _lib;

  bool get isLoaded => _lib != null;

  /// Load the native library. Throws [UnsupportedError] with a clear message
  /// when the library cannot be found — the offline provider treats this as
  /// "engine not linked" and keeps model discovery working.
  void load(String libraryPath) {
    try {
      _lib = DynamicLibrary.open(libraryPath);
    } catch (e) {
      throw UnsupportedError(
          'llama.cpp native library not found at "$libraryPath" ($e). '
          'Offline inference requires building llama.cpp for this platform.');
    }
  }

  DynamicLibrary get _requireLib {
    final lib = _lib;
    if (lib == null) {
      throw StateError(
          'LlamaBindings.load() was not called: native llama.cpp engine is '
          'not linked in this build.');
    }
    return lib;
  }

  late final _LlamaModelLoadFromFileDart modelLoadFromFile =
      _requireLib.lookupFunction<_LlamaModelLoadFromFileNative,
          _LlamaModelLoadFromFileDart>('llama_model_load_from_file');

  late final _LlamaModelFreeDart modelFree =
      _requireLib.lookupFunction<_LlamaModelFreeNative, _LlamaModelFreeDart>(
          'llama_model_free');

  late final _LlamaInitFromModelDart initFromModel =
      _requireLib.lookupFunction<_LlamaInitFromModelNative,
          _LlamaInitFromModelDart>('llama_init_from_model');

  late final _LlamaFreeDart freeContext =
      _requireLib.lookupFunction<_LlamaFreeNative, _LlamaFreeDart>(
          'llama_free');

  late final _LlamaDecodeDart decode =
      _requireLib.lookupFunction<_LlamaDecodeNative, _LlamaDecodeDart>(
          'llama_decode');

  late final _LlamaNVocabDart nVocab =
      _requireLib.lookupFunction<_LlamaNVocabNative, _LlamaNVocabDart>(
          'llama_n_vocab');

  late final _LlamaTokenToPieceDart tokenToPiece =
      _requireLib.lookupFunction<_LlamaTokenToPieceNative,
          _LlamaTokenToPieceDart>('llama_token_to_piece');

  late final _LlamaSampleTokenGreedyDart sampleTokenGreedy =
      _requireLib.lookupFunction<_LlamaSampleTokenGreedyNative,
          _LlamaSampleTokenGreedyDart>('llama_sample_token_greedy');
}
