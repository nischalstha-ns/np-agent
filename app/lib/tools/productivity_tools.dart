import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../agents/automation_agent.dart';
import '../core/config.dart';
import '../memory/memory_store.dart';
import 'tool.dart';

/// REAL: Tiny JSON-file list store used by [CalendarTool] and [EmailTool].
///
/// Each item is a `Map<String, dynamic>` with a string `id`. The whole list
/// is rewritten on every mutation — fine for personal-scale data, honest
/// about its simplicity.
class JsonFileStore {
  /// REAL: File backing this store (created lazily on first write).
  final File file;

  JsonFileStore(String path) : file = File(path);

  /// REAL: Read every item; returns [] when the file is missing/empty.
  Future<List<Map<String, dynamic>>> readAll() async {
    if (!await file.exists()) return [];
    /// REAL: The raw.
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return [];
    /// REAL: The decoded.
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  /// REAL: Persist the whole item list.
  Future<void> writeAll(List<Map<String, dynamic>> items) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(items));
  }

  /// REAL: Generate a unique id with a prefix.
  static String newId(String prefix) =>
      '${prefix}_${DateTime.now().millisecondsSinceEpoch}';
}

/// REAL: Calendar backed by a local JSON file (default `~/.np/calendar.json`).
///
/// Actions:
/// - `list`   {from?, to?, limit?}          -> {events}
/// - `create` {title, start, end?, description?} -> {event}
/// - `delete` {id}                          -> {deleted}
///
/// Dates are ISO-8601 strings. This is a local store — there is no cloud
/// calendar sync in this build.
class CalendarTool extends Tool {
  /// REAL: The JSON file store holding the events.
  final JsonFileStore store;

  CalendarTool({String? storePath})
      : store = JsonFileStore(storePath ??
            '${AppConfig.dataRoot().path}/calendar.json');

  /// REAL: The name.
  @override
  String get name => 'calendar';

  /// REAL: The description.
  @override
  String get description =>
      'List, create and delete calendar events in the local calendar store '
      '(~/.np/calendar.json). No cloud sync in this build.';

  /// REAL: The input schema.
  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['list', 'create', 'delete'],
          'required': true,
        },
        'id': {'type': 'string', 'required': false},
        'title': {'type': 'string', 'required': false},
        'start': {'type': 'string', 'required': false},
        'end': {'type': 'string', 'required': false},
        'description': {'type': 'string', 'required': false},
        'from': {'type': 'string', 'required': false},
        'to': {'type': 'string', 'required': false},
        'limit': {'type': 'int', 'required': false},
      };

  /// REAL: The output schema.
  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'properties': {
          'events': {'type': 'array'},
          'event': {'type': 'object'},
          'deleted': {'type': 'bool'},
        },
      };

  /// REAL: Local data — everything allowed; delete needs approval.
  /// REAL: Checks permission.
  @override
  Future<PermissionDecision> checkPermission(ToolCall call) async {
    switch (call.action) {
      case 'list':
      case 'create':
        return const PermissionDecision.allowed('local calendar store');
      case 'delete':
        return const PermissionDecision.needsApproval(
            'deleting a calendar event is destructive');
      default:
        return PermissionDecision.denied(
            'Unknown calendar action "${call.action}"');
    }
  }

  /// REAL: Executes.
  @override
  Future<ToolResult> execute(ToolCall call) async {
    try {
      switch (call.action) {
        case 'list':
          return ToolResult.ok({'events': await _list(call)});
        case 'create':
          return ToolResult.ok({'event': await _create(call)});
        case 'delete':
          return ToolResult.ok(await _delete(call));
        default:
          return ToolResult.fail('Unknown calendar action "${call.action}"');
      }
    } catch (e) {
      return ToolResult.fail('calendar.${call.action} failed: $e');
    }
  }

  /// REAL: Verifies.
  @override
  Future<bool> verify(ToolCall call, ToolResult result) async {
    if (!result.success) return true;
    /// REAL: The data.
    final data = result.data as Map?;
    if (data == null) return false;
    switch (call.action) {
      case 'list':
        return data['events'] is List;
      case 'create':
        return (data['event'] as Map?)?.containsKey('id') == true;
      case 'delete':
        return data['deleted'] is bool;
      default:
        return true;
    }
  }

  Future<List<Map<String, dynamic>>> _list(ToolCall call) async {
    /// REAL: The from.
    final from = _tryParse(call.args['from'] as String?);
    /// REAL: The to.
    final to = _tryParse(call.args['to'] as String?);
    /// REAL: The limit.
    final limit = (call.args['limit'] as int?) ?? 50;
    /// REAL: The events.
    final events = await store.readAll();
    /// REAL: The filtered.
    final filtered = events.where((e) {
      /// REAL: Starts.
      final start = _tryParse(e['start'] as String?);
      if (start == null) return true;
      if (from != null && start.isBefore(from)) return false;
      if (to != null && start.isAfter(to)) return false;
      return true;
    }).toList()
      ..sort((a, b) => '${a['start']}'.compareTo('${b['start']}'));
    return filtered.take(limit).toList();
  }

  Future<Map<String, dynamic>> _create(ToolCall call) async {
    /// REAL: The title.
    final title = (call.args['title'] as String? ?? '').trim();
    /// REAL: Starts raw.
    final startRaw = call.args['start'] as String?;
    if (title.isEmpty) throw ArgumentError('create requires "title"');
    if (startRaw == null || _tryParse(startRaw) == null) {
      throw ArgumentError('create requires a valid ISO-8601 "start"');
    }
    /// REAL: The event.
    final event = {
      'id': JsonFileStore.newId('evt'),
      'title': title,
      'start': startRaw,
      'end': call.args['end'] as String?,
      'description': call.args['description'] as String?,
      'created_at': DateTime.now().toIso8601String(),
    };
    /// REAL: The events.
    final events = await store.readAll();
    events.add(event);
    await store.writeAll(events);
    return event;
  }

  Future<Map<String, dynamic>> _delete(ToolCall call) async {
    /// REAL: The id.
    final id = call.args['id'] as String?;
    if (id == null || id.isEmpty) {
      throw ArgumentError('delete requires "id"');
    }
    /// REAL: The events.
    final events = await store.readAll();
    /// REAL: The before.
    final before = events.length;
    events.removeWhere((e) => e['id'] == id);
    await store.writeAll(events);
    return {'id': id, 'deleted': events.length < before};
  }

  DateTime? _tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}

