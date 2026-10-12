import 'dart:io';

import 'agents/np_core.dart';
import 'core/config.dart';
import 'tools/tool_registry.dart';
// Conditional import: the Flutter UI entry is only compiled when dart:ui
// exists (Flutter engine). Under `dart run`, the stub launcher is used so
// the --cli path keeps working in the pure-Dart VM.
import 'ui/bootstrap.dart'
    if (dart.library.ui) 'ui/bootstrap_flutter.dart' as bootstrap;

/// REAL: NP entry point.
///
/// * Graphical app (default under `flutter run`): `runApp(const NpApp())`.
/// * Console escape hatch: pass `--cli` to run the original console
///   behavior instead, e.g.
///   `dart run lib/main.dart --cli "list files in /tmp"`.
Future<void> main(List<String> args) async {
  if (args.contains('--cli')) {
    await _runCli(args.where((a) => a != '--cli').toList());
    return;
  }
  await bootstrap.launchNpApp();
}

/// REAL: Original console behavior, preserved as the --cli escape hatch.
Future<void> _runCli(List<String> args) async {
  _printBanner();

  /// REAL: The auto approve.
  final autoApprove = args.contains('--auto-approve');
  // Mock native layer + in-memory store by default (works in pure `dart run`
  // without Flutter plugins). Pass --real on a device build with native
  // plugins to use sqflite and the real native engines.
  /// REAL: The use mocks.
  final useMocks = !args.contains('--real');
  /// REAL: The prompt args.
  final promptArgs =
      args.where((a) => a != '--auto-approve' && a != '--real').toList();

  /// REAL: The core.
  late final NpCore core;
  try {
    core = await NpCore.initialize(autoApprove: autoApprove, useMocks: useMocks);
  } catch (e) {
    stderr.writeln('NP failed to initialize: $e');
    exit(1);
  }
  _printStatus(core);

  try {
    if (promptArgs.isEmpty) {
      stdout.writeln('NP is ready. Pass a prompt as arguments to run it:');
      stdout.writeln('  dart run lib/main.dart --cli "list files in /tmp"');
      stdout.writeln(
          '  dart run lib/main.dart --cli --auto-approve "read file notes.txt"');
      return;
    }
    /// REAL: The response.
    final response = await core.handle(promptArgs.join(' '));
    stdout.writeln('');
    stdout.writeln(response);
  } finally {
    await core.dispose();
  }
}

void _printBanner() {
  stdout.writeln(r'''
  _   _ ____
 | \ | |  _ \    NP - hybrid Offline+Online AI Operating System Agent
 |  \| | |_) |
 | |\  |  __/
 |_| \_|_|
''');
  stdout.writeln('${AppConfig.appName} v${AppConfig.version}');
  stdout.writeln('------------------------------------------------------------');
}

void _printStatus(NpCore core) {
  /// REAL: The offline.
  final offline = core.llm.offline;
  /// REAL: The model dirs.
  final modelDirs = AppConfig.existingModelDirs();
  stdout.writeln('Model dirs: '
      '${modelDirs.isEmpty ? '(none found)' : modelDirs.join(', ')}');
  /// REAL: The current.
  final current = offline.currentModel;
  stdout.writeln('Offline model: ${current?.toString() ?? '(none loaded)'}'
      '${offline.engineLinked ? ' [engine linked]' : ' [engine not linked]'}');
  /// REAL: The tool names.
  final toolNames = core.di.get<ToolRegistry>().names();
  stdout.writeln('Tools (${toolNames.length}): ${toolNames.join(', ')}');
  stdout.writeln('------------------------------------------------------------');
}
