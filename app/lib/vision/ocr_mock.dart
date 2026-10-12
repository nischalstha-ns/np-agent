import 'dart:typed_data';

import 'ocr.dart';

/// MOCK: Simulated OCR engine.
///
/// Returns a plausible [OcrResult] — a few canned words with normalized
/// bounding boxes — without analyzing the pixels. The reported text notes
/// that it is simulated so it can never be mistaken for a real read.
class MockOcr implements OcrEngine {
  /// MOCK: Fake recognition — canned words, no pixel analysis.
  @override
  Future<OcrResult> recognize(Uint8List imageBytes,
      {String language = 'eng'}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    const words = [
      OcrWord(text: 'MOCK', confidence: 0.99, box: [0.05, 0.05, 0.25, 0.15]),
      OcrWord(text: 'screen', confidence: 0.97, box: [0.28, 0.05, 0.52, 0.15]),
      OcrWord(text: 'text', confidence: 0.96, box: [0.55, 0.05, 0.72, 0.15]),
    ];
    return OcrResult(
      text: 'MOCK screen text (simulated OCR of ${imageBytes.length} bytes; '
          'attach a real OcrEngine for actual recognition)',
      words: words,
      language: language,
    );
  }
}