/// REAL: Mailbox backed by a local JSON file (default `~/.np/email.json`).
///
/// Actions:
/// - `list`   {query?, limit?}              -> {messages}
/// - `read`   {id}                          -> {message} (marks read)
/// - `send`   {to, subject, body}           -> {message} (queued in the
///   local outbox — no SMTP is configured in this build, so nothing leaves
///   the device; the message is stored with `folder: 'outbox'`)
/// - `delete` {id}                          -> {deleted}
class EmailTool extends Tool {
  /// REAL: The JSON file store holding the messages.
  final JsonFileStore store;

  EmailTool({String? storePath})
      : store = JsonFileStore(
            storePath ?? '${AppConfig.dataRoot().path}/email.json');

  /// REAL: The name.
  @override
  String get name => 'email';

  /// REAL: The description.
  @override
  String get description =>
      'Search, read, queue and delete messages in the local mailbox store '
      '(~/.np/email.json). Sending queues to a local outbox; no SMTP is '
      'configured, so mail never leaves the device in this build.';

  /// REAL: The input schema.
  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['list', 'read', 'send', 'delete'],
          'required': true,
        },
        'id': {'type': 'string', 'required': false},
        'query': {'type': 'string', 'required': false},
        'to': {'type': 'string', 'required': false},
        'subject': {'type': 'string', 'required': false},
        'body': {'type': 'string', 'required': false},
        'limit': {'type': 'int', 'required': false},
      };

  /// REAL: The output schema.
  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'properties': {
          'messages': {'type': 'array'},
          'message': {'type': 'object'},
          'deleted': {'type': 'bool'},
        },
      };

  /// REAL: Reading is open; send/delete need approval (outward/destructive).
  /// REAL: Checks permission.
  @override
  Future<PermissionDecision> checkPermission(ToolCall call) async {
    switch (call.action) {
      case 'list':
      case 'read':
        return const PermissionDecision.allowed('local mailbox read');
      case 'send':
        return const PermissionDecision.needsApproval(
            'sending email is an outward action');
      case 'delete':
        return const PermissionDecision.needsApproval(
            'deleting a message is destructive');
      default:
        return PermissionDecision.denied(
            'Unknown email action "${call.action}"');
    }
  }

  /// REAL: Executes.
  @override
  Future<ToolResult> execute(ToolCall call) async {
    try {
      switch (call.action) {
        case 'list':
          return ToolResult.ok({'messages': await _list(call)});
        case 'read':
          return ToolResult.ok({'message': await _read(call)});
        case 'send':
          return ToolResult.ok({'message': await _send(call)});
        case 'delete':
          return ToolResult.ok(await _delete(call));
        default:
          return ToolResult.fail('Unknown email action "${call.action}"');
      }
    } catch (e) {
      return ToolResult.fail('email.${call.action} failed: $e');
    }
  }

  /// REAL: Verifies.
  @override
  Future<bool> verify(ToolCall call, ToolResult result) async {
    if (!result.success) return true;
    /// REAL: The data.
    final data = result.data as Map?;
    if (data == null) return false;
    switch (call.action) {
      case 'list':
        return data['messages'] is List;
      case 'read':
      case 'send':
        return (data['message'] as Map?)?.containsKey('id') == true;
      case 'delete':
        return data['deleted'] is bool;
      default:
        return true;
    }
  }

  Future<List<Map<String, dynamic>>> _list(ToolCall call) async {
    /// REAL: The query.
    final query = (call.args['query'] as String? ?? '').toLowerCase();
    /// REAL: The limit.
    final limit = (call.args['limit'] as int?) ?? 50;
    /// REAL: The messages.
    final messages = await store.readAll();
    /// REAL: The filtered.
    final filtered = query.isEmpty
        ? messages
        : messages.where((m) {
            /// REAL: The hay.
            final hay =
                '${m['to']} ${m['subject']} ${m['body']}'.toLowerCase();
            return hay.contains(query);
          }).toList();
    filtered.sort((a, b) =>
        '${b['created_at']}'.compareTo('${a['created_at']}'));
    return filtered.take(limit).toList();
  }

  Future<Map<String, dynamic>> _read(ToolCall call) async {
    /// REAL: The id.
    final id = call.args['id'] as String?;
    if (id == null || id.isEmpty) throw ArgumentError('read requires "id"');
    /// REAL: The messages.
    final messages = await store.readAll();
    /// REAL: The msg.
    final msg = messages.firstWhere((m) => m['id'] == id,
        orElse: () => throw StateError('Message not found: $id'));
    msg['read'] = true;
    await store.writeAll(messages);
    return msg;
  }

  Future<Map<String, dynamic>> _send(ToolCall call) async {
    /// REAL: The to.
    final to = (call.args['to'] as String? ?? '').trim();
    /// REAL: The subject.
    final subject = call.args['subject'] as String? ?? '';
    /// REAL: The body.
    final body = call.args['body'] as String? ?? '';
    if (to.isEmpty) throw ArgumentError('send requires "to"');
    /// REAL: The msg.
    final msg = {
      'id': JsonFileStore.newId('msg'),
      'to': to,
      'subject': subject,
      'body': body,
      'folder': 'outbox',
      'read': true,
      'created_at': DateTime.now().toIso8601String(),
      'note': 'Queued locally; no SMTP configured in this build.',
    };
    /// REAL: The messages.
    final messages = await store.readAll();
    messages.add(msg);
    await store.writeAll(messages);
    return msg;
  }

  Future<Map<String, dynamic>> _delete(ToolCall call) async {
    /// REAL: The id.
    final id = call.args['id'] as String?;
    if (id == null || id.isEmpty) {
      throw ArgumentError('delete requires "id"');
    }
    /// REAL: The messages.
    final messages = await store.readAll();
    /// REAL: The before.
    final before = messages.length;
    messages.removeWhere((m) => m['id'] == id);
    await store.writeAll(messages);
    return {'id': id, 'deleted': messages.length < before};
  }
}

