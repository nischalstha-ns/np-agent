import 'dart:math';
import 'dart:typed_data';

/// Embedding abstraction + an offline hashing-based implementation.
///
/// [EmbeddingProvider] is async so a future neural provider (e.g. a GGUF
/// embedding model) can drop in without changing callers. [HashingEmbedding]
/// is the default: pure-Dart, no network, deterministic, good enough for
/// cosine-similarity retrieval over short memory texts.
abstract class EmbeddingProvider {
  int get dimension;

  /// Embed [text] into a L2-normalized vector of length [dimension].
  Future<Float32List> embed(String text);
}

class HashingEmbedding implements EmbeddingProvider {
  @override
  final int dimension;

  HashingEmbedding({this.dimension = 256});

  @override
  Future<Float32List> embed(String text) async {
    final vec = Float32List(dimension);
    final tokens = text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.isNotEmpty)
        .toList();

    String? prev;
    for (final token in tokens) {
      vec[_fnv1a(token) % dimension] += 1.0;
      if (prev != null) {
        // bigram signal, weighted lower than unigrams
        vec[_fnv1a('$prev $token') % dimension] += 0.5;
      }
      prev = token;
    }

    // L2-normalize so cosine similarity is a plain dot product.
    var sum = 0.0;
    for (var i = 0; i < vec.length; i++) {
      sum += vec[i] * vec[i];
    }
    final norm = sqrt(sum);
    if (norm > 0) {
      for (var i = 0; i < vec.length; i++) {
        vec[i] = vec[i] / norm;
      }
    }
    return vec;
  }

  /// FNV-1a 32-bit hash over UTF-16 code units.
  static int _fnv1a(String s) {
    var hash = 0x811c9dc5;
    for (final unit in s.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  /// Cosine similarity; inputs are expected to be L2-normalized.
  static double cosine(Float32List a, Float32List b) {
    if (a.length != b.length || a.isEmpty) return 0.0;
    var dot = 0.0, na = 0.0, nb = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return 0.0;
    return dot / (sqrt(na) * sqrt(nb));
  }
}

/// Encode a vector for the SQLite `embedding` BLOB column (little-endian f32).
Uint8List encodeEmbedding(Float32List vec) {
  final bytes = Uint8List(vec.length * 4);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < vec.length; i++) {
    view.setFloat32(i * 4, vec[i], Endian.little);
  }
  return bytes;
}

/// Decode a BLOB produced by [encodeEmbedding].
Float32List decodeEmbedding(Uint8List bytes) {
  if (bytes.length % 4 != 0) {
    throw ArgumentError('Embedding blob length ${bytes.length} is not a '
        'multiple of 4');
  }
  final view = ByteData.sublistView(bytes);
  final out = Float32List(bytes.length ~/ 4);
  for (var i = 0; i < out.length; i++) {
    out[i] = view.getFloat32(i * 4, Endian.little);
  }
  return out;
}
