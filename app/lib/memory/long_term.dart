import 'embeddings.dart';
import 'memory_store.dart';

/// Thin typed wrapper over the `long_term` memory layer.
///
/// Long-term memory holds durable episodic records: completed tasks, user
/// decisions, events worth remembering across sessions. Higher default
/// importance than short-term; nothing here is auto-pruned.
class LongTermMemory {
  static const String layer = 'long_term';

  final MemoryStore _store;
  final EmbeddingProvider _embeddings;

  const LongTermMemory(this._store, this._embeddings);

  Future<int> remember(String key, String content,
      {double importance = 0.7}) async {
    final vec = await _embeddings.embed(content);
    return _store.saveMemoryItem(
      layer: layer,
      key: key,
      content: content,
      embedding: encodeEmbedding(vec),
      importance: importance,
    );
  }

  Future<List<Map<String, Object?>>> recent({int limit = 50}) =>
      _store.getMemoryItems(
          layer: layer, limit: limit, orderByRecency: true);

  Future<Map<String, Object?>?> get(String key) =>
      _store.getMemoryItem(layer, key);

  Future<int> reinforce(int id, double importance) =>
      _store.updateImportance(id, importance);

  Future<int> forget(int id) => _store.deleteMemoryItem(id);

  Future<int> count() => _store.countMemoryItems(layer);
}
