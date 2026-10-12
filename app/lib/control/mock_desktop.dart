import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../native/png_encode.dart';
import 'desktop_control.dart';

/// MOCK: Simulated desktop control — drives a virtual desktop instead of
/// the real OS.
///
/// The virtual desktop tracks: mouse position, typed text, pressed keys,
/// clicks, "open" app windows, and a virtual file tree under a temp dir.
/// [captureScreen] synthesizes a valid PNG (solid color) in pure Dart.
/// Nothing here touches the real mouse, keyboard, or screen.
///
/// One subclass per OS ([MockWindowsControl], [MockLinuxControl],
/// [MockMacosControl], [MockAndroidControl]) so tests can pick the platform
/// explicitly; [MockDesktopControl.forCurrentOs] mirrors
/// [DesktopControl.current].
class MockDesktopControl extends DesktopControl {
  @override
  final String platformName;

  int _x = 0;
  int _y = 0;

  /// MOCK: Virtual screen size used by [captureScreen].
  final int screenWidth;
  final int screenHeight;

  /// MOCK: Inspectable virtual desktop state.
  final List<String> typedLog = [];
  final List<String> pressedKeys = [];
  final List<String> clickedButtons = [];
  final Set<String> openApps = {};
  final Map<String, String> virtualFiles = {};

  MockDesktopControl({
    required this.platformName,
    this.screenWidth = 1280,
    this.screenHeight = 800,
  });

  /// MOCK: Build the mock matching the current OS.
  factory MockDesktopControl.forCurrentOs() {
    if (Platform.isWindows) return MockWindowsControl();
    if (Platform.isMacOS) return MockMacosControl();
    if (Platform.isAndroid) return MockAndroidControl();
    return MockLinuxControl();
  }

  @override
  Future<Point<int>> mousePosition() async => Point(_x, _y);

  @override
  Future<void> moveMouse(int x, int y) async {
    _x = x.clamp(0, screenWidth);
    _y = y.clamp(0, screenHeight);
  }

  @override
  Future<void> click({String button = 'left'}) async {
    clickedButtons.add(button);
  }

  @override
  Future<void> typeText(String text) async {
    typedLog.add(text);
  }

  @override
  Future<void> pressKey(String key) async {
    pressedKeys.add(key);
  }

  @override
  Future<void> hotkey(List<String> keys) async {
    pressedKeys.add(keys.join('+'));
  }

  /// MOCK: Synthesize a valid solid-color PNG of the virtual screen.
  @override
  Future<Uint8List> captureScreen() async =>
      PngEncode.solidPng(screenWidth, screenHeight, 0x2B, 0x3A, 0x55);

  /// MOCK: "Open" an app on the virtual desktop (adds a window entry).
  Future<void> openApp(String appName) async {
    openApps.add(appName);
  }

  /// MOCK: "Close" an app on the virtual desktop.
  Future<void> closeApp(String appName) async {
    openApps.remove(appName);
  }

  /// MOCK: Write a file into the virtual file tree (not the real fs).
  Future<void> writeVirtualFile(String path, String content) async {
    virtualFiles[path] = content;
  }

  /// MOCK: Read a file from the virtual file tree.
  Future<String?> readVirtualFile(String path) async => virtualFiles[path];

  /// MOCK: Human-readable snapshot of the virtual desktop.
  Map<String, dynamic> snapshot() => {
        'platform': platformName,
        'mouse': {'x': _x, 'y': _y},
        'openApps': openApps.toList(),
        'typedChars': typedLog.fold<int>(0, (n, s) => n + s.length),
        'pressedKeys': List.of(pressedKeys),
        'clicks': clickedButtons.length,
        'virtualFiles': virtualFiles.keys.toList(),
      };
}

/// MOCK: Simulated Windows desktop control.
class MockWindowsControl extends MockDesktopControl {
  /// MOCK: Create a simulated Windows desktop.
  MockWindowsControl() : super(platformName: 'windows');
}

/// MOCK: Simulated Linux desktop control.
class MockLinuxControl extends MockDesktopControl {
  /// MOCK: Create a simulated Linux desktop.
  MockLinuxControl() : super(platformName: 'linux');
}

/// MOCK: Simulated macOS desktop control.
class MockMacosControl extends MockDesktopControl {
  /// MOCK: Create a simulated macOS desktop.
  MockMacosControl() : super(platformName: 'macos');
}

/// MOCK: Simulated Android device control.
class MockAndroidControl extends MockDesktopControl {
  /// MOCK: Create a simulated Android device (portrait screen).
  MockAndroidControl()
      : super(platformName: 'android', screenWidth: 480, screenHeight: 800);
}
