import 'dart:typed_data';

import '../vision/ocr.dart';
import '../vision/screen_understanding.dart';
import 'agent.dart';

/// Vision stage: OCR and screen understanding.
///
/// The engines are optional. When attached (native plugins providing
/// [OcrEngine]/[ScreenUnderstanding]), this agent runs real analysis over
/// `ctx.metadata['imageBytes']` (a `Uint8List`). When absent it reports
/// honestly that vision is unavailable instead of hallucinating results.
class VisionAgent extends Agent {
  final OcrEngine? ocr;
  final ScreenUnderstanding? screen;

  VisionAgent({this.ocr, this.screen});

  @override
  String get name => 'vision';

  @override
  String describe() =>
      'Runs OCR and screen understanding over supplied image bytes when '
      'native vision engines are attached.';

  @override
  Future<AgentResult> execute(TaskContext ctx) async {
    final started = DateTime.now();
    try {
      final raw = ctx.metadata['imageBytes'];
      if (raw is! Uint8List || raw.isEmpty) {
        return AgentResult.ok(
          name,
          {
            'status': 'no_image',
            'note': 'No imageBytes in context metadata; nothing to analyze.',
          },
          started,
          DateTime.now(),
        );
      }

      final output = <String, dynamic>{'bytes': raw.length};
      if (ocr != null) {
        final result = await ocr!.recognize(raw,
            language: ctx.metadata['ocrLanguage'] as String? ?? 'eng');
        output['ocr'] = result.toJson();
      } else {
        output['ocr'] = 'unavailable: no OcrEngine attached';
      }
      if (screen != null) {
        final query = ctx.metadata['findElement'] as String?;
        output['description'] = await screen!.describe(raw);
        if (query != null && query.isNotEmpty) {
          final elements = await screen!.findElements(raw, query);
          output['elements'] =
              elements.map((e) => e.toJson()).toList();
        }
      } else {
        output['screen'] = 'unavailable: no ScreenUnderstanding engine attached';
      }

      return AgentResult.ok(name, output, started, DateTime.now());
    } catch (e) {
      return AgentResult.fail(name, 'Vision failed: $e', started, DateTime.now());
    }
  }
}
