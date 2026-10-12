library;

/// REAL: Method-channel contracts for every native-only capability in NP.
///
/// These abstract classes are the single source of truth for the native
/// boundary: each one names the Flutter `MethodChannel` (`channelName`) and
/// the methods/events a platform implementation must provide. Real platform
/// code (Kotlin/Swift/C++/ObjC) implements these over `MethodChannel`
/// (see `method_channel_transport.dart`); tests and pure-Dart runs use the
/// mocks in `mock_channels.dart`.
///
/// Covered capabilities:
/// - microphone capture ............ [MicrophoneChannel] (`np/microphone`)
/// - whisper.cpp / Vosk STT ........ [SttEngineChannel] (`np/stt`)
/// - Piper TTS ..................... [TtsEngineChannel] (`np/tts`)
/// - wake-word engine .............. [WakeWordEngineChannel] (`np/wakeword`)
/// - WinAPI / X11 / Cocoa / Android
///   desktop control ................ [OsControlChannel] (`np/oscontrol`)
/// - llama.cpp inference ........... [LlamaEngineChannel] (`np/llama`)
///
/// The contracts themselves are pure Dart (no flutter/services import), so
/// the rest of the app can depend on them in any build.

import 'dart:typed_data';

/// REAL: Base of every native channel contract — the channel name real
/// platform code binds to.
abstract class NpNativeChannel {
  /// REAL: The Flutter MethodChannel name, e.g. `np/microphone`.
  String get channelName;
}

/// REAL: Microphone capture contract (`np/microphone`).
///
/// Methods: `start` {sampleRateHz, channels} -> {started},
/// `stop` -> {stopped}. Audio frames arrive on the `audioFrames` event
/// channel as PCM16 mono bytes.
abstract class MicrophoneChannel extends NpNativeChannel {
  @override
  String get channelName => 'np/microphone';

  /// REAL: PCM16 mono audio frames while capturing.
  Stream<Uint8List> get audioFrames;

  /// REAL: True while the microphone is open.
  bool get isCapturing;

  /// REAL: Open the microphone; frames flow on [audioFrames].
  Future<void> start({int sampleRateHz = 16000});

  /// REAL: Close the microphone.
  Future<void> stop();
}

/// REAL: Speech-to-text engine contract (`np/stt`).
///
/// Backed by whisper.cpp or Vosk natively. Methods:
/// `transcribe` {audioBase64, language} -> {text, confidence},
/// `startStream`/`stopStream` for live mode with partial results on the
/// `partialResults` event channel.
abstract class SttEngineChannel extends NpNativeChannel {
  @override
  String get channelName => 'np/stt';

  /// REAL: Partial transcripts while streaming.
  Stream<String> get partialResults;

  /// REAL: One-shot transcription of PCM16 mono audio.
  Future<SttEngineResult> transcribe(Uint8List audioBytes,
      {String language = 'en'});

  /// REAL: Begin live transcription (partials on [partialResults]).
  Future<void> startStream({String language = 'en'});

  /// REAL: End live transcription; returns the final transcript.
  Future<String> stopStream();
}

/// REAL: One transcription result from the native STT engine.
class SttEngineResult {
  /// REAL: The recognized text.
  final String text;

  /// REAL: Engine confidence 0..1.
  final double confidence;

  const SttEngineResult({required this.text, this.confidence = 1.0});
}

/// REAL: Text-to-speech engine contract (`np/tts`).
///
/// Backed by Piper natively. Methods: `speak` {text, voice, utteranceId},
/// `stop`. Progress/completion arrive on the `ttsEvents` event channel as
/// `{state, utteranceId, progress}` maps.
abstract class TtsEngineChannel extends NpNativeChannel {
  @override
  String get channelName => 'np/tts';

  /// REAL: Raw TTS event maps from the native side.
  Stream<Map<String, dynamic>> get ttsEvents;

  /// REAL: Speak [text]; completes when the utterance finishes or stops.
  Future<void> speak(String text, {String? voice, String? utteranceId});

  /// REAL: Stop playback immediately.
  Future<void> stop();
}

/// REAL: Wake-word engine contract (`np/wakeword`).
///
/// Backed by openWakeWord/Porcupine natively. Methods: `start` {keyword},
/// `stop`. Detections arrive on the `detections` event channel.
abstract class WakeWordEngineChannel extends NpNativeChannel {
  @override
  String get channelName => 'np/wakeword';

  /// REAL: The keyword being spotted, e.g. `hey np`.
  String get keyword;

  /// REAL: Fires once per detection while running.
  Stream<DateTime> get detections;

  /// REAL: True while the spotter is listening.
  bool get isRunning;

  /// REAL: Start listening for [keyword].
  Future<void> start({String keyword = 'hey np'});

  /// REAL: Stop listening.
  Future<void> stop();
}

/// REAL: OS desktop-control contract (`np/oscontrol`).
///
/// Backed by WinAPI (SendInput/UIA), X11/XTest, Cocoa (CGEvent), or Android
/// (AccessibilityService) natively. Methods: `mousePosition`,
/// `moveMouse` {x, y}, `click` {button}, `typeText` {text}, `pressKey` {key},
/// `hotkey` {keys}, `captureScreen` -> PNG bytes (base64).
abstract class OsControlChannel extends NpNativeChannel {
  @override
  String get channelName => 'np/oscontrol';

  /// REAL: Platform this channel implementation drives.
  String get platformName;

  /// REAL: Current mouse position in screen pixels.
  Future<List<int>> mousePosition();

  /// REAL: Move the mouse to (x, y).
  Future<void> moveMouse(int x, int y);

  /// REAL: Click a mouse button (`left`/`right`/`middle`).
  Future<void> click({String button = 'left'});

  /// REAL: Type text via the OS input pipeline.
  Future<void> typeText(String text);

  /// REAL: Press a named key (`Enter`, `Tab`, `a`, ...).
  Future<void> pressKey(String key);

  /// REAL: Press a key chord (`['ctrl', 'c']`).
  Future<void> hotkey(List<String> keys);

  /// REAL: Capture the primary screen as PNG bytes.
  Future<Uint8List> captureScreen();
}

/// REAL: llama.cpp inference contract (`np/llama`).
///
/// The pure-Dart path uses dart:ffi directly (see `llama_bindings.dart`);
/// this channel covers platforms where inference must go through the host
/// (e.g. Android JNI service). Methods: `loadModel` {path} -> {loaded},
/// `generate` {prompt, maxTokens, temperature} -> {text},
/// `unloadModel`.
abstract class LlamaEngineChannel extends NpNativeChannel {
  @override
  String get channelName => 'np/llama';

  /// REAL: True when a model is loaded in the native engine.
  bool get hasModelLoaded;

  /// REAL: Load a GGUF model file into the native engine.
  Future<void> loadModel(String path);

  /// REAL: Generate a completion for [prompt].
  Future<String> generate(String prompt,
      {int maxTokens = 512, double temperature = 0.7});

  /// REAL: Stream completion tokens for [prompt].
  Stream<String> generateStreaming(String prompt,
      {int maxTokens = 512, double temperature = 0.7});

  /// REAL: Release the native model/context.
  Future<void> unloadModel();
}
