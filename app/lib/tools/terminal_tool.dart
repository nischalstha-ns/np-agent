import 'dart:async';
import 'dart:io';

import 'tool.dart';

/// REAL: Real local command execution via [Process].
///
/// Actions:
/// - `run` {command, args?, workingDirectory?, timeoutSeconds?}
///   -> {exitCode, stdout, stderr, timedOut}
///
/// The tool's own permission layer denies known-destructive patterns outright
/// and requires approval for privilege-escalation / system-service commands.
class TerminalTool extends Tool {
  /// REAL: Patterns that are always denied, no override possible.
  static final List<RegExp> _denied = [
    RegExp(r'\brm\s+(-[a-z]*r[a-z]*\s+)?/\s*(;|&&|\||$)'), // rm -rf /
    RegExp(r'\brm\s+(-[a-z]*r[a-z]*\s+)~/\s*(;|&&|\||$)'), // rm -rf ~/
    RegExp(r'\bmkfs\b'),
    RegExp(r'\bdd\b.*\bof='),
    RegExp(r':\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;'), // fork bomb
    RegExp(r'\bshutdown\b'),
    RegExp(r'\breboot\b'),
    RegExp(r'\bhalt\b'),
    RegExp(r'\bpoweroff\b'),
    RegExp(r'\bdel\s+/[fqs]\b', caseSensitive: false), // windows mass delete
    RegExp(r'\bformat\s+[a-z]:', caseSensitive: false), // windows format
  ];

  /// REAL: Patterns that need explicit user approval.
  static final List<RegExp> _needsApproval = [
    RegExp(r'^\s*sudo\b'),
    RegExp(r'\bsystemctl\b'),
    RegExp(r'\bservice\b'),
    RegExp(r'\bdiskpart\b', caseSensitive: false),
    RegExp(r'\breg\s+(add|delete)\b', caseSensitive: false),
    RegExp(r'>\s*/dev/sd'),
  ];

  /// REAL: The name.
  @override
  String get name => 'terminal';

  /// REAL: The description.
  @override
  String get description =>
      'Run shell commands locally and capture stdout/stderr/exit code.';

  /// REAL: The input schema.
  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['run'],
          'required': true,
        },
        'command': {'type': 'string', 'required': true},
        'args': {
          'type': 'array',
          'items': {'type': 'string'},
          'required': false,
        },
        'workingDirectory': {'type': 'string', 'required': false},
        'timeoutSeconds': {'type': 'int', 'required': false},
      };

  /// REAL: The output schema.
  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'properties': {
          'exitCode': {'type': 'int'},
          'stdout': {'type': 'string'},
          'stderr': {'type': 'string'},
          'timedOut': {'type': 'bool'},
        },
      };

  /// REAL: Checks permission.
  @override
  Future<PermissionDecision> checkPermission(ToolCall call) async {
    if (call.action != 'run') {
      return PermissionDecision.denied('Unknown terminal action "${call.action}"');
    }
    /// REAL: The command.
    final command = (call.args['command'] as String? ?? '').trim();
    if (command.isEmpty) {
      return const PermissionDecision.denied('Empty command');
    }
    /// REAL: The full.
    final full = '$command ${(call.args['args'] as List?)?.join(' ') ?? ''}';
    for (final pattern in _denied) {
      if (pattern.hasMatch(full)) {
        return PermissionDecision.denied(
            'Command matches destructive pattern ${pattern.pattern}');
      }
    }
    for (final pattern in _needsApproval) {
      if (pattern.hasMatch(full)) {
        return PermissionDecision.needsApproval(
            'Command matches privileged pattern ${pattern.pattern}');
      }
    }
    return const PermissionDecision.allowed('command passed safety patterns');
  }

  /// REAL: Executes.
  @override
  Future<ToolResult> execute(ToolCall call) async {
    /// REAL: The command.
    final command = (call.args['command'] as String? ?? '').trim();
    /// REAL: The args.
    final args = (call.args['args'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    /// REAL: The working directory.
    final workingDirectory = call.args['workingDirectory'] as String?;
    /// REAL: The timeout seconds.
    final timeoutSeconds = (call.args['timeoutSeconds'] as int?) ?? 60;

    try {
      /// REAL: The future.
      final future = Process.run(
        command,
        args,
        workingDirectory: workingDirectory,
        runInShell: true,
      );
      /// REAL: The pr.
      final ProcessResult pr = await future.timeout(
        Duration(seconds: timeoutSeconds),
        onTimeout: () => throw TimeoutException(
            'Command timed out after ${timeoutSeconds}s: $command'),
      );
      return ToolResult.ok({
        'exitCode': pr.exitCode,
        'stdout': _truncate(pr.stdout.toString()),
        'stderr': _truncate(pr.stderr.toString()),
        'timedOut': false,
      });
    } on TimeoutException catch (e) {
      return ToolResult.fail(e.message ?? 'Command timed out');
    } catch (e) {
      return ToolResult.fail('terminal.run failed: $e');
    }
  }

  /// REAL: Verifies.
  @override
  Future<bool> verify(ToolCall call, ToolResult result) async {
    if (!result.success) return true;
    /// REAL: The data.
    final data = result.data;
    return data is Map &&
        data['exitCode'] is int &&
        data['stdout'] is String &&
        data['stderr'] is String;
  }

  String _truncate(String s, [int max = 20000]) =>
      s.length > max ? '${s.substring(0, max)}\n...[truncated]' : s;
}
