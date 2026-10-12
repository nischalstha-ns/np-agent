import 'tool.dart';

/// Interface-consistent stubs for media tools.
///
/// These expose the full six-layer [Tool] contract (real name, description,
/// schemas, permission policy) but [execute] throws [UnimplementedError]
/// because each one needs a native engine / plugin that is not part of this
/// scaffold:
/// - [ImageTool]  -> needs an image generation/editing engine (native plugin).
/// - [VideoTool]  -> needs a video synthesis engine (native plugin).
/// - [AudioTool]  -> needs an audio synthesis engine (native plugin).

abstract class _StubTool extends Tool {
  UnimplementedError get _missing =>
      UnimplementedError('$name.execute requires a native plugin/engine '
          'that is not bundled with this scaffold.');

  @override
  Future<PermissionDecision> checkPermission(ToolCall call) async =>
      PermissionDecision.denied('$name is not implemented in this build');

  @override
  Future<ToolResult> execute(ToolCall call) async => throw _missing;

  @override
  Future<bool> verify(ToolCall call, ToolResult result) async => false;
}

class ImageTool extends _StubTool {
  @override
  String get name => 'image';

  @override
  String get description =>
      'Generate or edit images from a text prompt (requires native image engine).';

  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['generate', 'edit'],
          'required': true,
        },
        'prompt': {'type': 'string', 'required': true},
        'size': {'type': 'string', 'required': false},
      };

  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'properties': {
          'imagePath': {'type': 'string'},
        },
      };
}

class VideoTool extends _StubTool {
  @override
  String get name => 'video';

  @override
  String get description =>
      'Generate or edit video clips (requires native video engine).';

  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['generate', 'edit'],
          'required': true,
        },
        'prompt': {'type': 'string', 'required': true},
        'durationSeconds': {'type': 'int', 'required': false},
      };

  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'properties': {
          'videoPath': {'type': 'string'},
        },
      };
}

class AudioTool extends _StubTool {
  @override
  String get name => 'audio';

  @override
  String get description =>
      'Synthesize or transform audio (requires native audio engine).';

  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['synthesize', 'transcribe'],
          'required': true,
        },
        'text': {'type': 'string', 'required': false},
        'audioPath': {'type': 'string', 'required': false},
      };

  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'properties': {
          'audioPath': {'type': 'string'},
          'transcript': {'type': 'string'},
        },
      };
}
