import 'dart:async';

import 'tts.dart';

/// MOCK: Simulated text-to-speech engine.
///
/// [speak] does not produce audio — it emits speaking/idle [TtsEvent]s over
/// a duration proportional to the text length and records what was "spoken".
/// Useful for wiring the speech pipeline and barge-in logic without Piper.
class MockTts implements TextToSpeech {
  final _events = StreamController<TtsEvent>.broadcast();
  TtsState _state = TtsState.idle;
  bool _stopped = false;

  /// MOCK: Every text passed to [speak], in order.
  final List<String> spokenTexts = [];

  /// MOCK: Simulated duration of the last utterance.
  Duration lastDuration = Duration.zero;

  @override
  Stream<TtsEvent> get events => _events.stream;

  @override
  TtsState get state => _state;

  /// MOCK: Fake speech — timed events, no audio output.
  @override
  Future<void> speak(String text, {String? utteranceId}) async {
    spokenTexts.add(text);
    _stopped = false;
    final id = utteranceId ?? 'mock_${DateTime.now().millisecondsSinceEpoch}';
    _set(TtsState.speaking, id, 0.0);
    // ~15 chars/sec in 5 progress steps; capped so tests stay fast.
    final totalMs = (text.length * 65).clamp(200, 3000);
    lastDuration = Duration(milliseconds: totalMs);
    const steps = 5;
    for (var i = 1; i <= steps && !_stopped; i++) {
      await Future.delayed(Duration(milliseconds: totalMs ~/ steps));
      if (!_stopped) _set(TtsState.speaking, id, i / steps);
    }
    _set(TtsState.idle, id, 1.0);
  }

  /// MOCK: Stop the fake utterance immediately.
  @override
  Future<void> stop() async {
    _stopped = true;
    _set(TtsState.idle, null, 1.0);
  }

  /// MOCK: Pause is a stop for the simulated engine.
  @override
  Future<void> pause() => stop();

  /// MOCK: Resume is a no-op for the simulated engine.
  @override
  Future<void> resume() async {}

  void _set(TtsState s, String? id, double progress) {
    _state = s;
    _events.add(TtsEvent(state: s, utteranceId: id, progress: progress));
  }

  /// MOCK: Release the event stream.
  void dispose() => _events.close();
}
