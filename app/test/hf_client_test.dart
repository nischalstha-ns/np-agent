// Tests for HuggingFaceClient against a local HttpServer (hermetic — no
// real network). NOTE: the client uses dart:io HttpClient internally, so
// package:http's MockClient cannot be injected; a loopback server fakes the
// HF API instead, exercising search, GGUF listing, downloads, progress,
// sha256 verification, zip extraction and the model registry.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:np/hf/huggingface_client.dart';

const _fakeBytes = 'FAKE-GGUF-BYTES-0123456789';

Future<HttpServer> _startServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final path = req.uri.path;
    if (path == '/api/models') {
      // search endpoint
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode([
        {
          'id': 'fake/tiny-gguf',
          'downloads': 1234,
          'likes': 56,
          'sha': 'abc123',
          'tags': ['gguf'],
        },
        {'id': '', 'downloads': 0}, // filtered out (empty id)
      ]));
    } else if (path.startsWith('/api/models/')) {
      // repo metadata endpoint
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({
        'id': 'fake/tiny-gguf',
        'siblings': [
          {'rfilename': 'tiny-Q4_K_M.gguf', 'size': 1024},
          {'rfilename': 'README.md', 'size': 100},
          {'rfilename': 'tiny-Q8_0.gguf', 'size': 2048},
        ],
      }));
    } else if (path == '/fake/tiny-gguf/resolve/main/tiny-Q4_K_M.gguf') {
      final bytes = utf8.encode(_fakeBytes);
      req.response.headers.contentType = ContentType.binary;
      req.response.headers.contentLength = bytes.length;
      req.response.add(bytes);
    } else {
      req.response.statusCode = 404;
      req.response.write('not found');
    }
    await req.response.close();
  });
  return server;
}

