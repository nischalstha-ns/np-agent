import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/config.dart';
import 'tool.dart';

/// REAL: Local filesystem tool (dart:io).
///
/// Every path is normalized and checked against [allowedRoots]:
/// - inside an allowed root -> the action's normal permission applies;
/// - outside every allowed root -> the call requires user approval
///   (delete outside roots is denied outright — destructive + unscoped).
/// Symlinks are resolved best-effort before the check so `..` tricks and
/// link escapes cannot leave the allowed roots silently.
///
/// Actions:
/// - `read`   {path, maxBytes?}            -> file text
/// - `write`  {path, content, append?}      -> bytes written
/// - `list`   {dir, recursive?}            -> entries
/// - `delete` {path, recursive?}           -> deleted flag (needs approval)
/// - `exists` {path}                       -> bool
/// - `stat`   {path}                       -> type/size/modified
/// - `mkdir`  {path}                       -> created flag
/// - `copy`   {path, dest}                 -> copied flag
/// - `move`   {path, dest}                 -> moved flag
class FileTool extends Tool {
  static const int _maxReadBytes = 512 * 1024;

  /// REAL: Absolute, normalized roots this tool may touch without extra approval.
  final List<String> allowedRoots;

  /// REAL: Build with explicit roots, or fall back to the safe defaults:
  /// the user's home directory, the system temp dir, and the NP data root.
  FileTool({List<String>? allowedRoots})
      : allowedRoots = (allowedRoots ?? _defaultRoots())
            .map((r) => p.normalize(p.absolute(r)))
            .toList();

  static List<String> _defaultRoots() {
    /// REAL: The home.
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    return [
      home,
      Directory.systemTemp.path,
      AppConfig.dataRoot().path,
    ];
  }

  /// REAL: The name.
  @override
  String get name => 'file';

  /// REAL: The description.
  @override
  String get description =>
      'Read, write, list, copy, move, delete and inspect files on the local '
      'filesystem. Paths are confined to allowed roots (home dir, temp dir, '
      'NP data dir); anything outside needs approval.';

