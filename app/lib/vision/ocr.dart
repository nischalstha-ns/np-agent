import 'dart:typed_data';

/// OCR contract.
///
/// Implementations need a native OCR engine (ML Kit text recognition or
/// Tesseract via a platform plugin); this file defines the contract only.
class OcrWord {
  final String text;
  final double confidence;

  /// Normalized bounding box (0..1 relative to image size): [l, t, r, b].
  final List<double> box;

  const OcrWord({
    required this.text,
    required this.confidence,
    this.box = const [],
  });

  Map<String, dynamic> toJson() =>
      {'text': text, 'confidence': confidence, 'box': box};
}

class OcrResult {
  final String text;
  final List<OcrWord> words;
  final String language;

  const OcrResult({
    required this.text,
    this.words = const [],
    this.language = 'eng',
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'language': language,
        'words': words.map((w) => w.toJson()).toList(),
      };
}

abstract class OcrEngine {
  /// Recognize text in [imageBytes] (PNG/JPEG bytes).
  Future<OcrResult> recognize(Uint8List imageBytes, {String language = 'eng'});
}

/// Fallback engine that reports unavailability instead of hallucinating.
class NullOcrEngine implements OcrEngine {
  @override
  Future<OcrResult> recognize(Uint8List imageBytes,
      {String language = 'eng'}) async {
    throw UnimplementedError(
        'OCR requires a native engine (ML Kit / Tesseract plugin).');
  }
}
