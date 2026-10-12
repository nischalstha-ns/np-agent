import 'dart:math';
import 'dart:typed_data';

/// REAL: Screen-understanding contract.
///
/// Implementations need (a) a native screen-capture source and (b) a vision
/// model (local GGUF VLM or cloud) to interpret pixels; this file defines
/// the contract only.
class UiElement {
  /// REAL: The label.
  final String label;
  /// REAL: The kind.
  final String kind; // 'button' | 'textfield' | 'link' | 'icon' | 'text' | ...
  /// REAL: The bounds.
  final Rectangle<int> bounds; // pixel coordinates in the screenshot

  const UiElement({
    required this.label,
    required this.kind,
    required this.bounds,
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'kind': kind,
        'bounds': {
          'left': bounds.left,
          'top': bounds.top,
          'width': bounds.width,
          'height': bounds.height,
        },
      };
}

/// REAL: Screen-understanding contract.
abstract class ScreenUnderstanding {
  /// REAL: Describe what is visible in [screenshotPng] in one or two sentences.
  Future<String> describe(Uint8List screenshotPng);

  /// REAL: Find UI elements matching [query] (e.g. 'the Send button').
  Future<List<UiElement>> findElements(
      Uint8List screenshotPng, String query);
}

/// REAL: Fallback implementation that reports unavailability.
class NullScreenUnderstanding implements ScreenUnderstanding {
  /// MOCK: Describes.
  @override
  Future<String> describe(Uint8List screenshotPng) async {
    throw UnimplementedError('Screen understanding requires a native '
        'screen-capture source and a vision model.');
  }

  @override
  Future<List<UiElement>> findElements(
      Uint8List screenshotPng, String query) async {
    throw UnimplementedError('Screen understanding requires a native '
        'screen-capture source and a vision model.');
  }
}
