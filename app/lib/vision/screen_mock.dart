import 'dart:math';
import 'dart:typed_data';

import 'screen_understanding.dart';

/// MOCK: Simulated screen understanding.
///
/// [describe] returns a canned description noting the screenshot size.
/// [findElements] returns a small list of plausible regions whose labels
/// are derived from the [query] — a deterministic stand-in for a vision
/// model, clearly marked as simulated.
class MockScreenUnderstanding implements ScreenUnderstanding {
  /// MOCK: Fake description — canned, with the real byte count.
  @override
  Future<String> describe(Uint8List screenshotPng) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return 'Simulated screen description: a mock desktop with a top bar, '
        'a dock on the left, and one open window '
        '(${screenshotPng.length} bytes analyzed by MockScreenUnderstanding; '
        'attach a real vision model for actual understanding).';
  }

  /// MOCK: Fake element search — deterministic regions labeled from [query].
  @override
  Future<List<UiElement>> findElements(
      Uint8List screenshotPng, String query) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final q = query.trim().isEmpty ? 'element' : query.trim();
    return [
      UiElement(
        label: 'Mock $q (top bar)',
        kind: 'button',
        bounds: const Rectangle<int>(1200, 12, 120, 32),
      ),
      UiElement(
        label: 'Mock $q (window)',
        kind: 'button',
        bounds: const Rectangle<int>(640, 400, 140, 36),
      ),
      UiElement(
        label: 'Mock $q (dock)',
        kind: 'icon',
        bounds: const Rectangle<int>(24, 320, 48, 48),
      ),
    ];
  }
}