/// REAL: Task/todo management over the app's [MemoryStore] `tasks` table.
///
/// Actions:
/// - `list`     {status?, limit?}   -> {tasks}
/// - `create`   {title}              -> {task}
/// - `complete` {id}                 -> {task} (status -> 'done')
/// - `update`   {id, status}        -> {task}
/// - `delete`   {id}                 -> {deleted}
///
/// Task ids created here are indexed in `~/.np/task_index.json` so `list`
/// can enumerate them (the store's public API has no list-all-tasks).
class TaskTool extends Tool {
  /// REAL: The memory store backing the tasks table.
  final MemoryStore store;

  /// REAL: Local index of task ids created through this tool.
  final JsonFileStore index;

  TaskTool({required this.store, String? indexPath})
      : index = JsonFileStore(indexPath ??
            '${AppConfig.dataRoot().path}/task_index.json');

  /// REAL: The name.
  @override
  String get name => 'task';

  /// REAL: The description.
  @override
  String get description =>
      'Create, list, complete, update and delete to-do tasks, persisted in '
      'the NP memory store.';

  /// REAL: The input schema.
  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['list', 'create', 'complete', 'update', 'delete'],
          'required': true,
        },
        'id': {'type': 'string', 'required': false},
        'title': {'type': 'string', 'required': false},
        'status': {'type': 'string', 'required': false},
        'limit': {'type': 'int', 'required': false},
      };

  /// REAL: The output schema.
  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'properties': {
          'tasks': {'type': 'array'},
          'task': {'type': 'object'},
          'deleted': {'type': 'bool'},
        },
      };

  /// REAL: Local data — all actions allowed; delete needs approval.
  /// REAL: Checks permission.
  @override
  Future<PermissionDecision> checkPermission(ToolCall call) async {
    switch (call.action) {
      case 'list':
      case 'create':
      case 'complete':
      case 'update':
        return const PermissionDecision.allowed('local task management');
      case 'delete':
        return const PermissionDecision.needsApproval(
            'deleting a task is destructive');
      default:
        return PermissionDecision.denied(
            'Unknown task action "${call.action}"');
    }
  }

  /// REAL: Executes.
  @override
  Future<ToolResult> execute(ToolCall call) async {
    try {
      switch (call.action) {
        case 'list':
          return ToolResult.ok({'tasks': await _list(call)});
        case 'create':
          return ToolResult.ok({'task': await _create(call)});
        case 'complete':
          return ToolResult.ok(
              {'task': await _updateStatus(call, 'done')});
        case 'update':
          return ToolResult.ok({'task': await _update(call)});
        case 'delete':
          return ToolResult.ok(await _delete(call));
        default:
          return ToolResult.fail('Unknown task action "${call.action}"');
      }
    } catch (e) {
      return ToolResult.fail('task.${call.action} failed: $e');
    }
  }

  /// REAL: Verifies.
  @override
  Future<bool> verify(ToolCall call, ToolResult result) async {
    if (!result.success) return true;
    /// REAL: The data.
    final data = result.data as Map?;
    if (data == null) return false;
    switch (call.action) {
      case 'list':
        return data['tasks'] is List;
      case 'create':
      case 'complete':
      case 'update':
        return (data['task'] as Map?)?.containsKey('id') == true;
      case 'delete':
        return data['deleted'] is bool;
      default:
        return true;
    }
  }

  Future<List<Map<String, dynamic>>> _list(ToolCall call) async {
    /// REAL: The status.
    final status = call.args['status'] as String?;
    /// REAL: The limit.
    final limit = (call.args['limit'] as int?) ?? 100;
    /// REAL: The ids.
    final ids = (await index.readAll())
        .map((e) => e['id'] as String?)
        .whereType<String>();
    /// REAL: The tasks.
    final tasks = <Map<String, dynamic>>[];
    for (final id in ids) {
      /// REAL: The row.
      final row = await store.getTask(id);
      if (row == null) continue;
      if (status != null && row['status'] != status) continue;
      tasks.add(_rowToTask(row));
    }
    tasks.sort((a, b) =>
        (b['created_at'] as int).compareTo(a['created_at'] as int));
    return tasks.take(limit).toList();
  }

  Future<Map<String, dynamic>> _create(ToolCall call) async {
    /// REAL: The title.
    final title = (call.args['title'] as String? ?? '').trim();
    if (title.isEmpty) throw ArgumentError('create requires "title"');
    /// REAL: The id.
    final id = JsonFileStore.newId('task');
    await store.createTask(id, title);
    /// REAL: The ids.
    final ids = await index.readAll();
    ids.add({'id': id});
    await index.writeAll(ids);
    /// REAL: The row.
    final row = await store.getTask(id);
    return _rowToTask(row!);
  }

  Future<Map<String, dynamic>> _updateStatus(
      ToolCall call, String status) async {
    /// REAL: The id.
    final id = call.args['id'] as String?;
    if (id == null || id.isEmpty) {
      throw ArgumentError('${call.action} requires "id"');
    }
    /// REAL: The existing.
    final existing = await store.getTask(id);
    if (existing == null) throw StateError('Task not found: $id');
    await store.updateTaskStatus(id, status);
    /// REAL: The row.
    final row = await store.getTask(id);
    return _rowToTask(row!);
  }

  Future<Map<String, dynamic>> _update(ToolCall call) async {
    /// REAL: The status.
    final status = (call.args['status'] as String? ?? '').trim();
    if (status.isEmpty) throw ArgumentError('update requires "status"');
    return _updateStatus(call, status);
  }

  Future<Map<String, dynamic>> _delete(ToolCall call) async {
    /// REAL: The id.
    final id = call.args['id'] as String?;
    if (id == null || id.isEmpty) throw ArgumentError('delete requires "id"');
    /// REAL: The existing.
    final existing = await store.getTask(id);
    if (existing == null) return {'id': id, 'deleted': false};
    // The store has no deleteTask; tombstone via status.
    await store.updateTaskStatus(id, 'deleted');
    /// REAL: The ids.
    final ids = await index.readAll();
    ids.removeWhere((e) => e['id'] == id);
    await index.writeAll(ids);
    return {'id': id, 'deleted': true};
  }

  Map<String, dynamic> _rowToTask(Map<String, Object?> row) => {
        'id': row['id'],
        'title': row['input'],
        'status': row['status'],
        'created_at': row['created_at'],
        'updated_at': row['updated_at'],
      };
}

