import 'embeddings.dart';
import 'memory_store.dart';

/// REAL: Thin typed wrapper over the `semantic` memory layer.
///
/// Semantic memory holds facts and general knowledge distilled from
/// experience ("the user prefers dark mode", "project X uses Riverpod").
/// Keyed by a stable fact id so re-learning the same fact upserts it.
class SemanticMemory {
  /// REAL: The layer.
  static const String layer = 'semantic';

  final MemoryStore _store;
  final EmbeddingProvider _embeddings;

  const SemanticMemory(this._store, this._embeddings);

  /// REAL: Learn (or update) a fact. Same [factId] replaces the previous version.
  Future<int> learnFact(String factId, String fact,
      {double importance = 0.8}) async {
    /// REAL: The vec.
    final vec = await _embeddings.embed(fact);
    return _store.saveMemoryItem(
      layer: layer,
      key: factId,
      content: fact,
      embedding: encodeEmbedding(vec),
      importance: importance,
    );
  }

  Future<Map<String, Object?>?> getFact(String factId) =>
      _store.getMemoryItem(layer, factId);

  Future<List<Map<String, Object?>>> allFacts({int limit = 200}) =>
      _store.getMemoryItems(layer: layer, limit: limit);

  /// REAL: The unlearn.
  Future<int> unlearn(String factId) async {
    /// REAL: The row.
    final row = await _store.getMemoryItem(layer, factId);
    if (row == null) return 0;
    return _store.deleteMemoryItem((row['id'] as int?) ?? 0);
  }

  /// REAL: Counts.
  Future<int> count() => _store.countMemoryItems(layer);
}
