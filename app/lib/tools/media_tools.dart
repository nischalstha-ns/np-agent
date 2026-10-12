import 'dart:io';
import 'dart:typed_data';

import 'tool.dart';

/// REAL: Method-channel contract for native media engines.
///
/// Real implementations forward these calls over a Flutter `MethodChannel`
/// (channel `np/media`, methods `image.resize`, `image.convert`,
/// `video.transcode`, `audio.synthesize`, ...). In pure-Dart builds the
/// [MockMediaEngine] below simulates them instead.
///
/// Pixel/codec work genuinely needs native codecs (libpng/libjpeg,
/// FFmpeg, Piper) — there is no pure-Dart transcoder in this build, which
/// is why transforms go through this interface.
abstract class MediaEngineChannel {
  /// REAL: Channel name real implementations bind to (`np/media`).
  String get channelName => 'np/media';

  /// REAL: Resize an image; returns the output path.
  Future<String> resizeImage(String inputPath, String outputPath,
      {required int width, required int height});

  /// REAL: Convert an image between formats (png/jpeg); returns output path.
  Future<String> convertImage(
      String inputPath, String outputPath, String format);

  /// REAL: Transcode a video clip; returns the output path.
  Future<String> transcodeVideo(String inputPath, String outputPath,
      {String? preset});

  /// REAL: Synthesize speech audio from text; returns the output wav path.
  Future<String> synthesizeAudio(String text, String outputPath,
      {String? voice});
}

/// MOCK: Simulated media engine — behaves like a native codec without doing
/// real pixel/codec work.
///
/// - `resizeImage`/`convertImage`: copies the input to the output path and
///   records the requested transform in a `.np-mock.json` sidecar, so
///   callers can verify the plumbing end-to-end.
/// - `transcodeVideo`/`synthesizeAudio`: writes a small placeholder file and
///   reports it honestly as simulated output.
class MockMediaEngine implements MediaEngineChannel {
  @override
  String get channelName => 'np/media';

  /// MOCK: Fake resize — copies the file and notes the requested size.
  @override
  Future<String> resizeImage(String inputPath, String outputPath,
      {required int width, required int height}) async {
    await _copyWithSidecar(inputPath, outputPath, {
      'mockTransform': 'resize',
      'width': width,
      'height': height,
    });
    return outputPath;
  }

  /// MOCK: Fake convert — copies the file and notes the requested format.
  @override
  Future<String> convertImage(
      String inputPath, String outputPath, String format) async {
    await _copyWithSidecar(inputPath, outputPath, {
      'mockTransform': 'convert',
      'format': format,
    });
    return outputPath;
  }

  /// MOCK: Fake transcode — writes a placeholder and says so.
  @override
  Future<String> transcodeVideo(String inputPath, String outputPath,
      {String? preset}) async {
    final out = File(outputPath);
    await out.parent.create(recursive: true);
    await out.writeAsString(
        'MOCK video transcode of $inputPath (preset=$preset). '
        'Not a real video file.');
    return outputPath;
  }

  /// MOCK: Fake synthesis — writes a placeholder and says so.
  @override
  Future<String> synthesizeAudio(String text, String outputPath,
      {String? voice}) async {
    final out = File(outputPath);
    await out.parent.create(recursive: true);
    await out.writeAsString(
        'MOCK audio synthesis (voice=$voice): "$text". Not real audio.');
    return outputPath;
  }

  Future<void> _copyWithSidecar(
      String inputPath, String outputPath, Map<String, Object?> note) async {
    final src = File(inputPath);
    if (!await src.exists()) {
      throw StateError('Input file not found: $inputPath');
    }
    final out = File(outputPath);
    await out.parent.create(recursive: true);
    await src.copy(outputPath);
    await File('$outputPath.np-mock.json').writeAsString(
        note.entries.map((e) => '${e.key}=${e.value}').join('\n'));
  }
}