/// REAL: Read-only queries over the app's own [MemoryStore].
///
/// Actions:
/// - `memoryItems` {layer?, limit?} -> {rows} from `memory_items`
/// - `toolUsage`   {tool?, limit?}   -> {rows} from `tool_usage`
/// - `successRate` {tool}            -> {tool, successRate}
/// - `tables`                       -> {tables} (the tables this tool covers)
class DatabaseTool extends Tool {
  /// REAL: The memory store being queried.
  final MemoryStore store;

  DatabaseTool({required this.store});

  /// REAL: The name.
  @override
  String get name => 'database';

  /// REAL: The description.
  @override
  String get description =>
      'Query NP\'s own memory database (memory_items and tool_usage tables). '
      'Read-only.';

  /// REAL: The input schema.
  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['memoryItems', 'toolUsage', 'successRate', 'tables'],
          'required': true,
        },
        'layer': {'type': 'string', 'required': false},
        'tool': {'type': 'string', 'required': false},
        'limit': {'type': 'int', 'required': false},
      };

  /// REAL: The output schema.
  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'description': 'Action-dependent payload (rows / rate / tables).',
      };

  /// REAL: Read-only local queries — always allowed.
  /// REAL: Checks permission.
  @override
  Future<PermissionDecision> checkPermission(ToolCall call) async {
    switch (call.action) {
      case 'memoryItems':
      case 'toolUsage':
      case 'successRate':
      case 'tables':
        return const PermissionDecision.allowed('read-only local database');
      default:
        return PermissionDecision.denied(
            'Unknown database action "${call.action}"');
    }
  }

  /// REAL: Executes.
  @override
  Future<ToolResult> execute(ToolCall call) async {
    try {
      switch (call.action) {
        case 'memoryItems':
          return ToolResult.ok(await _memoryItems(call));
        case 'toolUsage':
          return ToolResult.ok(await _toolUsage(call));
        case 'successRate':
          return ToolResult.ok(await _successRate(call));
        case 'tables':
          return ToolResult.ok({
            'tables': ['memory_items', 'tool_usage']
          });
        default:
          return ToolResult.fail('Unknown database action "${call.action}"');
      }
    } catch (e) {
      return ToolResult.fail('database.${call.action} failed: $e');
    }
  }

  /// REAL: Verifies.
  @override
  Future<bool> verify(ToolCall call, ToolResult result) async {
    if (!result.success) return true;
    return result.data is Map;
  }

  Future<Map<String, dynamic>> _memoryItems(ToolCall call) async {
    /// REAL: The layer.
    final layer = call.args['layer'] as String?;
    /// REAL: The limit.
    final limit = (call.args['limit'] as int?) ?? 100;
    /// REAL: The rows.
    final rows = await store.getMemoryItems(
      layer: layer,
      limit: limit,
      orderByRecency: true,
    );
    return {
      'rows': rows
          .map((r) => {
                'id': r['id'],
                'layer': r['layer'],
                'key': r['key'],
                'content': r['content'],
                'importance': r['importance'],
                'updated_at': r['updated_at'],
              })
          .toList(),
      'count': rows.length,
    };
  }

  Future<Map<String, dynamic>> _toolUsage(ToolCall call) async {
    /// REAL: The tool.
    final tool = call.args['tool'] as String?;
    /// REAL: The limit.
    final limit = (call.args['limit'] as int?) ?? 100;
    /// REAL: The rows.
    var rows = await store.recentToolUsage(limit: 500);
    if (tool != null && tool.isNotEmpty) {
      rows = rows.where((r) => r['tool'] == tool).toList();
    }
    rows = rows.take(limit).toList();
    return {
      'rows': rows
          .map((r) => {
                'id': r['id'],
                'tool': r['tool'],
                'success': r['success'],
                'duration_ms': r['duration_ms'],
                'created_at': r['created_at'],
                'result_summary': r['result_summary'],
              })
          .toList(),
      'count': rows.length,
    };
  }

  Future<Map<String, dynamic>> _successRate(ToolCall call) async {
    /// REAL: The tool.
    final tool = call.args['tool'] as String?;
    if (tool == null || tool.isEmpty) {
      throw ArgumentError('successRate requires "tool"');
    }
    return {'tool': tool, 'successRate': await store.toolSuccessRate(tool)};
  }
}

/// REAL: Minimal PDF text extraction in pure Dart.
///
/// Parses text objects between BT/ET operators and decodes `Tj` (literal and
/// hex strings) and `TJ` (arrays of literal/hex strings). Handles escaped
/// parentheses, octal escapes, and UTF-16BE hex strings (FEFF prefix).
/// This is a best-effort extractor: encrypted, compressed-object-stream, or
/// exotic-encoding PDFs may yield partial text — reported honestly via
/// `extractionNotes`.
///
/// Actions:
/// - `read` {path, maxChars?} -> {pages, text, truncated}
/// - `info` {path}             -> {pages, sizeBytes}
class PdfTool extends Tool {
  /// REAL: The name.
  @override
  String get name => 'pdf';

  /// REAL: The description.
  @override
  String get description =>
      'Extract text from PDF files (pure-Dart BT/ET + Tj/TJ parsing) and '
      'report page counts. Best-effort on encrypted/exotic PDFs.';

