import 'dart:async';

/// REAL: Text-to-speech contract.
///
/// Implementations need a native synthesis engine (Piper or the platform TTS
/// via a plugin); this file defines the contract only.
///
/// Barge-in: callers that support it should stop playback when
/// [SpeechController.userInterrupted] becomes true (see lib/voice/stt.dart).
enum TtsState { idle, speaking, paused }

/// REAL: State/progress event for a TTS utterance.
class TtsEvent {
  /// REAL: The state.
  final TtsState state;
  /// REAL: The utterance id.
  final String? utteranceId;
  /// REAL: The progress.
  final double progress; // 0..1 of the current utterance

  const TtsEvent({required this.state, this.utteranceId, this.progress = 0});

  Map<String, dynamic> toJson() => {
        'state': state.name,
        if (utteranceId != null) 'utteranceId': utteranceId,
        'progress': progress,
      };
}

/// REAL: Text-to-speech contract.
abstract class TextToSpeech {
  /// REAL: State/progress events for the current and queued utterances.
  Stream<TtsEvent> get events;

  /// REAL: The state.
  TtsState get state;

  /// REAL: Speak [text]. Completes when the utterance finishes or is stopped.
  /// [utteranceId] correlates events for this call.
  Future<void> speak(String text, {String? utteranceId});

  /// REAL: Stop playback immediately (used for barge-in).
  Future<void> stop();

  /// REAL: Pause/resume are optional; default implementations stop/start over.
  Future<void> pause() => stop();
  /// REAL: The resume.
  Future<void> resume() async {}
}

/// MOCK: A no-op TTS used for wiring/tests: emits speaking->idle around a delay.
class NullTextToSpeech implements TextToSpeech {
  final _events = StreamController<TtsEvent>.broadcast();
  TtsState _state = TtsState.idle;

  /// MOCK: The events.
  @override
  Stream<TtsEvent> get events => _events.stream;

  /// MOCK: The state.
  @override
  TtsState get state => _state;

  @override
  Future<void> speak(String text, {String? utteranceId}) async {
    _set(TtsState.speaking, utteranceId);
    await Future.delayed(Duration(milliseconds: 50 * text.length.clamp(1, 40)));
    _set(TtsState.idle, utteranceId);
  }

  /// MOCK: Stops.
  @override
  Future<void> stop() async => _set(TtsState.idle, null);

  /// MOCK: Pause is a stop for the no-op engine.
  @override
  Future<void> pause() => stop();

  /// MOCK: Resume is a no-op for the no-op engine.
  @override
  Future<void> resume() async {}

  void _set(TtsState s, String? id) {
    _state = s;
    _events.add(TtsEvent(state: s, utteranceId: id));
  }

  /// MOCK: Disposes.
  void dispose() => _events.close();
}
