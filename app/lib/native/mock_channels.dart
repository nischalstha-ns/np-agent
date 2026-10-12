import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'channels.dart';
import 'png_encode.dart';

/// MOCK: Simulated microphone — emits synthetic PCM16 mono frames (a quiet
/// 440 Hz sine mixed with noise) at roughly real-time cadence.
class MockMicrophoneChannel implements MicrophoneChannel {
  final _frames = StreamController<Uint8List>.broadcast();
  Timer? _timer;
  bool _capturing = false;
  final _random = Random(42);

  @override
  String get channelName => 'np/microphone';

  @override
  Stream<Uint8List> get audioFrames => _frames.stream;

  @override
  bool get isCapturing => _capturing;

  /// MOCK: Start emitting synthetic audio frames (320 samples / 20 ms).
  @override
  Future<void> start({int sampleRateHz = 16000}) async {
    if (_capturing) return;
    _capturing = true;
    var phase = 0.0;
    _timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      final samples = Int16List(320);
      for (var i = 0; i < samples.length; i++) {
        phase += 2 * pi * 440 / sampleRateHz;
        final sine = (sin(phase) * 2000).toInt();
        final noise = (_random.nextDouble() * 400 - 200).toInt();
        samples[i] = (sine + noise).clamp(-32768, 32767);
      }
      _frames.add(samples.buffer.asUint8List());
    });
  }

  /// MOCK: Stop emitting frames.
  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _capturing = false;
  }
}

/// MOCK: Simulated STT engine — returns plausible canned transcriptions.
///
/// One-shot [transcribe] waits ~300 ms and returns a sentence derived from
/// the audio length (so different inputs give different outputs).
/// Streaming mode emits two partials then completes.
class MockSttEngineChannel implements SttEngineChannel {
  final _partials = StreamController<String>.broadcast();
  bool _streaming = false;

  @override
  String get channelName => 'np/stt';

  @override
  Stream<String> get partialResults => _partials.stream;

  /// MOCK: Fake one-shot transcription with a realistic delay.
  @override
  Future<SttEngineResult> transcribe(Uint8List audioBytes,
      {String language = 'en'}) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final seconds = (audioBytes.length / 2 / 16000);
    return SttEngineResult(
      text: 'This is a simulated transcription of about '
          '${seconds.toStringAsFixed(1)} seconds of audio '
          '(mock whisper.cpp engine, language $language).',
      confidence: 0.87,
    );
  }

  /// MOCK: Fake live transcription — emits partials on a timer.
  @override
  Future<void> startStream({String language = 'en'}) async {
    if (_streaming) return;
    _streaming = true;
    Future.delayed(const Duration(milliseconds: 400), () {
      if (_streaming) _partials.add('this is a simulated');
    });
    Future.delayed(const Duration(milliseconds: 900), () {
      if (_streaming) _partials.add('this is a simulated partial result');
    });
  }

  /// MOCK: End the fake stream with a final transcript.
  @override
  Future<String> stopStream() async {
    _streaming = false;
    await Future.delayed(const Duration(milliseconds: 150));
    return 'this is a simulated final transcription';
  }
}

/// MOCK: Simulated Piper TTS — "speaks" by emitting progress events over a
/// duration proportional to the text length, without producing audio.
class MockTtsEngineChannel implements TtsEngineChannel {
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  bool _speaking = false;

  @override
  String get channelName => 'np/tts';

  @override
  Stream<Map<String, dynamic>> get ttsEvents => _events.stream;

  /// MOCK: Fake speech — progress events paced like real TTS.
  @override
  Future<void> speak(String text,
      {String? voice, String? utteranceId}) async {
    _speaking = true;
    final id = utteranceId ?? 'utt_${DateTime.now().millisecondsSinceEpoch}';
    _events.add({'state': 'speaking', 'utteranceId': id, 'progress': 0.0});
    // ~15 chars/sec paced in 5 steps; capped so tests stay fast.
    final totalMs = (text.length * 65).clamp(200, 3000);
    const steps = 5;
    for (var i = 1; i <= steps && _speaking; i++) {
      await Future.delayed(Duration(milliseconds: totalMs ~/ steps));
      _events.add({
        'state': 'speaking',
        'utteranceId': id,
        'progress': i / steps,
      });
    }
    _speaking = false;
    _events.add({'state': 'idle', 'utteranceId': id, 'progress': 1.0});
  }

  /// MOCK: Stop the fake playback.
  @override
  Future<void> stop() async {
    _speaking = false;
    _events.add({'state': 'idle', 'progress': 1.0});
  }
}

/// MOCK: Simulated wake-word engine — never fires on its own; call
/// [simulateDetection] to trigger the [detections] stream on demand.
class MockWakeWordEngineChannel implements WakeWordEngineChannel {
  final _detections = StreamController<DateTime>.broadcast();
  bool _running = false;
  String _keyword = 'hey np';

