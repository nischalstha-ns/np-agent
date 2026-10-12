import 'dart:async';
import 'dart:typed_data';

import 'stt.dart';

/// MOCK: Simulated speech-to-text engine.
///
/// [start] emits one partial result and then a final result after short
/// realistic delays; the final text is derived from the input size so
/// different inputs produce different outputs. No audio is really decoded.
class MockStt implements SpeechToText {
  final _results = StreamController<SttResult>.broadcast();
  bool _running = false;

  /// MOCK: The last final transcript produced (inspectable in tests).
  String lastTranscript = '';

  @override
  Stream<SttResult> get results => _results.stream;

  @override
  bool get isRunning => _running;

  /// MOCK: Fake transcription run — partial + final results on a timer.
  @override
  Future<void> start({Uint8List? audioBytes, String language = 'en'}) async {
    if (_running) return;
    _running = true;
    final seconds = audioBytes == null
        ? 1.0
        : (audioBytes.length / 2 / 16000).clamp(0.5, 30.0);
    Future.delayed(const Duration(milliseconds: 250), () {
      if (_running) {
        _results.add(const SttResult(
            text: 'simulated partial...', isFinal: false, confidence: 0.6));
      }
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (_running) {
        lastTranscript = 'This is a simulated transcription of about '
            '${seconds.toStringAsFixed(1)} seconds of audio '
            '(MockStt, language $language).';
        _results.add(SttResult(
            text: lastTranscript, isFinal: true, confidence: 0.87));
      }
    });
  }

  /// MOCK: Stop the fake transcription run.
  @override
  Future<void> stop() async {
    _running = false;
  }
}
