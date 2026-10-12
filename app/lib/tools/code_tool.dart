import 'dart:io';

import 'tool.dart';

/// Real local code tool (dart:io backed).
///
/// Actions:
/// - `writeDart` {path, code} -> writes a `.dart` source file.
/// - `analyze`   {path}       -> lightweight static analysis:
///   brace/paren/bracket balance, TODO/FIXME count, over-long lines,
///   and lines that look like statements missing a trailing `;`.
/// - `symbols`   {path}       -> top-level class/function/enum names found
///   with regular expressions (heuristic, not a full parser).
class CodeTool extends Tool {
  @override
  String get name => 'code';

  @override
  String get description =>
      'Write Dart source files and run lightweight static analysis on them.';

  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['writeDart', 'analyze', 'symbols'],
          'required': true,
        },
        'path': {'type': 'string', 'required': true},
        'code': {'type': 'string', 'required': false},
      };

  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'description': 'Action-dependent payload (write receipt / diagnostics).',
      };

  @override
  Future<PermissionDecision> checkPermission(ToolCall call) async {
    switch (call.action) {
      case 'analyze':
      case 'symbols':
        return const PermissionDecision.allowed('read-only analysis');
      case 'writeDart':
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

  @override
  Future<ToolResult> execute(ToolCall call) async {
    try {
      switch (call.action) {
        case 'writeDart':
          return ToolResult.ok(await _writeDart(call));
        case 'analyze':
          return ToolResult.ok(await _analyze(call));
        case 'symbols':
          return ToolResult.ok(await _symbols(call));
        default:
          return ToolResult.fail('Unknown code action "${call.action}"');
      }
    } catch (e) {
      return ToolResult.fail('code.${call.action} failed: $e');
    }
  }

  @override
  Future<bool> verify(ToolCall call, ToolResult result) async {
    if (!result.success) return true;
    return result.data is Map;
  }

  Future<Map<String, dynamic>> _writeDart(ToolCall call) async {
    final path = (call.args['path'] as String?) ?? '';
    final code = (call.args['code'] as String?) ?? '';
    if (path.isEmpty) throw ArgumentError('writeDart requires "path"');
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(code);
    return {'path': path, 'bytesWritten': code.length};
  }

  Future<Map<String, dynamic>> _analyze(ToolCall call) async {
    final path = (call.args['path'] as String?) ?? '';
    final file = File(path);
    if (!await file.exists()) throw StateError('File not found: $path');
    final source = await file.readAsString();
    final lines = source.split('\n');

    int brace = 0, paren = 0, bracket = 0;
    var minDepth = 0;
    var inBlockComment = false;
    var todos = 0;
    final longLines = <int>[];
    final missingSemi = <int>[];
    final stripped = StringBuffer();

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      // crude comment/string stripping for balance counting
      if (line.contains('/*')) inBlockComment = true;
      if (inBlockComment) {
        if (line.contains('*/')) inBlockComment = false;
        continue;
      }
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

  Future<Map<String, dynamic>> _symbols(ToolCall call) async {
    final path = (call.args['path'] as String?) ?? '';
    final file = File(path);
    if (!await file.exists()) throw StateError('File not found: $path');
    final source = await file.readAsString();
    final classes = RegExp(r'^\s*(?:abstract\s+|final\s+|sealed\s+|base\s+|mixin\s+)?class\s+(\w+)',
            multiLine: true)
        .allMatches(source)
        .map((m) => m.group(1))
        .whereType<String>()
        .toList();
    final functions = RegExp(
            r'^\s*(?:Future<[^>]+>|[A-Za-z_][\w<>,\s?]*)\s+([a-zA-Z_]\w*)\s*\(',
            multiLine: true)
        .allMatches(source)
        .map((m) => m.group(1))
        .whereType<String>()
        .toList();
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
