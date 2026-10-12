/// Platform performance stats, web-safe via conditional import.
///
/// On `dart:io` platforms this reports real values (RSS via [ProcessInfo],
/// Dart version, OS). Elsewhere it returns honest `n/a` placeholders.
export 'perf_stub.dart' if (dart.library.io) 'perf_io.dart';