  /// REAL: The input schema.
  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['read', 'info'],
          'required': true,
        },
        'path': {'type': 'string', 'required': true},
        'maxChars': {'type': 'int', 'required': false},
      };

  /// REAL: The output schema.
  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'properties': {
          'text': {'type': 'string'},
          'pages': {'type': 'int'},
        },
      };

  /// REAL: Read-only — always allowed.
  /// REAL: Checks permission.
  @override
  Future<PermissionDecision> checkPermission(ToolCall call) async {
    switch (call.action) {
      case 'read':
      case 'info':
        return const PermissionDecision.allowed('read-only pdf access');
      default:
        return PermissionDecision.denied('Unknown pdf action "${call.action}"');
    }
  }

  /// REAL: Executes.
  @override
  Future<ToolResult> execute(ToolCall call) async {
    try {
      /// REAL: The path.
      final path = (call.args['path'] as String?) ?? '';
      if (path.isEmpty) throw ArgumentError('pdf requires "path"');
      /// REAL: The file.
      final file = File(path);
      if (!await file.exists()) throw StateError('File not found: $path');
      /// REAL: The bytes.
      final bytes = await file.readAsBytes();
      /// REAL: The parsed.
      final parsed = _parsePdf(bytes);
      switch (call.action) {
        case 'read':
          /// REAL: The max chars.
          final maxChars = (call.args['maxChars'] as int?) ?? 20000;
          /// REAL: The text.
          final text = parsed.text;
          /// REAL: The truncated.
          final truncated = text.length > maxChars;
          return ToolResult.ok({
            'path': path,
            'pages': parsed.pages,
            'text': truncated ? text.substring(0, maxChars) : text,
            'truncated': truncated,
            'extractionNotes': parsed.notes,
          });
        case 'info':
          return ToolResult.ok({
            'path': path,
            'pages': parsed.pages,
            'sizeBytes': bytes.length,
            'extractionNotes': parsed.notes,
          });
        default:
          return ToolResult.fail('Unknown pdf action "${call.action}"');
      }
    } catch (e) {
      return ToolResult.fail('pdf.${call.action} failed: $e');
    }
  }

  /// REAL: Verifies.
  @override
  Future<bool> verify(ToolCall call, ToolResult result) async {
    if (!result.success) return true;
    /// REAL: The data.
    final data = result.data as Map?;
    if (data == null || data['pages'] is! int) return false;
    if (call.action == 'read') return data['text'] is String;
    return true;
  }

  _ParsedPdf _parsePdf(Uint8List bytes) {
    /// REAL: The raw.
    final raw = latin1.decode(bytes, allowInvalid: true);
    /// REAL: The notes.
    final notes = <String>[];
    if (raw.contains('/Encrypt')) {
      notes.add('PDF declares /Encrypt: extracted text may be garbled.');
    }
    /// REAL: The pages.
    final pages = RegExp(r'/Type\s*/Page(?!s)').allMatches(raw).length;
    /// REAL: The buf.
    final buf = StringBuffer();
    /// REAL: The blocks.
    final blocks =
        RegExp(r'BT(.*?)ET', dotAll: true).allMatches(raw).toList();
    if (blocks.isEmpty) {
      notes.add('No BT/ET text blocks found; file may be scanned images.');
    }
    for (final block in blocks) {
      /// REAL: The content.
      final content = block.group(1)!;
      // TJ arrays first (they contain Tj-like strings too).
      for (final m
          in RegExp(r'\[(.*?)\]\s*TJ', dotAll: true).allMatches(content)) {
        buf.write(_decodeTjArray(m.group(1)!));
        buf.write(' ');
      }
      // Standalone literal-string Tj (not inside a TJ array we already did).
      /// REAL: The without arrays.
      final withoutArrays =
          content.replaceAll(RegExp(r'\[.*?\]\s*TJ', dotAll: true), ' ');
      for (final m in RegExp(r'\((?:\\.|[^\\()])*\)\s*Tj')
          .allMatches(withoutArrays)) {
        buf.write(_decodeLiteral(m.group(0)!));
        buf.write(' ');
      }
      for (final m in RegExp(r'<([0-9a-fA-F\s]+)>\s*Tj')
          .allMatches(withoutArrays)) {
        buf.write(_decodeHex(m.group(1)!));
        buf.write(' ');
      }
    }
    return _ParsedPdf(
      pages: pages,
      text: buf.toString().replaceAll(RegExp(r'[ \t]+'), ' ').trim(),
      notes: notes,
    );
  }

  String _decodeTjArray(String inner) {
    /// REAL: The buf.
    final buf = StringBuffer();
    for (final m in RegExp(r'\((?:\\.|[^\\()])*\)').allMatches(inner)) {
      buf.write(_decodeLiteral(m.group(0)!));
    }
    for (final m in RegExp(r'<([0-9a-fA-F\s]+)>').allMatches(inner)) {
      buf.write(_decodeHex(m.group(1)!));
    }
    return buf.toString();
  }

  /// REAL: Decode a PDF literal string `(...)`, handling escapes.
  String _decodeLiteral(String raw) {
    /// REAL: The s.
    var s = raw.trim();
    // strip the trailing Tj if present and the surrounding parens
    s = s.replaceAll(RegExp(r'\s*Tj\s*$'), '');
    if (s.startsWith('(') && s.endsWith(')')) {
      s = s.substring(1, s.length - 1);
    }
    /// REAL: The out.
    final out = StringBuffer();
    /// REAL: The i.
    var i = 0;
    while (i < s.length) {
      /// REAL: The ch.
      final ch = s[i];
      if (ch == '\\' && i + 1 < s.length) {
        /// REAL: The next.
        final next = s[i + 1];
        switch (next) {
          case 'n':
            out.write('\n');
            i += 2;
            continue;
          case 'r':
            out.write('\r');
            i += 2;
            continue;
          case 't':
            out.write('\t');
            i += 2;
            continue;
          case '(':
          case ')':
          case '\\':
            out.write(next);
            i += 2;
            continue;
          default:
            if (RegExp(r'[0-7]').hasMatch(next)) {
              /// REAL: The oct.
              var oct = '';
              /// REAL: The j.
              var j = i + 1;
              while (j < s.length && oct.length < 3 &&
                  RegExp(r'[0-7]').hasMatch(s[j])) {
                oct += s[j];
                j++;
              }
              out.write(String.fromCharCode(int.parse(oct, radix: 8)));
              i = j;
              continue;
            }
            out.write(next);
            i += 2;
            continue;
        }
      } else {
        out.write(ch);
        i++;
      }
    }
    return out.toString();
  }

  /// REAL: Decode a PDF hex string `<...>` (UTF-16BE when FEFF-prefixed).
  String _decodeHex(String hex) {
    /// REAL: The clean.
    final clean = hex.replaceAll(RegExp(r'\s+'), '');
    if (clean.isEmpty) return '';
    /// REAL: The padded.
    final padded = clean.length.isOdd ? '${clean}0' : clean;
    /// REAL: The bytes.
    final bytes = Uint8List(padded.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(padded.substring(i * 2, i * 2 + 2), radix: 16);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      /// REAL: The units.
      final units = <int>[];
      for (var i = 2; i + 1 < bytes.length; i += 2) {
        units.add((bytes[i] << 8) | bytes[i + 1]);
      }
      return String.fromCharCodes(units);
    }
    return latin1.decode(bytes, allowInvalid: true);
  }
}

