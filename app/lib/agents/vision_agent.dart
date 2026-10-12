import 'dart:typed_data';

import '../vision/ocr.dart';
import '../vision/screen_understanding.dart';
import 'agent.dart';

/// REAL: Vision stage: OCR and screen understanding.
///
/// The engines are optional. When attached (native plugins providing
/// [OcrEngine]/[ScreenUnderstanding]), this agent runs real analysis over
/// `ctx.metadata['imageBytes']` (a `Uint8List`). When absent it reports
/// honestly that vision is unavailable instead of hallucinating results.
class VisionAgent extends Agent {
  /// REAL: The ocr.
  final OcrEngine? ocr;
  /// REAL: The screen.
  final ScreenUnderstanding? screen;

  VisionAgent({this.ocr, this.screen});

  /// REAL: The name.
  @override
  String get name => 'vision';

  @override
  String describe() =>
      'Runs OCR and screen understanding over supplied image bytes when '
      'native vision engines are attached.';

  /// REAL: Executes.
  @override
  Future<AgentResult> execute(TaskContext ctx) async {
    /// REAL: The started.
    final started = DateTime.now();
    try {
      /// REAL: The raw.
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

      /// REAL: The output.
      final output = <String, dynamic>{'bytes': raw.length};
      if (ocr != null) {
        /// REAL: The result.
        final result = await ocr!.recognize(raw,
            language: ctx.metadata['ocrLanguage'] as String? ?? 'eng');
        output['ocr'] = result.toJson();
      } else {
        output['ocr'] = 'unavailable: no OcrEngine attached';
      }
      if (screen != null) {
        /// REAL: The query.
        final query = ctx.metadata['findElement'] as String?;
        output['description'] = await screen!.describe(raw);
        if (query != null && query.isNotEmpty) {
          /// REAL: The elements.
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