/// REAL: Shared probing helpers — PNG/JPEG dimension parsing in pure Dart.
class MediaProbe {
  /// REAL: File size in bytes, or -1 when the file is missing.
  static Future<int> fileSize(String path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return -1;
    }
  }

  /// REAL: Parse image dimensions from PNG/JPEG headers (pure Dart).
  /// Returns {'width', 'height', 'format'} or {'format': 'unknown'}.
  static Future<Map<String, dynamic>> imageDimensions(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('File not found: $path');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length < 24) return {'format': 'unknown'};
    // PNG: 8-byte signature, then IHDR chunk with width/height (big-endian).
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      final width = _u32be(bytes, 16);
      final height = _u32be(bytes, 20);
      return {'format': 'png', 'width': width, 'height': height};
    }
    // JPEG: scan markers for a SOF segment holding height/width.
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      final dims = _jpegDimensions(bytes);
      if (dims != null) {
        return {
          'format': 'jpeg',
          'width': dims[0],
          'height': dims[1],
        };
      }
      return {'format': 'jpeg'};
    }
    return {'format': 'unknown'};
  }

  static int _u32be(Uint8List b, int offset) =>
      (b[offset] << 24) |
      (b[offset + 1] << 16) |
      (b[offset + 2] << 8) |
      b[offset + 3];

  /// REAL: Walk JPEG markers to the first Start-Of-Frame segment.
  static List<int>? _jpegDimensions(Uint8List bytes) {
    var i = 2;
    while (i + 8 < bytes.length) {
      if (bytes[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = bytes[i + 1];
      // SOF0..SOF3, SOF5..SOF7, SOF9..SOF11, SOF13..SOF15 (not DHT/DAC).
      final isSof = (marker >= 0xC0 && marker <= 0xCF) &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isSof) {
        final height = (bytes[i + 5] << 8) | bytes[i + 6];
        final width = (bytes[i + 7] << 8) | bytes[i + 8];
        return [width, height];
      }
      if (marker == 0xD8 || marker == 0xD9) {
        i += 2;
        continue;
      }
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        i += 2;
        continue;
      }
      final len = (bytes[i + 2] << 8) | bytes[i + 3];
      if (len < 2) return null;
      i += 2 + len;
    }
    return null;
  }
}

abstract class _MediaTool extends Tool {
  /// The native engine; null means "no codec available in this build".
  MediaEngineChannel? get engine;

  UnimplementedError get _noEngine => UnimplementedError(
      '$name transform requires a native codec/engine, which is not '
      'bundled in this build. Probing actions (info) work; attach a '
      'MediaEngineChannel implementation to enable transforms.');

  Future<Map<String, dynamic>> _probe(String path) async {
    final size = await MediaProbe.fileSize(path);
    if (size < 0) throw StateError('File not found: $path');
    final dims = await MediaProbe.imageDimensions(path);
    return {
      'path': path,
      'sizeBytes': size,
      ...dims,
    };
  }
}

/// REAL: Image probing (real PNG/JPEG header parsing); transforms need a
/// native engine via [MediaEngineChannel] and fail honestly without one.
///
/// Actions:
/// - `info`    {path}                          -> {sizeBytes, format,
///   width?, height?}
/// - `resize`  {path, outputPath, width, height} -> {outputPath} (engine)
/// - `convert` {path, outputPath, format}       -> {outputPath} (engine)
class ImageTool extends _MediaTool {
  @override
  final MediaEngineChannel? engine;

  ImageTool({this.engine});

  @override
  String get name => 'image';

