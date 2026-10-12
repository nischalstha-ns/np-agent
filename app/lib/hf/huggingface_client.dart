import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// A HuggingFace model repo (subset of the HF API model object).
class HfModel {
  final String id;
  final int downloads;
  final int likes;
  final String? sha;
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

/// One GGUF file inside a repo.
class GgufFile {
  final String repoId;
  final String fileName;
  final int? size;
  final String? sha256;

  const GgufFile({
    required this.repoId,
    required this.fileName,
    this.size,
    this.sha256,
  });

  /// Direct download URL for the file on the main branch.
  String downloadUrl(String apiBase) =>
      '$apiBase/$repoId/resolve/main/$fileName';

  Map<String, dynamic> toJson() => {
        'repoId': repoId,
        'fileName': fileName,
        'size': size,
        'sha256': sha256,
      };
}

/// Progress event emitted while downloading.
class DownloadProgress {
  final String fileName;
  final int receivedBytes;
  final int? totalBytes;

  const DownloadProgress({
    required this.fileName,
    required this.receivedBytes,
    this.totalBytes,
  });

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

/// Client for the HuggingFace Hub: model search, GGUF listing, and resumable
/// downloads with sha256 verification. Real HTTP via [HttpClient].
class HuggingFaceClient {
  final String apiBase;
  final HttpClient _http = HttpClient();

  HuggingFaceClient({this.apiBase = 'https://huggingface.co'});

  /// Search models, biased to GGUF repos, sorted by downloads.
  Future<List<HfModel>> searchModels(String query,
      {int limit = 20}) async {
    final uri = Uri.parse('$apiBase/api/models').replace(queryParameters: {
      'search': query,
      'filter': 'gguf',
      'sort': 'downloads',
      'direction': '-1',
      'limit': limit.toString(),
    });
    final body = await _getJson(uri);
    if (body is! List) {
      throw StateError('Unexpected HF search response shape');
    }
    return body
        .map((e) => HfModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .where((m) => m.id.isNotEmpty)
        .toList();
  }

  /// List the `.gguf` files of a repo (from the model metadata siblings).
  Future<List<GgufFile>> listGgufFiles(String repoId) async {
    final uri = Uri.parse('$apiBase/api/models/$repoId');
    final body = await _getJson(uri);
    if (body is! Map<String, dynamic>) {
      throw StateError('Unexpected HF model response shape for $repoId');
    }
    final siblings = body['siblings'] as List? ?? const [];
    final files = <GgufFile>[];
    for (final raw in siblings) {
      final s = Map<String, dynamic>.from(raw as Map);
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

  /// Download [fileName] from [repoId] into [destDir], emitting progress.
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
    final dir = Directory(destDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File(p.join(dir.path, fileName));

    var start = 0;
    if (await file.exists()) {
      start = await file.length();
    }

    final request =
        await _http.getUrl(Uri.parse('$apiBase/$repoId/resolve/main/$fileName'));
    request.headers.set('user-agent', 'NP-agent/0.1');
    if (start > 0) {
      request.headers.set('Range', 'bytes=$start-');
    }
    final response = await request.close();

    if (response.statusCode == 416) {
      // Already fully downloaded.
      yield DownloadProgress(
          fileName: fileName, receivedBytes: start, totalBytes: start);
    } else if (response.statusCode != 200 && response.statusCode != 206) {
      throw StateError(
          'HF download failed (${response.statusCode}) for $repoId/$fileName');
    } else {
      final resumed = response.statusCode == 206;
      final total = _parseTotal(response, start, resumed);
      final sink = file.openWrite(
          mode: resumed ? FileMode.append : FileMode.write);
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
      final ok = await verifySha256(file, expectedSha256);
      if (!ok) {
        throw StateError(
            'sha256 mismatch for $fileName: file may be corrupt; delete it and retry.');
      }
    }
  }

  /// Verify [file] against an expected hex sha256 digest (streaming, so it
  /// works for multi-GB model files without loading them into memory).
  Future<bool> verifySha256(File file, String expectedHex) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() ==
        expectedHex.trim().toLowerCase();
  }

  /// Extract a `.zip` model bundle into [destDir] (real, via package:archive).
  static Future<void> extractZip(File zipFile, String destDir) async {
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final entry in archive) {
      final outPath = p.join(destDir, entry.name);
      if (entry.isFile) {
        final out = File(outPath);
        await out.parent.create(recursive: true);
        await out.writeAsBytes(entry.content as List<int>);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }
  }

  void close() => _http.close(force: true);

  // --- internals ------------------------------------------------------------

  Future<dynamic> _getJson(Uri uri) async {
    final request = await _http.getUrl(uri);
    request.headers.set('user-agent', 'NP-agent/0.1');
    request.headers.set('accept', 'application/json');
    final response = await request.close();
    if (response.statusCode != 200) {
      throw StateError(
          'HF API request failed (${response.statusCode}): $uri');
    }
    final body = await response.transform(utf8.decoder).join();
    return jsonDecode(body);
  }

  int? _parseTotal(HttpClientResponse response, int start, bool resumed) {
    // Prefer Content-Range: "bytes 100-999/1234".
    final contentRange = response.headers.value('content-range');
    if (contentRange != null) {
      final m = RegExp(r'/(\d+)\s*$').firstMatch(contentRange);
      if (m != null) return int.tryParse(m.group(1)!);
    }
    final length = response.contentLength;
    if (length > 0) return resumed ? start + length : length;
    return null;
  }
}

/// Persists the repo-id -> local-path mapping so downloads survive restarts.
class ModelRegistry {
  final Map<String, String> _repoToLocal = {};

  void map(String repoId, String localPath) {
    _repoToLocal[repoId] = localPath;
  }

  String? lookup(String repoId) => _repoToLocal[repoId];

  Map<String, String> get all => Map.unmodifiable(_repoToLocal);

  void remove(String repoId) => _repoToLocal.remove(repoId);

  Future<void> save(File file) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(_repoToLocal));
  }

  static Future<ModelRegistry> load(File file) async {
    final registry = ModelRegistry();
    if (await file.exists()) {
      try {
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
