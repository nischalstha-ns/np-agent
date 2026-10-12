import 'dart:typed_data';

import 'embeddings.dart';
import 'memory_store.dart';

/// REAL: A memory item scored for a query.
class ScoredMemory {
  /// REAL: The id.
  final int id;
  /// REAL: The layer.
  final String layer;
  /// REAL: The key.
  final String key;
  /// REAL: The content.
  final String content;
  /// REAL: The score.
  final double score;
  /// REAL: The similarity.
  final double similarity;
  /// REAL: The importance.
  final double importance;
  /// REAL: The updated at.
  final DateTime updatedAt;

  const ScoredMemory({
    required this.id,
    required this.layer,
    required this.key,
    required this.content,
    required this.score,
    required this.similarity,
    required this.importance,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'layer': layer,
        'key': key,
        'content': content,
        'score': score,
        'similarity': similarity,
        'importance': importance,
        'updatedAt': updatedAt.toIso8601String(),
      };
}

/// REAL: Hybrid retrieval used by the pipeline's memory stage.
///
/// score = wSim * cosine(query, item) + wRec * recency + wImp * importance
/// where recency = 1 / (1 + ageHours/24) and importance is the stored 0..1
/// weight. Items without a stored embedding still compete on recency and
/// importance (similarity = 0).
class RetrievalService {
  /// REAL: Stores.
  final MemoryStore store;
  /// REAL: The embeddings.
  final EmbeddingProvider embeddings;

  /// REAL: The similarity weight.
  final double similarityWeight;
  /// REAL: The recency weight.
  final double recencyWeight;
  /// REAL: The importance weight.
  final double importanceWeight;

  const RetrievalService({
    required this.store,
    required this.embeddings,
    this.similarityWeight = 0.6,
    this.recencyWeight = 0.25,
    this.importanceWeight = 0.15,
  });

  /// REAL: Retrieve the top-[topK] memories for [query] across [layers].
  Future<List<ScoredMemory>> retrieve(
    String query, {
    /// REAL: The layers.
    List<String> layers = const ['short_term', 'long_term', 'semantic'],
    /// REAL: The top k.
    int topK = 5,
  }) async {
    /// REAL: The query vec.
    final queryVec = await embeddings.embed(query);
    /// REAL: The rows.
    final rows = await store.getMemoryItems(layers: layers, limit: 500);
    /// REAL: The now ms.
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    /// REAL: The scored.
    final scored = <ScoredMemory>[];
    for (final row in rows) {
      /// REAL: The similarity.
      double similarity = 0.0;
      /// REAL: The blob.
      final blob = row['embedding'];
      if (blob is Uint8List && blob.isNotEmpty) {
        try {
          similarity =
              HashingEmbedding.cosine(queryVec, decodeEmbedding(blob));
        } catch (_) {
          similarity = 0.0; // corrupt blob: fall back to recency/importance
        }
      }
      /// REAL: The updated ms.
      final updatedMs = (row['updated_at'] as int?) ?? nowMs;
      /// REAL: The age hours.
      final ageHours = (nowMs - updatedMs) / 3600000.0;
      /// REAL: The recency.
      final recency = 1.0 / (1.0 + ageHours / 24.0);
      /// REAL: The importance.
      final importance =
          ((row['importance'] as num?) ?? 0.5).toDouble().clamp(0.0, 1.0);

      /// REAL: The score.
      final score = similarityWeight * similarity +
          recencyWeight * recency +
          importanceWeight * importance;

      scored.add(ScoredMemory(
        id: (row['id'] as int?) ?? 0,
        layer: (row['layer'] as String?) ?? '',
        key: (row['key'] as String?) ?? '',
        content: (row['content'] as String?) ?? '',
        score: score,
        similarity: similarity,
        importance: importance,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedMs),
      ));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(topK).toList();
  }
}
