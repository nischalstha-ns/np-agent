import 'dart:io';

import 'agents/np_core.dart';
import 'core/config.dart';
import 'tools/tool_registry.dart';

/// NP bootstrap: builds the DI container, initializes NP Core, prints the
/// startup banner.
///
/// Console-style entry point (valid Dart, no Flutter widgets required).
/// A Flutter UI would call `NpCore.initialize()` the same way and then
/// `runApp(...)` with widgets bound to the controllers in lib/ui.
///
/// Usage:
///   dart run lib/main.dart "list files in /tmp"
Future<void> main(List<String> args) async {
  _printBanner();

  final autoApprove = args.contains('--auto-approve');
  final promptArgs = args.where((a) => a != '--auto-approve').toList();

  late final NpCore core;
  try {
    core = await NpCore.initialize(autoApprove: autoApprove);
  } catch (e) {
    stderr.writeln('NP failed to initialize: $e');
    exit(1);
  }
  _printStatus(core);

  try {
    if (promptArgs.isEmpty) {
      stdout.writeln('NP is ready. Pass a prompt as arguments to run it:');
      stdout.writeln('  dart run lib/main.dart "list files in /tmp"');
      stdout.writeln('  dart run lib/main.dart --auto-approve "read file notes.txt"');
      return;
    }
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
  final offline = core.llm.offline;
  final modelDirs = AppConfig.existingModelDirs();
  stdout.writeln('Model dirs: '
      '${modelDirs.isEmpty ? '(none found)' : modelDirs.join(', ')}');
  final current = offline.currentModel;
  stdout.writeln('Offline model: ${current?.toString() ?? '(none loaded)'}'
      '${offline.engineLinked ? ' [engine linked]' : ' [engine not linked]'}');
  final toolNames = core.di.get<ToolRegistry>().names();
  stdout.writeln('Tools (${toolNames.length}): ${toolNames.join(', ')}');
  stdout.writeln('------------------------------------------------------------');
}
