import 'dart:typed_data';

import '../voice/stt.dart';
import '../voice/tts.dart';
import 'agent.dart';

/// Speech stage: speech-to-text and text-to-speech.
///
/// Real orchestration logic around optional native engines:
/// - when `ctx.metadata['audioBytes']` is present and an [SpeechToText]
///   engine is attached, it transcribes and returns the transcript;
/// - when `ctx.metadata['speak']` is present and a [TextToSpeech] engine is
///   attached, it speaks the text (barge-in aware via [SpeechController]);
/// - otherwise it reports status honestly.
///
/// Native engines needed: whisper.cpp/vosk for STT, Piper (or platform TTS)
/// for TTS. See lib/voice for the contracts.
class SpeechAgent extends Agent {
  final SpeechToText? stt;
  final TextToSpeech? tts;
  final SpeechController? controller;

  SpeechAgent({this.stt, this.tts, this.controller});

  @override
  String get name => 'speech';

  @override
  String describe() =>
      'Transcribes audio input and speaks text output when native speech '
      'engines are attached; barge-in aware.';

  @override
  Future<AgentResult> execute(TaskContext ctx) async {
    final started = DateTime.now();
    try {
      final output = <String, dynamic>{};

      final audio = ctx.metadata['audioBytes'];
      if (audio is Uint8List && audio.isNotEmpty) {
        if (stt == null) {
          output['transcript'] = 'unavailable: no SpeechToText engine attached';
        } else {
          final transcript = await _transcribeOnce(audio);
          output['transcript'] = transcript;
        }
      }

      final speak = ctx.metadata['speak'];
      if (speak is String && speak.isNotEmpty) {
        if (tts == null) {
          output['spoken'] = 'unavailable: no TextToSpeech engine attached';
        } else {
          controller?.beginSpeaking();
          try {
            await tts!.speak(speak);
            output['spoken'] = true;
          } finally {
            controller?.endSpeaking();
          }
        }
      }

      if (output.isEmpty) {
        output['status'] = 'idle';
        output['note'] =
            'No audioBytes/speak in context metadata; nothing to do.';
      }
      return AgentResult.ok(name, output, started, DateTime.now());
    } catch (e) {
      controller?.endSpeaking();
      return AgentResult.fail(name, 'Speech failed: $e', started, DateTime.now());
    }
  }

  /// One-shot transcription: start the engine, collect final results for a
  /// bounded window, then stop.
  Future<String> _transcribeOnce(Uint8List audio) async {
    final engine = stt!;
    final finals = <String>[];
    final sub = engine.results.listen((r) {
      if (r.isFinal && r.text.isNotEmpty) finals.add(r.text);
    });
    await engine.start(audioBytes: audio);
    await Future.delayed(const Duration(seconds: 30));
    await engine.stop();
    await sub.cancel();
    return finals.join(' ');
  }
}
