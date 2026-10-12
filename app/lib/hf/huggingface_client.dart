import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// REAL: A HuggingFace model repo (subset of the HF API model object).
class HfModel {
  /// REAL: The id.
  final String id;
  /// REAL: The downloads.
  final int downloads;
  /// REAL: The likes.
  final int likes;
  /// REAL: The sha.
  final String? sha;
  /// REAL: The tags.
  final List<String> tags;

  const HfModel({
    required this.id,
    required this.downloads,
    required this.likes,
    this.sha,
    this.tags = const [],
  });

  factory HfModel.fromJson(Map<String, dynamic> json) => HfModel(
        id: json['id'] as String? ?? '',
        downloads: (json['downloads'] as int?) ?? 0,
        likes: (json['likes'] as int?) ?? 0,
        sha: json['sha'] as String?,
        tags: List<String>.from(json['tags'] as List? ?? const []),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'downloads': downloads,
        'likes': likes,
        'sha': sha,
        'tags': tags,
      };
}

/// REAL: One GGUF file inside a repo.
class GgufFile {
  /// REAL: The repo id.
  final String repoId;
  /// REAL: The file name.
  final String fileName;
  /// REAL: The size.
  final int? size;
  /// REAL: The sha256.
  final String? sha256;

  const GgufFile({
    required this.repoId,
    required this.fileName,
    this.size,
    this.sha256,
  });

  /// REAL: Direct download URL for the file on the main branch.
  String downloadUrl(String apiBase) =>
      '$apiBase/$repoId/resolve/main/$fileName';

  Map<String, dynamic> toJson() => {
        'repoId': repoId,
        'fileName': fileName,
        'size': size,
        'sha256': sha256,
      };
}

/// REAL: Progress event emitted while downloading.
class DownloadProgress {
  /// REAL: The file name.
  final String fileName;
  /// REAL: The received bytes.
  final int receivedBytes;
  /// REAL: The total bytes.
  final int? totalBytes;

  const DownloadProgress({
    required this.fileName,
    required this.receivedBytes,
    this.totalBytes,
  });

  /// REAL: The percent.
  double? get percent => totalBytes == null || totalBytes == 0
      ? null
      : receivedBytes / totalBytes! * 100;

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'receivedBytes': receivedBytes,
        'totalBytes': totalBytes,
        'percent': percent,
      };
}

/// REAL: Client for the HuggingFace Hub: model search, GGUF listing, and resumable
/// downloads with sha256 verification. Real HTTP via [HttpClient].
class HuggingFaceClient {
  /// REAL: The api base.
  final String apiBase;
  final HttpClient _http = HttpClient();

  HuggingFaceClient({this.apiBase = 'https://huggingface.co'});