  @override
  String get channelName => 'np/wakeword';

  @override
  String get keyword => _keyword;

  @override
  Stream<DateTime> get detections => _detections.stream;

  @override
  bool get isRunning => _running;

  /// MOCK: Mark the spotter running (no real audio analysis happens).
  @override
  Future<void> start({String keyword = 'hey np'}) async {
    _keyword = keyword;
    _running = true;
  }

  /// MOCK: Stop the fake spotter.
  @override
  Future<void> stop() async {
    _running = false;
  }

  /// MOCK: Fire a detection event on demand (tests / demos).
  void simulateDetection() {
    if (_running) _detections.add(DateTime.now());
  }
}

/// MOCK: Simulated OS control channel — applies input actions to a virtual
/// desktop state instead of the real OS.
///
/// The virtual desktop tracks mouse position, a typed-text log, pressed
/// keys, and "open" app windows. [captureScreen] synthesizes a valid PNG
/// (solid color with the virtual screen dimensions).
class MockOsControlChannel implements OsControlChannel {
  @override
  String get channelName => 'np/oscontrol';

  @override
  final String platformName;

  int _x = 0;
  int _y = 0;

  /// MOCK: Virtual desktop state (inspectable in tests).
  final List<String> typedLog = [];
  final List<String> pressedKeys = [];
  final List<String> clickedButtons = [];
  final Set<String> openApps = {};

  MockOsControlChannel({this.platformName = 'linux'});

  /// MOCK: Move the virtual mouse.
  @override
  Future<List<int>> mousePosition() async => [_x, _y];

  /// MOCK: Move the virtual mouse.
  @override
  Future<void> moveMouse(int x, int y) async {
    _x = x;
    _y = y;
  }

  /// MOCK: Record a virtual click.
  @override
  Future<void> click({String button = 'left'}) async {
    clickedButtons.add(button);
  }

  /// MOCK: Append to the virtual typed-text log.
  @override
  Future<void> typeText(String text) async {
    typedLog.add(text);
  }

  /// MOCK: Record a virtual key press.
  @override
  Future<void> pressKey(String key) async {
    pressedKeys.add(key);
  }

  /// MOCK: Record a virtual hotkey chord.
  @override
  Future<void> hotkey(List<String> keys) async {
    pressedKeys.add(keys.join('+'));
  }

  /// MOCK: Synthesize a valid 320x200 solid-color PNG (pure Dart).
  @override
  Future<Uint8List> captureScreen() async =>
      PngEncode.solidPng(320, 200, 0x2B, 0x3A, 0x55);
}

/// MOCK: Simulated llama.cpp inference — echoes prompts through canned
/// completions with word-by-word streaming, without any native library.
class MockLlamaEngineChannel implements LlamaEngineChannel {
  String? _modelPath;

  @override
  String get channelName => 'np/llama';

  @override
  bool get hasModelLoaded => _modelPath != null;

  /// MOCK: "Load" a model path (no native library involved).
  @override
  Future<void> loadModel(String path) async {
    await Future.delayed(const Duration(milliseconds: 100));
    _modelPath = path;
  }

  /// MOCK: Canned completion referencing the prompt.
  @override
  Future<String> generate(String prompt,
      {int maxTokens = 512, double temperature = 0.7}) async {
    final buf = StringBuffer();
    await for (final token in generateStreaming(prompt,
        maxTokens: maxTokens, temperature: temperature)) {
      buf.write(token);
    }
    return buf.toString();
  }

  /// MOCK: Word-by-word streaming with realistic delays.
  @override
  Stream<String> generateStreaming(String prompt,
      {int maxTokens = 512, double temperature = 0.7}) async* {
    if (_modelPath == null) {
      throw StateError('MockLlamaEngineChannel: no model loaded.');
    }
    final response = _cannedResponse(prompt);
    final words = response.split(' ');
    for (var i = 0; i < words.length; i++) {
      await Future.delayed(const Duration(milliseconds: 35));
      yield i == 0 ? words[i] : ' ${words[i]}';
    }
  }

  /// MOCK: "Unload" the fake model.
  @override
  Future<void> unloadModel() async {
    _modelPath = null;
  }

  String _cannedResponse(String prompt) {
    final lower = prompt.toLowerCase();
    if (lower.contains('hello') || lower.contains('hi')) {
      return 'Hello! I am NP running on the mock inference engine. '
          'No native llama.cpp library is linked in this build.';
    }
    final snippet =
        prompt.length > 60 ? '${prompt.substring(0, 60)}...' : prompt;
    return 'Mock inference result for: "$snippet". '
        'Link the real llama.cpp engine for actual generation.';
  }
}