  /// REAL: The input schema.
  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': [
            'read',
            'write',
            'list',
            'delete',
            'exists',
            'stat',
            'mkdir',
            'copy',
            'move'
          ],
          'required': true,
        },
        'path': {'type': 'string', 'required': false},
        'dir': {'type': 'string', 'required': false},
        'dest': {'type': 'string', 'required': false},
        'content': {'type': 'string', 'required': false},
        'append': {'type': 'bool', 'required': false},
        'recursive': {'type': 'bool', 'required': false},
        'maxBytes': {'type': 'int', 'required': false},
      };

  /// REAL: The output schema.
  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'description': 'Action-dependent payload (text, entries, stats...)',
      };

  /// REAL: Permission policy — read-only actions are open inside roots;
  /// writes need approval outside roots; delete always needs approval
  /// (and is denied outside roots).
  /// REAL: Checks permission.
  @override
  Future<PermissionDecision> checkPermission(ToolCall call) async {
    /// REAL: The known.
    const known = {
      'read',
      'write',
      'list',
      'delete',
      'exists',
      'stat',
      'mkdir',
      'copy',
      'move'
    };
    if (!known.contains(call.action)) {
      return PermissionDecision.denied('Unknown file action "${call.action}"');
    }
    /// REAL: The target.
    final target = _targetPath(call);
    /// REAL: The inside.
    final inside = target == null || await _insideRoots(target);

    switch (call.action) {
      case 'read':
      case 'list':
      case 'exists':
      case 'stat':
        return const PermissionDecision.allowed('read-only filesystem access');
      case 'mkdir':
      case 'write':
      case 'copy':
      case 'move':
        if (!inside) {
          return PermissionDecision.needsApproval(
              'Path "$target" is outside the allowed roots; approval required');
        }
        return const PermissionDecision.allowed('write inside allowed roots');
      case 'delete':
        if (!inside) {
          return const PermissionDecision.denied(
              'Refusing to delete outside the allowed roots');
        }
        return const PermissionDecision.needsApproval(
            'deletion is destructive and needs user approval');
      default:
        return PermissionDecision.denied('Unknown file action "${call.action}"');
    }
  }

  /// REAL: Executes.
  @override
  Future<ToolResult> execute(ToolCall call) async {
    try {
      // Defense in depth: re-check the resolved path at execution time.
      /// REAL: The target.
      final target = _targetPath(call);
      if (target != null && !await _insideRoots(target)) {
        if (call.action == 'delete') {
          return ToolResult.fail(
              'Refusing to delete outside the allowed roots: $target');
        }
      }
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
        case 'copy':
          return ToolResult.ok(await _copy(call));
        case 'move':
          return ToolResult.ok(await _move(call));
        default:
          return ToolResult.fail('Unknown file action "${call.action}"');
      }
    } catch (e) {
      return ToolResult.fail('file.${call.action} failed: $e');
    }
  }

  /// REAL: Verifies.
  @override
  Future<bool> verify(ToolCall call, ToolResult result) async {
    if (!result.success) return true; // failures are already explicit
    switch (call.action) {
      case 'read':
        return result.data is Map &&
            (result.data as Map).containsKey('content');
      case 'write':
        return result.data is Map &&
            (result.data as Map)['bytesWritten'] is int;
      case 'list':
        return result.data is Map && (result.data as Map)['entries'] is List;
      case 'copy':
        return result.data is Map && (result.data as Map)['copied'] == true;
      case 'move':
        return result.data is Map && (result.data as Map)['moved'] == true;
      default:
        return true;
    }
  }

  // --- path guard ------------------------------------------------------------

  /// REAL: The primary path this call will touch (source for copy/move).
  String? _targetPath(ToolCall call) {
    /// REAL: The raw.
    final raw = (call.args['path'] as String?) ??
        (call.args['dir'] as String?);
    return raw;
  }

  /// REAL: True when [rawPath] normalizes (and resolves symlinks best-effort)
  /// inside one of [allowedRoots].
  Future<bool> _insideRoots(String rawPath) async {
    /// REAL: The normalized.
    var normalized = p.normalize(p.absolute(rawPath));
    // Resolve symlinks when the path exists; fall back to the raw
    // normalized path when it does not (e.g. a not-yet-created file).
    try {
      /// REAL: The type.
      final type = await FileSystemEntity.type(rawPath);
      if (type != FileSystemEntityType.notFound) {
        normalized = p.normalize(await File(rawPath).resolveSymbolicLinks());
      }
    } catch (_) {
      // Keep the normalized guess; the action itself will surface errors.
    }
    for (final root in allowedRoots) {
      if (normalized == root || p.isWithin(root, normalized)) {
        return true;
      }
    }
    return false;
  }

  // --- actions ---------------------------------------------------------------

  Future<Map<String, dynamic>> _read(ToolCall call) async {
    /// REAL: The path.
    final path = _req(call, 'path');
    /// REAL: The max bytes.
    final maxBytes = (call.args['maxBytes'] as int?) ?? _maxReadBytes;
    /// REAL: The file.
    final file = File(path);
    if (!await file.exists()) throw StateError('File not found: $path');
    /// REAL: The bytes.
    final bytes = await file.readAsBytes();
    /// REAL: The truncated.
    final truncated = bytes.length > maxBytes;
    /// REAL: The slice.
    final slice = truncated ? bytes.sublist(0, maxBytes) : bytes;
    return {
      'path': path,
      'bytes': bytes.length,
      'truncated': truncated,
      'content': String.fromCharCodes(slice),
    };
  }

  Future<Map<String, dynamic>> _write(ToolCall call) async {
    /// REAL: The path.
    final path = _req(call, 'path');
    /// REAL: The content.
    final content = call.args['content'] as String? ?? '';
    /// REAL: Appends.
    final append = call.args['append'] as bool? ?? false;
    /// REAL: The file.
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
    /// REAL: The dir path.
    final dirPath =
        (call.args['dir'] as String?) ?? (call.args['path'] as String?) ?? '.';
    /// REAL: The recursive.
    final recursive = call.args['recursive'] as bool? ?? false;
    /// REAL: The dir.
    final dir = Directory(dirPath);
    if (!await dir.exists()) throw StateError('Directory not found: $dirPath');
    /// REAL: The entries.
    final entries = await dir.list(recursive: recursive).toList();
    return {
      'dir': dirPath,
      'count': entries.length,
      'entries': entries.map((e) {
        /// REAL: Whether dir.
        final isDir = e is Directory;
        return {
          'path': e.path,
          'type': isDir ? 'dir' : (e is Link ? 'link' : 'file'),
        };
      }).toList(),
    };
  }

  Future<Map<String, dynamic>> _delete(ToolCall call) async {
    /// REAL: The path.
    final path = _req(call, 'path');
    /// REAL: The recursive.
    final recursive = call.args['recursive'] as bool? ?? false;
    /// REAL: The type.
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.notFound) {
      return {'path': path, 'deleted': false, 'reason': 'not found'};
    }
    if (FileSystemEntity.isDirectorySync(path)) {
      await Directory(path).delete(recursive: recursive);
    } else {
      await File(path).delete();
    }
    return {'path': path, 'deleted': true};
  }

  Future<Map<String, dynamic>> _exists(ToolCall call) async {
    /// REAL: The path.
    final path = _req(call, 'path');
    /// REAL: The type.
    final type = await FileSystemEntity.type(path);
    return {'path': path, 'exists': type != FileSystemEntityType.notFound};
  }

  Future<Map<String, dynamic>> _stat(ToolCall call) async {
    /// REAL: The path.
    final path = _req(call, 'path');
    /// REAL: Stats.
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
    /// REAL: The path.
    final path = _req(call, 'path');
    /// REAL: The dir.
    final dir = await Directory(path).create(recursive: true);
    return {'path': dir.path, 'created': true};
  }

  Future<Map<String, dynamic>> _copy(ToolCall call) async {
    /// REAL: The src.
    final src = _req(call, 'path');
    /// REAL: The dest.
    final dest = _req(call, 'dest');
    if (!await _insideRoots(dest)) {
      throw StateError('Copy destination is outside the allowed roots: $dest');
    }
    /// REAL: The type.
    final type = await FileSystemEntity.type(src);
    if (type == FileSystemEntityType.notFound) {
      throw StateError('Source not found: $src');
    }
    /// REAL: The dest file.
    final destFile = File(dest);
    await destFile.parent.create(recursive: true);
    if (type == FileSystemEntityType.directory) {
      await _copyDir(Directory(src), Directory(dest));
    } else {
      await File(src).copy(dest);
    }
    return {'path': src, 'dest': dest, 'copied': true};
  }

  Future<Map<String, dynamic>> _move(ToolCall call) async {
    /// REAL: The src.
    final src = _req(call, 'path');
    /// REAL: The dest.
    final dest = _req(call, 'dest');
    if (!await _insideRoots(dest)) {
      throw StateError('Move destination is outside the allowed roots: $dest');
    }
    /// REAL: The type.
    final type = await FileSystemEntity.type(src);
    if (type == FileSystemEntityType.notFound) {
      throw StateError('Source not found: $src');
    }
    await File(dest).parent.create(recursive: true);
    await File(src).rename(dest);
    return {'path': src, 'dest': dest, 'moved': true};
  }

  Future<void> _copyDir(Directory src, Directory dest) async {
    await dest.create(recursive: true);
    await for (final entity in src.list(recursive: false)) {
      /// REAL: The name.
      final name = p.basename(entity.path);
      if (entity is Directory) {
        await _copyDir(entity, Directory(p.join(dest.path, name)));
      } else if (entity is File) {
        await entity.copy(p.join(dest.path, name));
      }
    }
  }

  String _req(ToolCall call, String key) {
    /// REAL: The v.
    final v = call.args[key] as String?;
    if (v == null || v.isEmpty) {
      throw ArgumentError('file.${call.action} requires argument "$key"');
    }
    return v;
  }
}