class _ParsedPdf {
  /// REAL: The pages.
  final int pages;
  /// REAL: The text.
  final String text;
  /// REAL: The notes.
  final List<String> notes;

  _ParsedPdf({required this.pages, required this.text, required this.notes});
}

/// REAL: Read/write plain-text document formats: `.txt`, `.md`, `.json`,
/// `.csv`. No native office plugin is needed for these formats.
///
/// Actions:
/// - `read`  {path, maxChars?} -> {format, text} (+ `rows` for csv,
///   `parsed` for json)
/// - `write` {path, content}   -> {bytesWritten}
class DocumentTool extends Tool {
  static const _supported = {'.txt', '.md', '.json', '.csv'};

  /// REAL: The name.
  @override
  String get name => 'document';

  /// REAL: The description.
  @override
  String get description =>
      'Read and write .txt, .md, .json and .csv documents (pure Dart). '
      'CSV is parsed into rows; JSON is validated.';

  /// REAL: The input schema.
  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['read', 'write'],
          'required': true,
        },
        'path': {'type': 'string', 'required': true},
        'content': {'type': 'string', 'required': false},
        'maxChars': {'type': 'int', 'required': false},
      };

  /// REAL: The output schema.
  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'properties': {
          'text': {'type': 'string'},
          'format': {'type': 'string'},
        },
      };

  /// REAL: Reading is open; writing is limited to supported extensions.
  /// REAL: Checks permission.
  @override
  Future<PermissionDecision> checkPermission(ToolCall call) async {
    /// REAL: The path.
    final path = (call.args['path'] as String?) ?? '';
    /// REAL: The ext.
    final ext = _ext(path);
    if (!_supported.contains(ext)) {
      return PermissionDecision.denied(
          'document tool supports only ${_supported.join(', ')} (got "$ext")');
    }
    switch (call.action) {
      case 'read':
        return const PermissionDecision.allowed('document read');
      case 'write':
        return const PermissionDecision.allowed('document write');
      default:
        return PermissionDecision.denied(
            'Unknown document action "${call.action}"');
    }
  }

  /// REAL: Executes.
  @override
  Future<ToolResult> execute(ToolCall call) async {
    try {
      /// REAL: The path.
      final path = (call.args['path'] as String?) ?? '';
      switch (call.action) {
        case 'read':
          return ToolResult.ok(await _read(call, path));
        case 'write':
          return ToolResult.ok(await _write(call, path));
        default:
          return ToolResult.fail('Unknown document action "${call.action}"');
      }
    } catch (e) {
      return ToolResult.fail('document.${call.action} failed: $e');
    }
  }

  /// REAL: Verifies.
  @override
  Future<bool> verify(ToolCall call, ToolResult result) async {
    if (!result.success) return true;
    /// REAL: The data.
    final data = result.data as Map?;
    if (data == null) return false;
    if (call.action == 'read') return data['text'] is String;
    return data['bytesWritten'] is int;
  }

  Future<Map<String, dynamic>> _read(ToolCall call, String path) async {
    /// REAL: The file.
    final file = File(path);
    if (!await file.exists()) throw StateError('File not found: $path');
    /// REAL: The ext.
    final ext = _ext(path);
    /// REAL: The max chars.
    final maxChars = (call.args['maxChars'] as int?) ?? 20000;
    /// REAL: The raw.
    final raw = await file.readAsString();
    /// REAL: The truncated.
    final truncated = raw.length > maxChars;
    /// REAL: The text.
    final text = truncated ? raw.substring(0, maxChars) : raw;
    /// REAL: The out.
    final out = <String, dynamic>{
      'path': path,
      'format': ext,
      'text': text,
      'truncated': truncated,
      'chars': raw.length,
    };
    if (ext == '.csv') {
      out['rows'] = _parseCsv(raw);
    } else if (ext == '.json') {
      try {
        out['parsed'] = jsonDecode(raw);
        out['validJson'] = true;
      } catch (e) {
        out['validJson'] = false;
        out['jsonError'] = '$e';
      }
    }
    return out;
  }

  Future<Map<String, dynamic>> _write(ToolCall call, String path) async {
    /// REAL: The content.
    final content = call.args['content'] as String? ?? '';
    /// REAL: The ext.
    final ext = _ext(path);
    if (ext == '.json') {
      jsonDecode(content); // validate before writing
    }
    /// REAL: The file.
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return {'path': path, 'bytesWritten': content.length};
  }

  String _ext(String path) {
    /// REAL: The dot.
    final dot = path.lastIndexOf('.');
    return dot < 0 ? '' : path.substring(dot).toLowerCase();
  }

  /// REAL: Minimal CSV parser (quoted fields, doubled quotes, embedded
  /// commas/newlines).
  List<List<String>> _parseCsv(String raw) {
    /// REAL: The rows.
    final rows = <List<String>>[];
    /// REAL: The row.
    var row = <String>[];
    /// REAL: The field.
    final field = StringBuffer();
    /// REAL: The in quotes.
    var inQuotes = false;
    /// REAL: The i.
    var i = 0;
    /// REAL: The end field.
    void endField() {
      row.add(field.toString());
      field.clear();
    }

    while (i < raw.length) {
      /// REAL: The ch.
      final ch = raw[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < raw.length && raw[i + 1] == '"') {
            field.write('"');
            i += 2;
          } else {
            inQuotes = false;
            i++;
          }
        } else {
          field.write(ch);
          i++;
        }
      } else if (ch == '"') {
        inQuotes = true;
        i++;
      } else if (ch == ',') {
        endField();
        i++;
      } else if (ch == '\n' || ch == '\r') {
        endField();
        rows.add(row);
        row = <String>[];
        if (ch == '\r' && i + 1 < raw.length && raw[i + 1] == '\n') i++;
        i++;
      } else {
        field.write(ch);
        i++;
      }
    }
    endField();
    if (row.length == 1 && row.first.isEmpty) {
      // trailing newline produced an empty row; drop it
      rows.add(row);
      rows.removeLast();
    } else {
      rows.add(row);
    }
    return rows;
  }
}

