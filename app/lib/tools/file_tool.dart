import 'dart:io';

import 'tool.dart';

/// Real local filesystem tool (dart:io).
///
/// Actions:
/// - `read`   {path, maxBytes?}            -> file text
/// - `write`  {path, content, append?}      -> bytes written
/// - `list`   {dir, recursive?}            -> entries
/// - `delete` {path, recursive?}           -> deleted flag (needs approval)
/// - `exists` {path}                       -> bool
/// - `stat`   {path}                       -> type/size/modified
/// - `mkdir`  {path}                       -> created flag
class FileTool extends Tool {
  static const int _maxReadBytes = 512 * 1024;

  @override
  String get name => 'file';

  @override
  String get description =>
      'Read, write, list, delete and inspect files on the local filesystem.';

  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['read', 'write', 'list', 'delete', 'exists', 'stat', 'mkdir'],
          'required': true,
        },
        'path': {'type': 'string', 'required': false},
        'dir': {'type': 'string', 'required': false},
        'content': {'type': 'string', 'required': false},
        'append': {'type': 'bool', 'required': false},
        'recursive': {'type': 'bool', 'required': false},
        'maxBytes': {'type': 'int', 'required': false},
      };

  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'description': 'Action-dependent payload (text, entries, stats...)',
      };

  @override
  Future<PermissionDecision> checkPermission(ToolCall call) async {
    switch (call.action) {
      case 'read':
      case 'list':
      case 'exists':
      case 'stat':
        return const PermissionDecision.allowed('read-only filesystem access');
      case 'mkdir':
        return const PermissionDecision.allowed('directory creation');
      case 'write':
        return const PermissionDecision.allowed('file write');
      case 'delete':
        return const PermissionDecision.needsApproval(
            'deletion is destructive and needs user approval');
      default:
        return PermissionDecision.denied('Unknown file action "${call.action}"');
    }
  }

  @override
  Future<ToolResult> execute(ToolCall call) async {
    try {
      switch (call.action) {
        case 'read':
          return ToolResult.ok(await _read(call));
        case 'write':
          return ToolResult.ok(await _write(call));
        case 'list':
          return ToolResult.ok(await _list(call));
        case 'delete':
          return ToolResult.ok(await _delete(call));
        case 'exists':
          return ToolResult.ok(await _exists(call));
        case 'stat':
          return ToolResult.ok(await _stat(call));
        case 'mkdir':
          return ToolResult.ok(await _mkdir(call));
        default:
          return ToolResult.fail('Unknown file action "${call.action}"');
      }
    } catch (e) {
      return ToolResult.fail('file.${call.action} failed: $e');
    }
  }

  @override
  Future<bool> verify(ToolCall call, ToolResult result) async {
    if (!result.success) return true; // failures are already explicit
    switch (call.action) {
      case 'read':
        return result.data is Map && (result.data as Map).containsKey('content');
      case 'write':
        return result.data is Map &&
            (result.data as Map)['bytesWritten'] is int;
      case 'list':
        return result.data is Map && (result.data as Map)['entries'] is List;
      default:
        return true;
    }
  }

  // --- actions ------------------------------------------------------------

  Future<Map<String, dynamic>> _read(ToolCall call) async {
    final path = _req(call, 'path');
    final maxBytes = (call.args['maxBytes'] as int?) ?? _maxReadBytes;
    final file = File(path);
    if (!await file.exists()) throw StateError('File not found: $path');
    final bytes = await file.readAsBytes();
    final truncated = bytes.length > maxBytes;
    final slice = truncated ? bytes.sublist(0, maxBytes) : bytes;
    return {
      'path': path,
      'bytes': bytes.length,
      'truncated': truncated,
      'content': String.fromCharCodes(slice),
    };
  }

  Future<Map<String, dynamic>> _write(ToolCall call) async {
    final path = _req(call, 'path');
    final content = call.args['content'] as String? ?? '';
    final append = call.args['append'] as bool? ?? false;
    final file = File(path);
    await file.parent.create(recursive: true);
    if (append) {
      await file.writeAsString(content, mode: FileMode.append);
    } else {
      await file.writeAsString(content);
    }
    return {'path': path, 'bytesWritten': content.length, 'append': append};
  }

  Future<Map<String, dynamic>> _list(ToolCall call) async {
    final dirPath = (call.args['dir'] as String?) ?? (call.args['path'] as String?) ?? '.';
    final recursive = call.args['recursive'] as bool? ?? false;
    final dir = Directory(dirPath);
    if (!await dir.exists()) throw StateError('Directory not found: $dirPath');
    final entries = await dir.list(recursive: recursive).toList();
    return {
      'dir': dirPath,
      'count': entries.length,
      'entries': entries.map((e) {
        final isDir = e is Directory;
        return {
          'path': e.path,
          'type': isDir ? 'dir' : (e is Link ? 'link' : 'file'),
        };
      }).toList(),
    };
  }

  Future<Map<String, dynamic>> _delete(ToolCall call) async {
    final path = _req(call, 'path');
    final recursive = call.args['recursive'] as bool? ?? false;
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.notFound) {
      return {'path': path, 'deleted': false, 'reason': 'not found'};
    }
    await FileSystemEntity.isDirectorySync(path)
        ? await Directory(path).delete(recursive: recursive)
        : await File(path).delete();
    return {'path': path, 'deleted': true};
  }

  Future<Map<String, dynamic>> _exists(ToolCall call) async {
    final path = _req(call, 'path');
    final type = await FileSystemEntity.type(path);
    return {'path': path, 'exists': type != FileSystemEntityType.notFound};
  }

  Future<Map<String, dynamic>> _stat(ToolCall call) async {
    final path = _req(call, 'path');
    final stat = await FileStat.stat(path);
    return {
      'path': path,
      'type': stat.type.toString().split('.').last,
      'size': stat.size,
      'modified': stat.modified.toIso8601String(),
      'accessed': stat.accessed.toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> _mkdir(ToolCall call) async {
    final path = _req(call, 'path');
    final dir = await Directory(path).create(recursive: true);
    return {'path': dir.path, 'created': true};
  }

  String _req(ToolCall call, String key) {
    final v = call.args[key] as String?;
    if (v == null || v.isEmpty) {
      throw ArgumentError('file.${call.action} requires argument "$key"');
    }
    return v;
  }
}
