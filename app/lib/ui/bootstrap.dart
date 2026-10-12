/// App launcher for the pure-Dart VM (no dart:ui).
///
/// `dart run lib/main.dart` (without `--cli`) lands here: the graphical UI
/// needs the Flutter engine, so we print a pointer instead of crashing on
/// the missing `dart:ui` library.
Future<void> launchNpApp() async {
  // ignore: avoid_print
  print('NP UI needs the Flutter engine. Run one of:');
  // ignore: avoid_print
  print('  flutter run                 # graphical NP app');
  // ignore: avoid_print
  print('  dart run lib/main.dart --cli "list files in /tmp"');
}
