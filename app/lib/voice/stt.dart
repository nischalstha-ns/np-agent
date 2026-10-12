import 'dart:async';
import 'dart:typed_data';

/// Speech-to-text contract.
///
/// Implementations need a native transcription engine (whisper.cpp or Vosk
/// via a platform plugin); this file defines the contract only.
///
/// Usage:
/// 1. `await stt.start()` (live mic) or `await stt.start(audioBytes: ...)`
///    (one-shot buffer);
/// 2. listen to [results] for partial (`isFinal: false`) and final results;
/// 3. `await stt.stop()` when done.
class SttResult {
  final String text;
  final bool isFinal;
  final double confidence;

  const SttResult({
    required this.text,
    required this.isFinal,
    this.confidence = 1.0,
  });

  Map<String, dynamic> toJson() =>
      {'text': text, 'isFinal': isFinal, 'confidence': confidence};
}

abstract class SpeechToText {
  /// Stream of partial and final transcription results while running.
  Stream<SttResult> get results;

  bool get isRunning;

  /// Start transcription. Pass [audioBytes] for one-shot buffer mode
  /// (PCM16 mono); omit for live microphone mode.
  Future<void> start({Uint8List? audioBytes, String language = 'en'});

  Future<void> stop();
}

/// Coordinates STT/TTS interaction, notably barge-in: when the user starts
/// speaking while NP is talking, the controller raises [userInterrupted] so
/// the TTS side can stop promptly.
///
/// Contract:
/// - [beginSpeaking] is called when TTS output starts,
/// - [endSpeaking] when it finishes or is interrupted,
/// - [signalUserSpeech] is called by the STT path on partial results;
///   when speaking and barge-in is enabled it sets [userInterrupted].
class SpeechController {
  final _interrupted = StreamController<bool>.broadcast();

  bool bargeInEnabled;
  bool _speaking = false;
  bool _userInterrupted = false;

  SpeechController({this.bargeInEnabled = true});

  bool get isSpeaking => _speaking;
  bool get userInterrupted => _userInterrupted;

  /// Fires true when the user barges in, false when speech (re)starts clean.
  Stream<bool> get onInterrupted => _interrupted.stream;

  void beginSpeaking() {
    _speaking = true;
    _userInterrupted = false;
    _interrupted.add(false);
  }

  void endSpeaking() {
    _speaking = false;
  }

  /// Called by the STT path whenever a partial/final result arrives.
  void signalUserSpeech(String partialText) {
    if (_speaking && bargeInEnabled && partialText.trim().isNotEmpty) {
      _userInterrupted = true;
      _interrupted.add(true);
    }
  }

  void dispose() => _interrupted.close();
}