/// REAL: OS-level automation routines via the attached [AutomationAgent].
///
/// The tool itself holds no automation logic — it delegates to the agent,
/// which runs each routine's tool calls through the same safety gate +
/// registry dispatch as normal tool use. Without an attached agent the
/// actions report honestly that no backend is wired.
class AutomationTool extends Tool {
  /// REAL: The automation agent this tool delegates to (may be null).
  final AutomationAgent? agent;

  AutomationTool({this.agent});

  /// REAL: The name.
  @override
  String get name => 'automation';

  /// REAL: The description.
  @override
  String get description =>
      'Run named multi-step OS automation routines (delegates to the '
      'automation agent; every step still passes the safety gate).';

  /// REAL: The input schema.
  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['runRoutine', 'listRoutines'],
          'required': true,
        },
        'routine': {'type': 'string', 'required': false},
      };

  /// REAL: The output schema.
  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'properties': {
          'result': {'type': 'string'},
        },
      };

  /// REAL: Automation always needs approval (OS-level side effects).
  /// REAL: Checks permission.
  @override
  Future<PermissionDecision> checkPermission(ToolCall call) async {
    switch (call.action) {
      case 'listRoutines':
        return const PermissionDecision.allowed('routine listing');
      case 'runRoutine':
        return const PermissionDecision.needsApproval(
            'OS automation routines have system-wide side effects');
      default:
        return PermissionDecision.denied(
            'Unknown automation action "${call.action}"');
    }
  }

  /// REAL: Executes.
  @override
  Future<ToolResult> execute(ToolCall call) async {
    /// REAL: The a.
    final a = agent;
    if (a == null) {
      return ToolResult.fail(
          'automation.${call.action} failed: no automation backend attached');
    }
    try {
      switch (call.action) {
        case 'listRoutines':
          return ToolResult.ok({'routines': a.listRoutines()});
        case 'runRoutine': {
          /// REAL: The name.
          final name = call.args['routine'] as String?;
          if (name == null || name.isEmpty) {
            return ToolResult.fail('runRoutine requires "routine"');
          }
          /// REAL: The transcript.
          final transcript = await a.runRoutine(name);
          /// REAL: The ok.
          final ok = transcript.isNotEmpty &&
              transcript.every((s) =>
                  !s.blocked && (s.result?.success ?? false));
          return ToolResult.ok({
            'routine': name,
            'steps': transcript.length,
            'success': ok,
            'transcript':
                transcript.map((s) => s.toJson()).toList(),
          });
        }
        default:
          return ToolResult.fail('Unknown automation action "${call.action}"');
      }
    } catch (e) {
      return ToolResult.fail('automation.${call.action} failed: $e');
    }
  }

  /// REAL: Verifies.
  @override
  Future<bool> verify(ToolCall call, ToolResult result) async {
    if (!result.success) return true;
    /// REAL: The data.
    final data = result.data as Map?;
    if (data == null) return false;
    if (call.action == 'listRoutines') return data['routines'] is List;
    return data['success'] is bool;
  }
}

/// REAL: Web research over real HTTP sources (package:http), no API key.
///
/// Sources:
/// - DuckDuckGo HTML endpoint (`html.duckduckgo.com/html/`) — result titles,
///   URLs and snippets parsed from the response.
/// - Wikipedia API (`en.wikipedia.org/w/api.php`) — article search results.
///
/// Actions:
/// - `search`    {query, maxResults?} -> {results: [{title, url, snippet,
///   source}], offline}
/// - `summarize` {query} -> {summary, sources} — top snippets stitched with
///   citations.
///
/// When the network is unreachable both actions return `offline: true` with
/// an empty result list instead of throwing — a graceful offline fallback.
class ResearchTool extends Tool {
  final http.Client _client = http.Client();

  /// REAL: The name.
  @override
  String get name => 'research';

  /// REAL: The description.
  @override
  String get description =>
      'Web research with citations: searches DuckDuckGo and Wikipedia over '
      'real HTTP (no API key). Returns offline:true when unreachable.';

  /// REAL: The input schema.
  @override
  Map<String, dynamic> get inputSchema => {
        'action': {
          'type': 'string',
          'enum': ['search', 'summarize'],
          'required': true,
        },
        'query': {'type': 'string', 'required': true},
        'maxResults': {'type': 'int', 'required': false},
      };

  /// REAL: The output schema.
  @override
  Map<String, dynamic> get outputSchema => {
        'type': 'object',
        'properties': {
          'results': {'type': 'array'},
          'offline': {'type': 'bool'},
        },
      };

  /// REAL: Read-only web research — always allowed.
  /// REAL: Checks permission.
  @override
  Future<PermissionDecision> checkPermission(ToolCall call) async {
    switch (call.action) {
      case 'search':
      case 'summarize':
        return const PermissionDecision.allowed('read-only web research');
      default:
        return PermissionDecision.denied(
            'Unknown research action "${call.action}"');
    }
  }

  /// REAL: Executes.
  @override
  Future<ToolResult> execute(ToolCall call) async {
    try {
      /// REAL: The query.
      final query = (call.args['query'] as String? ?? '').trim();
      if (query.isEmpty) throw ArgumentError('research requires "query"');
      /// REAL: The max results.
      final maxResults = (call.args['maxResults'] as int?) ?? 8;
      /// REAL: The results.
      final results = await _searchAll(query, maxResults);
      if (call.action == 'summarize') {
        return ToolResult.ok({
          'query': query,
          'summary': _stitchSummary(query, results),
          'sources': results,
          'offline': results.isEmpty &&
              await _looksOffline(),
        });
      }
      return ToolResult.ok({
        'query': query,
        'results': results,
        'offline':
            results.isEmpty && await _looksOffline(),
      });
    } catch (e) {
      return ToolResult.fail('research.${call.action} failed: $e');
    }
  }

