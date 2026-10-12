import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'android_control.dart';
import 'linux_control.dart';
import 'macos_control.dart';
import 'windows_control.dart';

/// Abstract OS-control service: mouse, keyboard, screen capture.
///
/// Capability matrix (this scaffold — all actions need a native plugin):
///
/// | capability        | Windows | Linux | macOS | Android |
/// |-------------------|---------|-------|-------|---------|
/// | mouse move/click  | plugin  | plugin| plugin| plugin  |
/// | keyboard type/keys| plugin  | plugin| plugin| plugin  |
/// | screen capture    | plugin  | plugin| plugin| plugin  |
/// | platform detect   | real    | real  | real  | real    |
///
/// Every action method throws [UnimplementedError]("requires native plugin")
/// in the platform subclasses until a real plugin is wired. [DesktopControl]
/// itself only implements [current()] (real platform detection) and the
/// shared contract.
abstract class DesktopControl {
  /// Human platform name, e.g. 'windows', 'linux', 'macos', 'android'.
  String get platformName;

  /// Pick the control implementation for the current OS.
  static DesktopControl current() {
    if (Platform.isWindows) return WindowsControl();
    if (Platform.isLinux) return LinuxControl();
    if (Platform.isMacOS) return MacosControl();
    if (Platform.isAndroid) return AndroidControl();
    throw UnsupportedError(
        'DesktopControl: unsupported OS "${Platform.operatingSystem}"');
  }

  Future<Point<int>> mousePosition();
  Future<void> moveMouse(int x, int y);
  Future<void> click({String button = 'left'});
  Future<void> doubleClick() => click(button: 'left').then((_) => click(button: 'left'));
  Future<void> typeText(String text);
  Future<void> pressKey(String key);
  Future<void> hotkey(List<String> keys);

  /// Capture the primary screen as PNG bytes.
  Future<Uint8List> captureScreen();

  UnimplementedError _native(String method) => UnimplementedError(
      '$runtimeType.$method requires a native plugin on $platformName.');
}