void main() {
  late HttpServer server;
  late HuggingFaceClient client;

  setUp(() async {
    server = await _startServer();
    client = HuggingFaceClient(apiBase: 'http://127.0.0.1:${server.port}');
  });

  tearDown(() async {
    client.close();
    await server.close(force: true);
  });

  group('HuggingFaceClient', () {
    test('searchModels parses fake JSON', () async {
      final models = await client.searchModels('tiny');
      expect(models.length, 1); // the empty-id entry is filtered out
      expect(models.first.id, 'fake/tiny-gguf');
      expect(models.first.downloads, 1234);
      expect(models.first.tags, contains('gguf'));
    });

    test('listGgufFiles filters to .gguf siblings, sorted by size', () async {
      final files = await client.listGgufFiles('fake/tiny-gguf');
      expect(files.length, 2);
      expect(files.map((f) => f.fileName),
          containsAll(['tiny-Q4_K_M.gguf', 'tiny-Q8_0.gguf']));
      expect(files.first.fileName, 'tiny-Q4_K_M.gguf'); // smaller first
      expect(files.first.size, 1024);
      expect(
        files.first.downloadUrl('http://127.0.0.1:${server.port}'),
        'http://127.0.0.1:${server.port}/fake/tiny-gguf/resolve/main/tiny-Q4_K_M.gguf',
      );
    });

    test('downloadModel writes bytes, emits progress, verifies sha256',
        () async {
      final dir =
          await Directory.systemTemp.createTemp('np-hf-dl-');
      addTearDown(() => dir.delete(recursive: true));

      final expected =
          sha256.convert(utf8.encode(_fakeBytes)).toString();

      final progress = <DownloadProgress>[];
      await client
          .downloadModel(
            repoId: 'fake/tiny-gguf',
            fileName: 'tiny-Q4_K_M.gguf',
            destDir: dir.path,
            expectedSha256: expected,
          )
          .forEach(progress.add);

      final file = File('${dir.path}/tiny-Q4_K_M.gguf');
      expect(await file.exists(), isTrue);
      expect(await file.readAsString(), _fakeBytes);
      expect(progress, isNotEmpty);
      final last = progress.last;
      expect(last.receivedBytes, utf8.encode(_fakeBytes).length);
      expect(last.percent, closeTo(100.0, 0.01));

      // direct verify helper agrees
      expect(await client.verifySha256(file, expected), isTrue);
      expect(await client.verifySha256(file, 'deadbeef'), isFalse);
    });

    test('downloadModel with wrong sha256 throws', () async {
      final dir =
          await Directory.systemTemp.createTemp('np-hf-bad-');
      addTearDown(() => dir.delete(recursive: true));

      await expectLater(
        client
            .downloadModel(
              repoId: 'fake/tiny-gguf',
              fileName: 'tiny-Q4_K_M.gguf',
              destDir: dir.path,
              expectedSha256: '00' * 32,
            )
            .drain(),
        throwsA(isA<StateError>()),
      );
    });

    test('downloadModel of a missing file throws', () async {
      final dir =
          await Directory.systemTemp.createTemp('np-hf-404-');
      addTearDown(() => dir.delete(recursive: true));

      await expectLater(
        client
            .downloadModel(
              repoId: 'fake/tiny-gguf',
              fileName: 'nope.gguf',
              destDir: dir.path,
            )
            .drain(),
        throwsA(isA<StateError>()),
      );
    });

    test('extractZip extracts a zip bundle', () async {
      final dir =
          await Directory.systemTemp.createTemp('np-hf-zip-');
      addTearDown(() => dir.delete(recursive: true));

      final content = utf8.encode('zip contents here');
      final archive = Archive()
        ..addFile(ArchiveFile('sub/hello.txt', content.length, content));
      final zipBytes = ZipEncoder().encode(archive)!;
      final zipFile = File('${dir.path}/bundle.zip');
      await zipFile.writeAsBytes(zipBytes);

      final dest = '${dir.path}/out';
      await HuggingFaceClient.extractZip(zipFile, dest);
      expect(await File('$dest/sub/hello.txt').readAsString(),
          'zip contents here');
    });
  });

  group('ModelRegistry', () {
    test('map/lookup/remove and save/load roundtrip', () async {
      final dir =
          await Directory.systemTemp.createTemp('np-hf-reg-');
      addTearDown(() => dir.delete(recursive: true));

      final registry = ModelRegistry();
      registry.map('fake/tiny-gguf', '/models/tiny.gguf');
      expect(registry.lookup('fake/tiny-gguf'), '/models/tiny.gguf');
      expect(registry.all, {'fake/tiny-gguf': '/models/tiny.gguf'});
      registry.remove('fake/tiny-gguf');
      expect(registry.lookup('fake/tiny-gguf'), isNull);

      registry.map('a/b', '/x/y.gguf');
      final file = File('${dir.path}/registry.json');
      await registry.save(file);
      final loaded = await ModelRegistry.load(file);
      expect(loaded.lookup('a/b'), '/x/y.gguf');

      // corrupt registry file loads as empty rather than throwing
      await file.writeAsString('not json {{{');
      final fresh = await ModelRegistry.load(file);
      expect(fresh.all, isEmpty);
    });
  });

  group('HF value objects', () {
    test('HfModel.fromJson defaults', () {
      final m = HfModel.fromJson({});
      expect(m.id, '');
      expect(m.downloads, 0);
      expect(m.likes, 0);
      expect(m.sha, isNull);
      expect(m.tags, isEmpty);
    });

    test('DownloadProgress.percent', () {
      const p = DownloadProgress(
          fileName: 'f', receivedBytes: 50, totalBytes: 200);
      expect(p.percent, 25.0);
      const unknown =
          DownloadProgress(fileName: 'f', receivedBytes: 10);
      expect(unknown.percent, isNull);
    });

    test('GgufFile.toJson roundtrip', () {
      const f = GgufFile(
          repoId: 'a/b', fileName: 'm.gguf', size: 10, sha256: 'ff');
      final back = f.toJson();
      expect(back['fileName'], 'm.gguf');
      expect(back['size'], 10);
    });
  });
}