  @override
  String get description =>
      'Probe image files (real PNG/JPEG dimension + size parsing). '
      'Resize/convert need a native media engine; without one they fail '
      'with an honest "transform requires native codec" error.';

  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['info', 'resize', 'convert'],
          'required': true,
        },
        'path': {'type': 'string', 'required': true},
        'outputPath': {'type': 'string', 'required': false},
        'width': {'type': 'int', 'required': false},
        'height': {'type': 'int', 'required': false},
        'format': {'type': 'string', 'required': false},
      };

  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'description': 'info -> {sizeBytes, format, width?, height?}; '
            'resize/convert -> {outputPath}',
      };

  /// REAL: Probing is open; transforms need approval (new file output).
  @override
  Future<PermissionDecision> checkPermission(ToolCall call) async {
    switch (call.action) {
      case 'info':
        return const PermissionDecision.allowed('image probing');
      case 'resize':
      case 'convert':
        return const PermissionDecision.needsApproval(
            'image transform writes a new file');
      default:
        return PermissionDecision.denied('Unknown image action "${call.action}"');
    }
  }

  @override
  Future<ToolResult> execute(ToolCall call) async {
    try {
      final path = (call.args['path'] as String?) ?? '';
      switch (call.action) {
        case 'info':
          return ToolResult.ok(await _probe(path));
        case 'resize':
        case 'convert': {
          final eng = engine;
          if (eng == null) return ToolResult.fail(_noEngine.toString());
          final outputPath = (call.args['outputPath'] as String? ?? '').trim();
          if (outputPath.isEmpty) {
            return ToolResult.fail(
                'image.${call.action} requires "outputPath"');
          }
          final out = call.action == 'resize'
              ? await eng.resizeImage(path, outputPath,
                  width: (call.args['width'] as int?) ?? 0,
                  height: (call.args['height'] as int?) ?? 0)
              : await eng.convertImage(path, outputPath,
                  (call.args['format'] as String? ?? 'png'));
          return ToolResult.ok({'outputPath': out});
        }
        default:
          return ToolResult.fail('Unknown image action "${call.action}"');
      }
    } catch (e) {
      return ToolResult.fail('image.${call.action} failed: $e');
    }
  }

  @override
  Future<bool> verify(ToolCall call, ToolResult result) async {
    if (!result.success) return true;
    final data = result.data as Map?;
    if (data == null) return false;
    if (call.action == 'info') return data['sizeBytes'] is int;
    return data['outputPath'] is String;
  }
}

/// REAL: Video probing (file size; container parsing needs native FFmpeg).
/// Transcoding needs a [MediaEngineChannel] and fails honestly without one.
///
/// Actions:
/// - `info`      {path}                    -> {sizeBytes}
/// - `transcode` {path, outputPath, preset?} -> {outputPath} (engine)
class VideoTool extends _MediaTool {
  @override
  final MediaEngineChannel? engine;

  VideoTool({this.engine});

  @override
  String get name => 'video';

  @override
  String get description =>
      'Probe video files (size; container metadata needs native FFmpeg). '
      'Transcoding needs a native media engine; without one it fails with '
      'an honest "transform requires native codec" error.';

  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['info', 'transcode'],
          'required': true,
        },
        'path': {'type': 'string', 'required': true},
        'outputPath': {'type': 'string', 'required': false},
        'preset': {'type': 'string', 'required': false},
      };

  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'description': 'info -> {sizeBytes}; transcode -> {outputPath}',
      };

  /// REAL: Probing is open; transcode needs approval (new file output).
  @override
  Future<PermissionDecision> checkPermission(ToolCall call) async {
    switch (call.action) {
      case 'info':
        return const PermissionDecision.allowed('video probing');
      case 'transcode':
        return const PermissionDecision.needsApproval(
            'video transcode writes a new file');
      default:
        return PermissionDecision.denied('Unknown video action "${call.action}"');
    }
  }

  @override
  Future<ToolResult> execute(ToolCall call) async {
    try {
      final path = (call.args['path'] as String?) ?? '';
      switch (call.action) {
        case 'info': {
          final size = await MediaProbe.fileSize(path);
          if (size < 0) throw StateError('File not found: $path');
          return ToolResult.ok({
            'path': path,
            'sizeBytes': size,
            'note': 'Container metadata (duration, codecs) needs native FFmpeg.',
          });
        }
        case 'transcode': {
          final eng = engine;
          if (eng == null) return ToolResult.fail(_noEngine.toString());
          final outputPath = (call.args['outputPath'] as String? ?? '').trim();
          if (outputPath.isEmpty) {
            return ToolResult.fail('video.transcode requires "outputPath"');
          }
          final out = await eng.transcodeVideo(path, outputPath,
              preset: call.args['preset'] as String?);
          return ToolResult.ok({'outputPath': out});
        }
        default:
          return ToolResult.fail('Unknown video action "${call.action}"');
      }
    } catch (e) {
      return ToolResult.fail('video.${call.action} failed: $e');
    }
  }

  @override
  Future<bool> verify(ToolCall call, ToolResult result) async {
    if (!result.success) return true;
    final data = result.data as Map?;
    if (data == null) return false;
    if (call.action == 'info') return data['sizeBytes'] is int;
    return data['outputPath'] is String;
  }
}

