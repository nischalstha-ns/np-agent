import 'dart:typed_data';

import 'embeddings.dart';
import 'memory_store.dart';

/// A memory item scored for a query.
class ScoredMemory {
  final int id;
  final String layer;
  final String key;
  final String content;
  final double score;
  final double similarity;
  final double importance;
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

/// Hybrid retrieval used by the pipeline's memory stage.
///
/// score = wSim * cosine(query, item) + wRec * recency + wImp * importance
/// where recency = 1 / (1 + ageHours/24) and importance is the stored 0..1
/// weight. Items without a stored embedding still compete on recency and
/// importance (similarity = 0).
class RetrievalService {
  final MemoryStore store;
  final EmbeddingProvider embeddings;

  final double similarityWeight;
  final double recencyWeight;
  final double importanceWeight;

  const RetrievalService({
    required this.store,
    required this.embeddings,
    this.similarityWeight = 0.6,
    this.recencyWeight = 0.25,
    this.importanceWeight = 0.15,
  });

  /// Retrieve the top-[topK] memories for [query] across [layers].
  Future<List<ScoredMemory>> retrieve(
    String query, {
    List<String> layers = const ['short_term', 'long_term', 'semantic'],
    int topK = 5,
  }) async {
    final queryVec = await embeddings.embed(query);
    final rows = await store.getMemoryItems(layers: layers, limit: 500);
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final scored = <ScoredMemory>[];
    for (final row in rows) {
      double similarity = 0.0;
      final blob = row['embedding'];
      if (blob is Uint8List && blob.isNotEmpty) {
        try {
          similarity =
              HashingEmbedding.cosine(queryVec, decodeEmbedding(blob));
        } catch (_) {
          similarity = 0.0; // corrupt blob: fall back to recency/importance
        }
      }
      final updatedMs = (row['updated_at'] as int?) ?? nowMs;
      final ageHours = (nowMs - updatedMs) / 3600000.0;
      final recency = 1.0 / (1.0 + ageHours / 24.0);
      final importance =
          ((row['importance'] as num?) ?? 0.5).toDouble().clamp(0.0, 1.0);

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
