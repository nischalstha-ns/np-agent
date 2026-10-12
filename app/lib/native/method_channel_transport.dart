import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';

import 'channels.dart';

/// REAL: Flutter `MethodChannel` transport for the native channel contracts.
///
/// This is the production wiring: each contract in `channels.dart` is
/// implemented by forwarding to a platform-side `MethodChannel` with the
/// contract's [NpNativeChannel.channelName]. Platform code (Kotlin/Swift/C++)
/// implements the method side.
///
/// NOTE: this file imports `package:flutter/services.dart`, so it is only
/// usable in Flutter builds. It is intentionally NOT referenced by
/// `NpCore`, the mocks, or any pure-Dart entry point — `dart run` builds
/// must keep working without the Flutter engine.
class MethodChannelTransport {
  /// REAL: Build (or reuse) the MethodChannel for a contract name.
  static MethodChannel channelFor(String channelName) =>
      MethodChannel(channelName);

  /// REAL: Invoke a method and expect a JSON-ish map reply.
  static Future<Map<String, dynamic>> invokeMap(
      MethodChannel channel, String method,
      [Map<String, dynamic> args = const {}]) async {
    /// REAL: The raw.
    final raw = await channel.invokeMethod<dynamic>(method, args);
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return {'value': raw};
  }
}

/// REAL: [MicrophoneChannel] over `MethodChannel('np/microphone')`.
class MethodChannelMicrophone extends MicrophoneChannel {
  final MethodChannel _channel = MethodChannelTransport.channelFor('np/microphone');
  final EventChannel _events = const EventChannel('np/microphone/events');
  Stream<Uint8List>? _frames;
  bool _capturing = false;

  /// REAL: The audio frames.
  @override
  Stream<Uint8List> get audioFrames =>
      _frames ??= _events.receiveBroadcastStream().map((e) {
        if (e is Uint8List) return e;
        if (e is List) return Uint8List.fromList(e.cast<int>());
        return Uint8List(0);
      });

  /// REAL: Whether capturing.
  @override
  bool get isCapturing => _capturing;

  @override
  Future<void> start({int sampleRateHz = 16000}) async {
    await _channel.invokeMethod('start', {'sampleRateHz': sampleRateHz});
    _capturing = true;
  }

  /// REAL: Stops.
  @override
  Future<void> stop() async {
    await _channel.invokeMethod('stop');
    _capturing = false;
  }
}

/// REAL: [SttEngineChannel] over `MethodChannel('np/stt')`.
class MethodChannelSttEngine extends SttEngineChannel {
  final MethodChannel _channel = MethodChannelTransport.channelFor('np/stt');
  final EventChannel _events = const EventChannel('np/stt/events');
  Stream<String>? _partials;

  /// REAL: The partial results.
  @override
  Stream<String> get partialResults =>
      _partials ??= _events.receiveBroadcastStream().map((e) => '$e');

