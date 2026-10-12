// Tests for ImageTool/VideoTool/AudioTool: metadata probing is real,
// transforms go through the (mock) media engine or fail honestly.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:np/tools/media_tools.dart';
import 'package:np/tools/tool.dart';

// 1x1 transparent PNG.
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

void main() {
  group('ImageTool', () {
    late Directory root;
    late String pngPath;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('np-media-');
      pngPath = '${root.path}/tiny.png';
      await File(pngPath).writeAsBytes(base64Decode(_pngBase64));
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('info probes real PNG dimensions', () async {
      final tool = ImageTool();
      final result = await tool.execute(
          ToolCall(tool: 'image', action: 'info', args: {'path': pngPath}));
      expect(result.success, isTrue);
      final data = result.data as Map;
      expect(data['format'], 'png');
      expect(data['width'], 1);
      expect(data['height'], 1);
      expect(data['sizeBytes'], greaterThan(0));
      expect((await tool.checkPermission(
              ToolCall(tool: 'image', action: 'info', args: {})))
          .isAllowed, isTrue);
    });

    test('info on missing file fails', () async {
      final tool = ImageTool();
      final result = await tool.execute(ToolCall(
          tool: 'image', action: 'info', args: {'path': '${root.path}/no.png'}));
      expect(result.success, isFalse);
    });

    test('resize works through the mock engine', () async {
      final tool = ImageTool(engine: MockMediaEngine());
      final out = '${root.path}/resized.png';
      final result = await tool.execute(ToolCall(
          tool: 'image',
          action: 'resize',
          args: {'path': pngPath, 'outputPath': out, 'width': 64, 'height': 64}));
      expect(result.success, isTrue);
      expect(await File(out).exists(), isTrue);
      // mock engine leaves an honest sidecar describing the fake transform
      expect(await File('$out.np-mock.json').exists(), isTrue);
    });

    test('resize without an engine fails honestly', () async {
      final tool = ImageTool();
      final result = await tool.execute(ToolCall(
          tool: 'image',
          action: 'resize',
          args: {
            'path': pngPath,
            'outputPath': '${root.path}/r.png',
            'width': 64,
            'height': 64
          }));
      expect(result.success, isFalse);
      expect(result.error, contains('native codec'));
    });

    test('convert through the mock engine', () async {
      final tool = ImageTool(engine: MockMediaEngine());
      final out = '${root.path}/tiny.jpg';
      final result = await tool.execute(ToolCall(
          tool: 'image',
          action: 'convert',
          args: {'path': pngPath, 'outputPath': out, 'format': 'jpeg'}));
      expect(result.success, isTrue);
      expect(await File(out).exists(), isTrue);
    });
  });

  group('VideoTool', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('np-video-');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('transcode without engine fails honestly', () async {
      final tool = VideoTool();
      final result = await tool.execute(ToolCall(
          tool: 'video',
          action: 'transcode',
          args: {'path': '${root.path}/in.mp4', 'outputPath': '${root.path}/o.mp4'}));
      expect(result.success, isFalse);
      expect(result.error, contains('native codec'));
    });

    test('transcode through the mock engine writes a placeholder', () async {
      final tool = VideoTool(engine: MockMediaEngine());
      final out = '${root.path}/out.mp4';
      final result = await tool.execute(ToolCall(
          tool: 'video',
          action: 'transcode',
          args: {'path': '${root.path}/in.mp4', 'outputPath': out}));
      expect(result.success, isTrue);
      final text = await File(out).readAsString();
      expect(text, contains('MOCK'));
    });

    test('transcode needs approval', () async {
      final tool = VideoTool(engine: MockMediaEngine());
      final decision = await tool.checkPermission(const ToolCall(
          tool: 'video', action: 'transcode', args: {}));
      expect(decision.needsApproval, isTrue);
    });
  });

  group('AudioTool', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('np-audio-');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('info probes file size', () async {
      final tool = AudioTool();
      final wav = '${root.path}/tone.wav';
      await File(wav).writeAsBytes(List<int>.filled(100, 0));
      final result = await tool.execute(
          ToolCall(tool: 'audio', action: 'info', args: {'path': wav}));
      expect(result.success, isTrue);
      expect((result.data as Map)['sizeBytes'], 100);
    });

    test('synthesize without engine fails honestly', () async {
      final tool = AudioTool();
      final result = await tool.execute(ToolCall(
          tool: 'audio',
          action: 'synthesize',
          args: {'text': 'hello', 'outputPath': '${root.path}/out.wav'}));
      expect(result.success, isFalse);
      expect(result.error, contains('native'));
    });

    test('synthesize through the mock engine writes a placeholder', () async {
      final tool = AudioTool(engine: MockMediaEngine());
      final out = '${root.path}/out.wav';
      final result = await tool.execute(ToolCall(
          tool: 'audio',
          action: 'synthesize',
          args: {'text': 'hello np', 'outputPath': out}));
      expect(result.success, isTrue);
      expect(await File(out).exists(), isTrue);
    });
  });
}
