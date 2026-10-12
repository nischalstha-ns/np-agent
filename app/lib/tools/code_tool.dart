import 'dart:async';
import 'dart:io';

import 'tool.dart';

/// REAL: Local code tool (dart:io backed).
///
/// Actions:
/// - `writeDart`   {path, code} -> writes a `.dart` source file.
/// - `analyze`     {path}       -> lightweight heuristic static analysis:
///   brace/paren/bracket balance, TODO/FIXME count, over-long lines,
///   and lines that look like statements missing a trailing `;`.
/// - `runAnalyze`  {path}       -> runs the real `dart analyze` on the file
///   (or directory) via a subprocess and returns its diagnostics.
/// - `format`      {path}       -> runs the real `dart format` on the file.
/// - `symbols`     {path}       -> top-level class/function/enum names found
///   with regular expressions (heuristic, not a full parser).
class CodeTool extends Tool {
  /// REAL: The name.
  @override
  String get name => 'code';

  /// REAL: The description.
  @override
  String get description =>
      'Write Dart source files, run real `dart analyze` / `dart format`, '
      'and extract symbols with heuristic static analysis.';

  /// REAL: The input schema.
  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': [
            'writeDart',
            'analyze',
            'runAnalyze',
            'format',
            'symbols'
          ],
          'required': true,
        },
        'path': {'type': 'string', 'required': true},
        'code': {'type': 'string', 'required': false},
      };

  /// REAL: The output schema.
  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'description': 'Action-dependent payload (write receipt / diagnostics).',
      };

  /// REAL: Permission policy — analysis is open; `dart analyze`/`dart format`
  /// are read-only-ish and open too; writing is limited to `.dart` files.
  /// REAL: Checks permission.
  @override
  Future<PermissionDecision> checkPermission(ToolCall call) async {
    switch (call.action) {
      case 'analyze':
      case 'symbols':
      case 'runAnalyze':
      case 'format':
        return const PermissionDecision.allowed('read-only analysis');
      case 'writeDart':
        /// REAL: The path.
        final path = call.args['path'] as String? ?? '';
        if (!path.endsWith('.dart')) {
          return const PermissionDecision.denied(
              'writeDart only writes .dart files');
        }
        return const PermissionDecision.allowed('dart source write');
      default:
        return PermissionDecision.denied('Unknown code action "${call.action}"');
    }
  }

  /// REAL: Executes.
  @override
  Future<ToolResult> execute(ToolCall call) async {
    try {
      switch (call.action) {
        case 'writeDart':
          return ToolResult.ok(await _writeDart(call));
        case 'analyze':
          return ToolResult.ok(await _analyze(call));
        case 'runAnalyze':
          return ToolResult.ok(await _runAnalyze(call));
        case 'format':
          return ToolResult.ok(await _format(call));
        case 'symbols':
          return ToolResult.ok(await _symbols(call));
        default:
          return ToolResult.fail('Unknown code action "${call.action}"');
      }
    } catch (e) {
      return ToolResult.fail('code.${call.action} failed: $e');
    }
  }

  /// REAL: Verifies.
  @override
  Future<bool> verify(ToolCall call, ToolResult result) async {
    if (!result.success) return true;
    return result.data is Map;
  }

  Future<Map<String, dynamic>> _writeDart(ToolCall call) async {
    /// REAL: The path.
    final path = (call.args['path'] as String?) ?? '';
    /// REAL: The code.
    final code = (call.args['code'] as String?) ?? '';
    if (path.isEmpty) throw ArgumentError('writeDart requires "path"');
    /// REAL: The file.
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(code);
    return {'path': path, 'bytesWritten': code.length};
  }

  Future<Map<String, dynamic>> _analyze(ToolCall call) async {
    /// REAL: The path.
    final path = (call.args['path'] as String?) ?? '';
    /// REAL: The file.
    final file = File(path);
    if (!await file.exists()) throw StateError('File not found: $path');
    /// REAL: The source.
    final source = await file.readAsString();
    /// REAL: The lines.
    final lines = source.split('\n');

    /// REAL: The brace.
    int brace = 0, paren = 0, bracket = 0;
    /// REAL: The min depth.
    var minDepth = 0;
    /// REAL: The in block comment.
    var inBlockComment = false;
    /// REAL: The todos.
    var todos = 0;
    /// REAL: The long lines.
    final longLines = <int>[];
    /// REAL: The missing semi.
    final missingSemi = <int>[];
    /// REAL: The stripped.
    final stripped = StringBuffer();

    for (var i = 0; i < lines.length; i++) {
      /// REAL: The line.
      var line = lines[i];
      // crude comment/string stripping for balance counting
      if (line.contains('/*')) inBlockComment = true;
      if (inBlockComment) {
        if (line.contains('*/')) inBlockComment = false;
        continue;
      }
      /// REAL: The code.
      final code = line.split('//').first;
      stripped.writeln(code);
      for (final ch in code.codeUnits) {
        if (ch == 0x7B) brace++; // {
        if (ch == 0x7D) {
          brace--;
          if (brace < minDepth) minDepth = brace;
        }
        if (ch == 0x28) paren++; // (
        if (ch == 0x29) paren--;
        if (ch == 0x5B) bracket++; // [
        if (ch == 0x5D) bracket--;
      }
      if (RegExp(r'\b(TODO|FIXME|HACK)\b').hasMatch(line)) todos++;
      if (line.length > 120) longLines.add(i + 1);
      /// REAL: The t.
      final t = code.trim();
      if (t.isNotEmpty &&
          !t.endsWith(';') &&
          !t.endsWith('{') &&
          !t.endsWith('}') &&
          !t.endsWith(',') &&
          !t.startsWith('import ') &&
          !t.startsWith('export ') &&
          !t.startsWith('library ') &&
          !t.startsWith('part ') &&
          !t.startsWith('@') &&
          !t.startsWith('///') &&
          RegExp(r'^[a-zA-Z_]').hasMatch(t)) {
        // Heuristic only: looks like a statement without ';'.
        missingSemi.add(i + 1);
      }
    }

    /// REAL: The diagnostics.
    final diagnostics = <Map<String, dynamic>>[];
    if (brace != 0 || minDepth < 0) {
      diagnostics.add({
        'severity': 'error',
        'message': 'Unbalanced braces: depth ended at $brace',
      });
    }
    if (paren != 0) {
      diagnostics.add({
        'severity': 'error',
        'message': 'Unbalanced parentheses: depth ended at $paren',
      });
    }
    if (bracket != 0) {
      diagnostics.add({
        'severity': 'error',
        'message': 'Unbalanced brackets: depth ended at $bracket',
      });
    }
    for (final ln in longLines.take(20)) {
      diagnostics.add({
        'severity': 'info',
        'message': 'Line $ln exceeds 120 characters',
      });
    }
    for (final ln in missingSemi.take(20)) {
      diagnostics.add({
        'severity': 'warning',
        'message': 'Line $ln may be missing a trailing semicolon',
      });
    }

    return {
      'path': path,
      'lines': lines.length,
      'todos': todos,
      'balanced':
          brace == 0 && paren == 0 && bracket == 0 && minDepth >= 0,
      'diagnostics': diagnostics,
    };
  }

  /// REAL: Run the real `dart analyze` on [path] (file or directory) via a
  /// subprocess. Returns the analyzer's exit code and parsed diagnostics.
  Future<Map<String, dynamic>> _runAnalyze(ToolCall call) async {
    /// REAL: The path.
    final path = (call.args['path'] as String?) ?? '';
    if (path.isEmpty) throw ArgumentError('runAnalyze requires "path"');
    /// REAL: The pr.
    final pr = await Process.run(
      'dart',
      ['analyze', path],
      runInShell: true,
    ).timeout(
      const Duration(seconds: 120),
      onTimeout: () =>
          throw TimeoutException('dart analyze timed out on $path'),
    );
    /// REAL: The output.
    final output = '${pr.stdout}\n${pr.stderr}';
    return {
      'path': path,
      'exitCode': pr.exitCode,
      'clean': pr.exitCode == 0,
      'diagnostics': _parseAnalyzerOutput(output),
    };
  }

  /// REAL: Run the real `dart format` on [path].
  Future<Map<String, dynamic>> _format(ToolCall call) async {
    /// REAL: The path.
    final path = (call.args['path'] as String?) ?? '';
    if (path.isEmpty) throw ArgumentError('format requires "path"');
    if (!path.endsWith('.dart')) {
      throw ArgumentError('format only formats .dart files');
    }
    /// REAL: The pr.
    final pr = await Process.run(
      'dart',
      ['format', path],
      runInShell: true,
    ).timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw TimeoutException('dart format timed out'),
    );
    return {
      'path': path,
      'exitCode': pr.exitCode,
      'changed': pr.exitCode == 0 &&
          '${pr.stdout}'.contains('Formatted'),
      'output': '${pr.stdout}'.trim(),
    };
  }

  /// REAL: Parse `dart analyze` human output lines into diagnostics.
  ///
  /// Real format: `error - path/to/file.dart:2:13 - message - error_code`.
  List<Map<String, dynamic>> _parseAnalyzerOutput(String output) {
    final diagnostics = <Map<String, dynamic>>[];
    final lineRe = RegExp(
        r'^(info|warning|error)\s+-\s+(.*?):(\d+):(\d+)\s+-\s+(.*?)\s+-\s+(\S+)\s*$');
    for (final line in output.split('\n')) {
      final m = lineRe.firstMatch(line.trim());
      if (m != null) {
        diagnostics.add({
          'severity': m.group(1),
          'file': m.group(2),
          'line': int.tryParse(m.group(3) ?? '') ?? 0,
          'column': int.tryParse(m.group(4) ?? '') ?? 0,
          'message': m.group(5),
          'code': m.group(6),
        });
      }
    }
    return diagnostics;
  }

  Future<Map<String, dynamic>> _symbols(ToolCall call) async {
    /// REAL: The path.
    final path = (call.args['path'] as String?) ?? '';
    /// REAL: The file.
    final file = File(path);
    if (!await file.exists()) throw StateError('File not found: $path');
    /// REAL: The source.
    final source = await file.readAsString();
    /// REAL: The classes.
    final classes = RegExp(r'^\s*(?:abstract\s+|final\s+|sealed\s+|base\s+|mixin\s+)?class\s+(\w+)',
            multiLine: true)
        .allMatches(source)
        .map((m) => m.group(1))
        .whereType<String>()
        .toList();
    /// REAL: The functions.
    final functions = RegExp(
            r'^\s*(?:Future<[^>]+>|[A-Za-z_][\w<>,\s?]*)\s+([a-zA-Z_]\w*)\s*\(',
            multiLine: true)
        .allMatches(source)
        .map((m) => m.group(1))
        .whereType<String>()
        .toList();
    /// REAL: The enums.
    final enums = RegExp(r'^\s*enum\s+(\w+)', multiLine: true)
        .allMatches(source)
        .map((m) => m.group(1))
        .whereType<String>()
        .toList();
    return {
      'path': path,
      'classes': classes,
      'functions': functions,
      'enums': enums,
    };
  }
}