  @override
  Future<SttEngineResult> transcribe(Uint8List audioBytes,
      {String language = 'en'}) async {
    /// REAL: The reply.
    final reply = await MethodChannelTransport.invokeMap(_channel,
        'transcribe', {
      'audioBase64': base64Encode(audioBytes),
      'language': language,
    });
    return SttEngineResult(
      text: '${reply['text'] ?? ''}',
      confidence: (reply['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  Future<void> startStream({String language = 'en'}) =>
      _channel.invokeMethod('startStream', {'language': language});

  /// REAL: Stops stream.
  @override
  Future<String> stopStream() async {
    /// REAL: The reply.
    final reply = await MethodChannelTransport.invokeMap(
        _channel, 'stopStream');
    return '${reply['text'] ?? ''}';
  }
}

/// REAL: [TtsEngineChannel] over `MethodChannel('np/tts')`.
class MethodChannelTtsEngine extends TtsEngineChannel {
  final MethodChannel _channel = MethodChannelTransport.channelFor('np/tts');
  final EventChannel _events = const EventChannel('np/tts/events');
  Stream<Map<String, dynamic>>? _eventStream;

  /// REAL: The tts events.
  @override
  Stream<Map<String, dynamic>> get ttsEvents => _eventStream ??=
      _events.receiveBroadcastStream().map((e) => e is Map
          ? Map<String, dynamic>.from(e)
          : <String, dynamic>{'raw': e});

  @override
  Future<void> speak(String text,
      {String? voice, String? utteranceId}) =>
      _channel.invokeMethod('speak', {
        'text': text,
        if (voice != null) 'voice': voice,
        if (utteranceId != null) 'utteranceId': utteranceId,
      });

  /// REAL: Stops.
  @override
  Future<void> stop() => _channel.invokeMethod('stop');
}

/// REAL: [WakeWordEngineChannel] over `MethodChannel('np/wakeword')`.
class MethodChannelWakeWordEngine extends WakeWordEngineChannel {
  final MethodChannel _channel =
      MethodChannelTransport.channelFor('np/wakeword');
  final EventChannel _events = const EventChannel('np/wakeword/events');
  Stream<DateTime>? _detections;
  bool _running = false;
  String _keyword = 'hey np';

  /// REAL: The keyword.
  @override
  String get keyword => _keyword;

  /// REAL: The detections.
  @override
  Stream<DateTime> get detections => _detections ??= _events
      .receiveBroadcastStream()
      .map((_) => DateTime.now());

  /// REAL: Whether running.
  @override
  bool get isRunning => _running;

  @override
  Future<void> start({String keyword = 'hey np'}) async {
    _keyword = keyword;
    await _channel.invokeMethod('start', {'keyword': keyword});
    _running = true;
  }

  /// REAL: Stops.
  @override
  Future<void> stop() async {
    await _channel.invokeMethod('stop');
    _running = false;
  }
}

/// REAL: [OsControlChannel] over `MethodChannel('np/oscontrol')`.
class MethodChannelOsControl extends OsControlChannel {
  final MethodChannel _channel =
      MethodChannelTransport.channelFor('np/oscontrol');

  /// REAL: The platform name.
  @override
  final String platformName;

  MethodChannelOsControl({required this.platformName});

  /// REAL: The mouse position.
  @override
  Future<List<int>> mousePosition() async {
    /// REAL: The reply.
    final reply =
        await MethodChannelTransport.invokeMap(_channel, 'mousePosition');
    return [(reply['x'] as int? ?? 0), (reply['y'] as int? ?? 0)];
  }

  @override
  Future<void> moveMouse(int x, int y) =>
      _channel.invokeMethod('moveMouse', {'x': x, 'y': y});

  @override
  Future<void> click({String button = 'left'}) =>
      _channel.invokeMethod('click', {'button': button});

  @override
  Future<void> typeText(String text) =>
      _channel.invokeMethod('typeText', {'text': text});

  @override
  Future<void> pressKey(String key) =>
      _channel.invokeMethod('pressKey', {'key': key});

  @override
  Future<void> hotkey(List<String> keys) =>
      _channel.invokeMethod('hotkey', {'keys': keys});

  /// REAL: Captures screen.
  @override
  Future<Uint8List> captureScreen() async {
    /// REAL: The raw.
    final raw = await _channel.invokeMethod<dynamic>('captureScreen');
    if (raw is Uint8List) return raw;
    if (raw is String) return base64Decode(raw);
    throw StateError('Unexpected captureScreen reply: $raw');
  }
}

/// REAL: [LlamaEngineChannel] over `MethodChannel('np/llama')`.
class MethodChannelLlamaEngine extends LlamaEngineChannel {
  final MethodChannel _channel = MethodChannelTransport.channelFor('np/llama');
  final EventChannel _events = const EventChannel('np/llama/events');
  bool _loaded = false;

  /// REAL: Checks whether model loaded.
  @override
  bool get hasModelLoaded => _loaded;

  /// REAL: Loads model.
  @override
  Future<void> loadModel(String path) async {
    /// REAL: The reply.
    final reply =
        await MethodChannelTransport.invokeMap(_channel, 'loadModel', {
      'path': path,
    });
    _loaded = reply['loaded'] as bool? ?? false;
  }

  @override
  Future<String> generate(String prompt,
      {int maxTokens = 512, double temperature = 0.7}) async {
    /// REAL: The reply.
    final reply =
        await MethodChannelTransport.invokeMap(_channel, 'generate', {
      'prompt': prompt,
      'maxTokens': maxTokens,
      'temperature': temperature,
    });
    return '${reply['text'] ?? ''}';
  }

  @override
  Stream<String> generateStreaming(String prompt,
      {int maxTokens = 512, double temperature = 0.7}) async* {
    await _channel.invokeMethod('startGenerate', {
      'prompt': prompt,
      'maxTokens': maxTokens,
      'temperature': temperature,
    });
    await for (final event in _events.receiveBroadcastStream()) {
      if (event is Map && event['done'] == true) break;
      yield '${event is Map ? event['token'] : event}';
    }
  }

  /// REAL: The unload model.
  @override
  Future<void> unloadModel() async {
    await _channel.invokeMethod('unloadModel');
    _loaded = false;
  }
}
