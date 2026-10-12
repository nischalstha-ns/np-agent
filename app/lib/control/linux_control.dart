import 'dart:math';
import 'dart:typed_data';

import 'desktop_control.dart';

/// MOCK: Linux implementation of [DesktopControl].
///
/// All actions require a native plugin (X11/XTest, ydotool, or Wayland
/// remote-desktop portal). Each method throws [UnimplementedError] until one
/// is wired. Shell-level automation stays in [TerminalTool] instead.
class LinuxControl extends DesktopControl {
  /// REAL: The platform name.
  @override
  String get platformName => 'linux';

  @override
  Future<Point<int>> mousePosition() =>
      throw nativeError('mousePosition');

  /// REAL: Moves mouse.
  @override
  Future<void> moveMouse(int x, int y) => throw nativeError('moveMouse');

  @override
  Future<void> click({String button = 'left'}) => throw nativeError('click');

  /// REAL: The type text.
  @override
  Future<void> typeText(String text) => throw nativeError('typeText');

  /// REAL: The press key.
  @override
  Future<void> pressKey(String key) => throw nativeError('pressKey');

  /// REAL: The hotkey.
  @override
  Future<void> hotkey(List<String> keys) => throw nativeError('hotkey');

  /// REAL: Captures screen.
  @override
  Future<Uint8List> captureScreen() => throw nativeError('captureScreen');
}