  /// REAL: Verifies.
  @override
  Future<bool> verify(ToolCall call, ToolResult result) async {
    if (!result.success) return true;
    /// REAL: The data.
    final data = result.data as Map?;
    if (data == null) return false;
    if (call.action == 'search') return data['results'] is List;
    return data['summary'] is String && data['sources'] is List;
  }

  /// REAL: Fan out to DuckDuckGo + Wikipedia, merge, dedupe, cap.
  Future<List<Map<String, dynamic>>> _searchAll(
      String query, int maxResults) async {
    /// REAL: The ddg.
    final ddg = _searchDuckDuckGo(query, (maxResults / 2).ceil());
    /// REAL: The wiki.
    final wiki = _searchWikipedia(query, (maxResults / 2).ceil());
    /// REAL: The settled.
    final settled = await Future.wait([ddg, wiki]);
    /// REAL: The merged.
    final merged = <Map<String, dynamic>>[
      ...settled[0],
      ...settled[1],
    ];
    /// REAL: The seen.
    final seen = <String>{};
    /// REAL: The deduped.
    final deduped = <Map<String, dynamic>>[];
    for (final r in merged) {
      /// REAL: The url.
      final url = r['url'] as String;
      if (seen.add(url)) deduped.add(r);
      if (deduped.length >= maxResults) break;
    }
    return deduped;
  }

  /// REAL: Scrape the DuckDuckGo HTML endpoint (no API key needed).
  Future<List<Map<String, dynamic>>> _searchDuckDuckGo(
      String query, int maxResults) async {
    try {
      /// REAL: The uri.
      final uri = Uri.parse(
          'https://html.duckduckgo.com/html/?q=${Uri.encodeQueryComponent(query)}');
      /// REAL: The resp.
      final resp = await _client
          .get(uri, headers: {'user-agent': 'NP-agent/0.1'})
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return [];
      return _parseDuckDuckGo(resp.body, maxResults);
    } catch (_) {
      return []; // offline or blocked -> graceful fallback
    }
  }

  /// REAL: Parse DuckDuckGo result anchors + snippets from HTML.
  List<Map<String, dynamic>> _parseDuckDuckGo(String html, int maxResults) {
    /// REAL: The results.
    final results = <Map<String, dynamic>>[];
    /// REAL: The re.
    final re = RegExp(
        r'<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
        caseSensitive: false,
        dotAll: true);
    /// REAL: The snippet re.
    final snippetRe = RegExp(
        r'<a[^>]*class="result__snippet"[^>]*>(.*?)</a>',
        caseSensitive: false,
        dotAll: true);
    /// REAL: The snippets.
    final snippets =
        snippetRe.allMatches(html).map((m) => m.group(1)!).toList();
    /// REAL: The i.
    var i = 0;
    for (final m in re.allMatches(html)) {
      if (results.length >= maxResults) break;
      /// REAL: The href.
      var href = m.group(1)!.trim();
      // DuckDuckGo wraps outbound links: //duckduckgo.com/l/?uddg=<url>
      /// REAL: The uddg.
      final uddg = RegExp(r'[?&]uddg=([^&]+)').firstMatch(href);
      if (uddg != null) {
        href = Uri.decodeComponent(uddg.group(1)!);
      } else if (href.startsWith('//')) {
        href = 'https:$href';
      }
      /// REAL: The title.
      final title = _stripTags(m.group(2)!).trim();
      /// REAL: The snippet.
      final snippet =
          i < snippets.length ? _stripTags(snippets[i]).trim() : '';
      i++;
      if (title.isEmpty || href.isEmpty) continue;
      results.add({
        'title': title,
        'url': href,
        'snippet': snippet,
        'source': 'duckduckgo',
      });
    }
    return results;
  }

  /// REAL: Query the Wikipedia search API (no key needed).
  Future<List<Map<String, dynamic>>> _searchWikipedia(
      String query, int maxResults) async {
    try {
      /// REAL: The uri.
      final uri = Uri.https('en.wikipedia.org', '/w/api.php', {
        'action': 'query',
        'list': 'search',
        'srsearch': query,
        'srlimit': '$maxResults',
        'format': 'json',
      });
      /// REAL: The resp.
      final resp = await _client
          .get(uri, headers: {'user-agent': 'NP-agent/0.1'})
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return [];
      /// REAL: The decoded.
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      /// REAL: Searches.
      final search =
          ((decoded['query'] as Map?)?['search'] as List?) ?? const [];
      return search.take(maxResults).map((item) {
        /// REAL: The m.
        final m = item as Map<String, dynamic>;
        /// REAL: The title.
        final title = '${m['title']}';
        return {
          'title': title,
          'url':
              'https://en.wikipedia.org/wiki/${Uri.encodeComponent(title.replaceAll(' ', '_'))}',
          'snippet': _stripTags('${m['snippet']}').trim(),
          'source': 'wikipedia',
        };
      }).toList();
    } catch (_) {
      return []; // offline -> graceful fallback
    }
  }

  /// REAL: Stitch top snippets into a cited summary.
  String _stitchSummary(
      String query, List<Map<String, dynamic>> results) {
    if (results.isEmpty) {
      return 'No web results for "$query" (offline or no matches).';
    }
    /// REAL: The buf.
    final buf = StringBuffer('Research summary for "$query":\n');
    for (var i = 0; i < results.length; i++) {
      /// REAL: The r.
      final r = results[i];
      buf.writeln('\n[${i + 1}] ${r['title']} (${r['source']})');
      /// REAL: The snippet.
      final snippet = '${r['snippet']}';
      if (snippet.isNotEmpty) buf.writeln('    $snippet');
      buf.writeln('    ${r['url']}');
    }
    return buf.toString();
  }

  /// REAL: Best-effort offline probe (DNS lookup with short timeout).
  Future<bool> _looksOffline() async {
    try {
      /// REAL: The addrs.
      final addrs = await InternetAddress.lookup('duckduckgo.com')
          .timeout(const Duration(seconds: 3));
      return addrs.isEmpty;
    } catch (_) {
      return true;
    }
  }

  String _stripTags(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}
