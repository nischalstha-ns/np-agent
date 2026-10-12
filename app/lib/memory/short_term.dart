import 'embeddings.dart';
import 'memory_store.dart';

/// Thin typed wrapper over the `short_term` memory layer.
///
/// Short-term memory holds the current session's working context: recent
/// turns, in-flight entity values, scratch notes. It is high-recency,
/// medium-importance by default, and pruned by the caller when the session
/// ends (or left to decay via the recency term in retrieval).
class ShortTermMemory {
  static const String layer = 'short_term';

  final MemoryStore _store;
  final EmbeddingProvider _embeddings;

  const ShortTermMemory(this._store, this._embeddings);

  Future<int> save(String key, String content, {double importance = 0.4}) async {
    final vec = await _embeddings.embed(content);
    return _store.saveMemoryItem(
      layer: layer,
      key: key,
      content: content,
      embedding: encodeEmbedding(vec),
      importance: importance,
    );
  }

  /// Most recent short-term items, newest first.
  Future<List<Map<String, Object?>>> recent({int limit = 20}) =>
      _store.getMemoryItems(
          layer: layer, limit: limit, orderByRecency: true);

  Future<Map<String, Object?>?> get(String key) =>
      _store.getMemoryItem(layer, key);

  Future<int> forget(int id) => _store.deleteMemoryItem(id);

  Future<void> clearSession() async {
    final rows = await _store.getMemoryItems(layer: layer, limit: 10000);
    for (final row in rows) {
      await _store.deleteMemoryItem((row['id'] as int?) ?? 0);
    }
  }
}