  /// REAL: Search models, biased to GGUF repos, sorted by downloads.
  Future<List<HfModel>> searchModels(String query,
      {int limit = 20}) async {
    /// REAL: The uri.
    final uri = Uri.parse('$apiBase/api/models').replace(queryParameters: {
      'search': query,
      'filter': 'gguf',
      'sort': 'downloads',
      'direction': '-1',
      'limit': limit.toString(),
    });
    /// REAL: The body.
    final body = await _getJson(uri);
    if (body is! List) {
      throw StateError('Unexpected HF search response shape');
    }
    return body
        .map((e) => HfModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .where((m) => m.id.isNotEmpty)
        .toList();
  }

  /// REAL: List the `.gguf` files of a repo (from the model metadata siblings).
  Future<List<GgufFile>> listGgufFiles(String repoId) async {
    /// REAL: The uri.
    final uri = Uri.parse('$apiBase/api/models/$repoId');
    /// REAL: The body.
    final body = await _getJson(uri);
    if (body is! Map<String, dynamic>) {
      throw StateError('Unexpected HF model response shape for $repoId');
    }
    /// REAL: The siblings.
    final siblings = body['siblings'] as List? ?? const [];
    /// REAL: The files.
    final files = <GgufFile>[];
    for (final raw in siblings) {
      /// REAL: The s.
      final s = Map<String, dynamic>.from(raw as Map);
      /// REAL: The name.
      final name = (s['rfilename'] as String?) ?? '';
      if (!name.toLowerCase().endsWith('.gguf')) continue;
      files.add(GgufFile(
        repoId: repoId,
        fileName: name,
        size: (s['size'] as int?),
        sha256: null, // siblings endpoint does not expose per-file sha256
      ));
    }
    files.sort((a, b) => (a.size ?? 0).compareTo(b.size ?? 0));
    return files;
  }

  /// REAL: Download [fileName] from [repoId] into [destDir], emitting progress.
  ///
  /// Resumes with HTTP `Range` when a partial file exists. When
  /// [expectedSha256] is provided the finished file is verified with
  /// [verifySha256] and a [StateError] is thrown on mismatch.
  Stream<DownloadProgress> downloadModel({
    required String repoId,
    required String fileName,
    required String destDir,
    String? expectedSha256,
  }) async* {
    /// REAL: The dir.
    final dir = Directory(destDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    /// REAL: The file.
    final file = File(p.join(dir.path, fileName));

    /// REAL: Starts.
    var start = 0;
    if (await file.exists()) {
      start = await file.length();
    }

    /// REAL: The request.
    final request =
        await _http.getUrl(Uri.parse('$apiBase/$repoId/resolve/main/$fileName'));
    request.headers.set('user-agent', 'NP-agent/0.1');
    if (start > 0) {
      request.headers.set('Range', 'bytes=$start-');
    }
    /// REAL: The response.
    final response = await request.close();

    if (response.statusCode == 416) {
      // Already fully downloaded.
      yield DownloadProgress(
          fileName: fileName, receivedBytes: start, totalBytes: start);
    } else if (response.statusCode != 200 && response.statusCode != 206) {
      throw StateError(
          'HF download failed (${response.statusCode}) for $repoId/$fileName');
    } else {
      /// REAL: The resumed.
      final resumed = response.statusCode == 206;
      /// REAL: The total.
      final total = _parseTotal(response, start, resumed);
      /// REAL: The sink.
      final sink = file.openWrite(
          mode: resumed ? FileMode.append : FileMode.write);
      /// REAL: The received.
      var received = resumed ? start : 0;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          yield DownloadProgress(
            fileName: fileName,
            receivedBytes: received,
            totalBytes: total,
          );
        }
      } finally {
        await sink.close();
      }
    }

    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      /// REAL: The ok.
      final ok = await verifySha256(file, expectedSha256);
      if (!ok) {
        throw StateError(
            'sha256 mismatch for $fileName: file may be corrupt; delete it and retry.');
      }
    }
  }

  /// REAL: Verify [file] against an expected hex sha256 digest (streaming, so it
  /// works for multi-GB model files without loading them into memory).
  Future<bool> verifySha256(File file, String expectedHex) async {
    /// REAL: The digest.
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() ==
        expectedHex.trim().toLowerCase();
  }

  /// REAL: Extract a `.zip` model bundle into [destDir] (real, via package:archive).
  static Future<void> extractZip(File zipFile, String destDir) async {
    /// REAL: The bytes.
    final bytes = await zipFile.readAsBytes();
    /// REAL: The archive.
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final entry in archive) {
      /// REAL: The out path.
      final outPath = p.join(destDir, entry.name);
      if (entry.isFile) {
        /// REAL: The out.
        final out = File(outPath);
        await out.parent.create(recursive: true);
        await out.writeAsBytes(entry.content as List<int>);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }
  }

  /// REAL: Closes.
  void close() => _http.close(force: true);

  // --- internals ------------------------------------------------------------

  Future<dynamic> _getJson(Uri uri) async {
    /// REAL: The request.
    final request = await _http.getUrl(uri);
    request.headers.set('user-agent', 'NP-agent/0.1');
    request.headers.set('accept', 'application/json');
    /// REAL: The response.
    final response = await request.close();
    if (response.statusCode != 200) {
      throw StateError(
          'HF API request failed (${response.statusCode}): $uri');
    }
    /// REAL: The body.
    final body = await response.transform(utf8.decoder).join();
    return jsonDecode(body);
  }

  int? _parseTotal(HttpClientResponse response, int start, bool resumed) {
    // Prefer Content-Range: "bytes 100-999/1234".
    /// REAL: The content range.
    final contentRange = response.headers.value('content-range');
    if (contentRange != null) {
      /// REAL: The m.
      final m = RegExp(r'/(\d+)\s*$').firstMatch(contentRange);
      if (m != null) return int.tryParse(m.group(1)!);
    }
    /// REAL: The length.
    final length = response.contentLength;
    if (length > 0) return resumed ? start + length : length;
    return null;
  }
}

/// REAL: Persists the repo-id -> local-path mapping so downloads survive restarts.
class ModelRegistry {
  final Map<String, String> _repoToLocal = {};

  /// REAL: Maps.
  void map(String repoId, String localPath) {
    _repoToLocal[repoId] = localPath;
  }

  String? lookup(String repoId) => _repoToLocal[repoId];

  /// REAL: The all.
  Map<String, String> get all => Map.unmodifiable(_repoToLocal);

  /// REAL: Removes.
  void remove(String repoId) => _repoToLocal.remove(repoId);

  /// REAL: Saves.
  Future<void> save(File file) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(_repoToLocal));
  }

  /// REAL: Loads.
  static Future<ModelRegistry> load(File file) async {
    /// REAL: The registry.
    final registry = ModelRegistry();
    if (await file.exists()) {
      try {
        /// REAL: The decoded.
        final decoded =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        decoded.forEach((k, v) => registry._repoToLocal[k] = v.toString());
      } catch (_) {
        // Corrupt registry file: start fresh rather than crash.
      }
    }
    return registry;
  }
}