/// REAL: Audio probing (file size; codec metadata needs a native engine).
/// Synthesis needs a [MediaEngineChannel] and fails honestly without one.
///
/// Actions:
/// - `info`       {path}                  -> {sizeBytes}
/// - `synthesize` {text, outputPath, voice?} -> {outputPath} (engine)
class AudioTool extends _MediaTool {
  @override
  final MediaEngineChannel? engine;

  AudioTool({this.engine});

  @override
  String get name => 'audio';

  @override
  String get description =>
      'Probe audio files (size; codec metadata needs a native engine). '
      'Speech synthesis needs a native media engine; without one it fails '
      'with an honest "transform requires native codec" error.';

  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['info', 'synthesize'],
          'required': true,
        },
        'path': {'type': 'string', 'required': false},
        'text': {'type': 'string', 'required': false},
        'outputPath': {'type': 'string', 'required': false},
        'voice': {'type': 'string', 'required': false},
      };

  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'description': 'info -> {sizeBytes}; synthesize -> {outputPath}',
      };

  /// REAL: Probing is open; synthesis needs approval (new file output).
  @override
  Future<PermissionDecision> checkPermission(ToolCall call) async {
    switch (call.action) {
      case 'info':
        return const PermissionDecision.allowed('audio probing');
      case 'synthesize':
        return const PermissionDecision.needsApproval(
            'audio synthesis writes a new file');
      default:
        return PermissionDecision.denied('Unknown audio action "${call.action}"');
    }
  }

  @override
  Future<ToolResult> execute(ToolCall call) async {
    try {
      switch (call.action) {
        case 'info': {
          final path = (call.args['path'] as String?) ?? '';
          final size = await MediaProbe.fileSize(path);
          if (size < 0) throw StateError('File not found: $path');
          return ToolResult.ok({
            'path': path,
            'sizeBytes': size,
            'note': 'Codec metadata (duration, sample rate) needs a native engine.',
          });
        }
        case 'synthesize': {
          final eng = engine;
          if (eng == null) return ToolResult.fail(_noEngine.toString());
          final text = (call.args['text'] as String? ?? '').trim();
          final outputPath = (call.args['outputPath'] as String? ?? '').trim();
          if (text.isEmpty || outputPath.isEmpty) {
            return ToolResult.fail(
                'audio.synthesize requires "text" and "outputPath"');
          }
          final out = await eng.synthesizeAudio(text, outputPath,
              voice: call.args['voice'] as String?);
          return ToolResult.ok({'outputPath': out});
        }
        default:
          return ToolResult.fail('Unknown audio action "${call.action}"');
      }
    } catch (e) {
      return ToolResult.fail('audio.${call.action} failed: $e');
    }
  }

  @override
  Future<bool> verify(ToolCall call, ToolResult result) async {
    if (!result.success) return true;
    final data = result.data as Map?;
    if (data == null) return false;
    if (call.action == 'info') return data['sizeBytes'] is int;
    return data['outputPath'] is String;
  }
}
