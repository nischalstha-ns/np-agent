import 'dart:async';

/// Text-to-speech contract.
///
/// Implementations need a native synthesis engine (Piper or the platform TTS
/// via a plugin); this file defines the contract only.
///
/// Barge-in: callers that support it should stop playback when
/// [SpeechController.userInterrupted] becomes true (see lib/voice/stt.dart).
enum TtsState { idle, speaking, paused }

class TtsEvent {
  final TtsState state;
  final String? utteranceId;
  final double progress; // 0..1 of the current utterance

  const TtsEvent({required this.state, this.utteranceId, this.progress = 0});

  Map<String, dynamic> toJson() => {
        'state': state.name,
        if (utteranceId != null) 'utteranceId': utteranceId,
        'progress': progress,
      };
}

abstract class TextToSpeech {
  /// State/progress events for the current and queued utterances.
  Stream<TtsEvent> get events;

  TtsState get state;

  /// Speak [text]. Completes when the utterance finishes or is stopped.
  /// [utteranceId] correlates events for this call.
  Future<void> speak(String text, {String? utteranceId});

  /// Stop playback immediately (used for barge-in).
  Future<void> stop();

  /// Pause/resume are optional; default implementations stop/start over.
  Future<void> pause() => stop();
  Future<void> resume() async {}
}

/// A no-op TTS used for wiring/tests: emits speaking->idle around a delay.
class NullTextToSpeech implements TextToSpeech {
  final _events = StreamController<TtsEvent>.broadcast();
  TtsState _state = TtsState.idle;

  @override
  Stream<TtsEvent> get events => _events.stream;

  @override
  TtsState get state => _state;

  @override
  Future<void> speak(String text, {String? utteranceId}) async {
    _set(TtsState.speaking, utteranceId);
    await Future.delayed(Duration(milliseconds: 50 * text.length.clamp(1, 40)));
    _set(TtsState.idle, utteranceId);
  }

  @override
  Future<void> stop() async => _set(TtsState.idle, null);

  void _set(TtsState s, String? id) {
    _state = s;
    _events.add(TtsEvent(state: s, utteranceId: id));
  }

  void dispose() => _events.close();
}
