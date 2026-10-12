import 'dart:math';
import 'dart:typed_data';

import 'desktop_control.dart';

/// Windows implementation of [DesktopControl].
///
/// All actions require a native plugin (SendInput / UI Automation / DXGI
/// capture). Each method throws [UnimplementedError] until one is wired.
class WindowsControl extends DesktopControl {
  @override
  String get platformName => 'windows';

  @override
  Future<Point<int>> mousePosition() =>
      throw _native('mousePosition');

  @override
  Future<void> moveMouse(int x, int y) => throw _native('moveMouse');

  @override
  Future<void> click({String button = 'left'}) => throw _native('click');

  @override
  Future<void> typeText(String text) => throw _native('typeText');

  @override
  Future<void> pressKey(String key) => throw _native('pressKey');

  @override
  Future<void> hotkey(List<String> keys) => throw _native('hotkey');

  @override
  Future<Uint8List> captureScreen() => throw _native('captureScreen');
}
