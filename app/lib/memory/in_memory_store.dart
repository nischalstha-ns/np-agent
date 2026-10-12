import 'dart:typed_data';

import 'memory_store.dart';

/// REAL: Drop-in, pure-Dart replacement for [MemoryStore] backed by Maps and
/// Lists instead of SQLite.
///
/// Implements the full [MemoryStore] public interface (same method names,
/// parameters, and row shapes: `Map<String, Object?>` rows with the same
/// column names, epoch-millisecond timestamps, autoincrement integer ids).
/// `implements` is legal here because only the public members are required.
///
/// Use it when the sqflite native plugin is unavailable (pure-Dart runs,
/// unit tests) or when persistence across restarts is not needed. Data is
/// lost when the instance is discarded — it never touches the disk.
class InMemoryMemoryStore implements MemoryStore {
  final List<Map<String, Object?>> _memoryItems = [];
  final Map<String, Map<String, Object?>> _memoryByLayerKey = {};
  final Map<String, Map<String, Object?>> _profiles = {};
  final List<Map<String, Object?>> _toolUsage = [];
  final Map<String, Map<String, Object?>> _projects = {};
  final Map<String, Map<String, Object?>> _skills = {};
  final Map<String, Map<String, Object?>> _tasks = {};
  final List<Map<String, Object?>> _taskResults = [];
  final List<Map<String, Object?>> _failures = [];
  final Map<String, Map<String, Object?>> _failureRules = {};

  int _nextId = 1;

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  int _allocId() => _nextId++;

  // ------------------------------------------------------------------ memory

  /// REAL: Insert or replace a memory item (upsert on UNIQUE(layer, key)).
  @override
  Future<int> saveMemoryItem({
    required String layer,
    required String key,
    required String content,
    Uint8List? embedding,
    double importance = 0.5,
  }) async {
    final now = _now();
    final mapKey = '$layer\x00$key';
    final existing = _memoryByLayerKey[mapKey];
    final row = <String, Object?>{
      'id': existing?['id'] ?? _allocId(),
      'layer': layer,
      'key': key,
      'content': content,
      'embedding': embedding,
      'created_at': existing?['created_at'] ?? now,
      'updated_at': now,
      'importance': importance.clamp(0.0, 1.0),
    };
    if (existing != null) {
      final idx = _memoryItems.indexWhere((r) => r['id'] == row['id']);
      if (idx >= 0) _memoryItems[idx] = row;
    } else {
      _memoryItems.add(row);
    }
    _memoryByLayerKey[mapKey] = row;
    return row['id'] as int;
  }

  /// REAL: Query memory items, optionally filtered to one layer or several.
  @override
  Future<List<Map<String, Object?>>> getMemoryItems({
    String? layer,
    List<String>? layers,
    int limit = 200,
    bool orderByRecency = false,
  }) async {
    Iterable<Map<String, Object?>> rows = _memoryItems;
    if (layer != null) {
      rows = rows.where((r) => r['layer'] == layer);
    } else if (layers != null && layers.isNotEmpty) {
      final set = layers.toSet();
      rows = rows.where((r) => set.contains(r['layer']));
    }
    final sorted = rows.toList()
      ..sort((a, b) {
        if (orderByRecency) {
          // Newest first; break same-millisecond ties by id (higher = newer).
          final cmp =
              (b['updated_at'] as int).compareTo(a['updated_at'] as int);
          if (cmp != 0) return cmp;
          return (b['id'] as int).compareTo(a['id'] as int);
        }
        final imp = (b['importance'] as double)
            .compareTo(a['importance'] as double);
        if (imp != 0) return imp;
        return (b['updated_at'] as int).compareTo(a['updated_at'] as int);
      });
    return sorted.take(limit).toList();
  }

  /// REAL: Fetch a single memory item by (layer, key).
  @override
  Future<Map<String, Object?>?> getMemoryItem(String layer, String key) async {
    return _memoryByLayerKey['$layer\x00$key'];
  }

  /// REAL: Update an item's importance (and bump updated_at).
  @override
  Future<int> updateImportance(int id, double importance) async {
    final row = _findById(_memoryItems, id);
    if (row == null) return 0;
    row['importance'] = importance.clamp(0.0, 1.0);
    row['updated_at'] = _now();
    return 1;
  }

  /// REAL: Bump an item's updated_at timestamp.
  @override
  Future<int> touchMemoryItem(int id) async {
    final row = _findById(_memoryItems, id);
    if (row == null) return 0;
    row['updated_at'] = _now();
    return 1;
  }

  /// REAL: Delete a memory item by id.
  @override
  Future<int> deleteMemoryItem(int id) async {
    final row = _findById(_memoryItems, id);
    if (row == null) return 0;
    _memoryItems.remove(row);
    _memoryByLayerKey.remove('${row['layer']}\x00${row['key']}');
    return 1;
  }

  /// REAL: Count memory items in one layer.
  @override
  Future<int> countMemoryItems(String layer) async {
    return _memoryItems.where((r) => r['layer'] == layer).length;
  }

  // ------------------------------------------------------------ user profile

  /// REAL: Read one profile value.
  @override
  Future<String?> profileGet(String key) async {
    return _profiles[key]?['value'] as String?;
  }

  /// REAL: Upsert one profile value.
  @override
  Future<void> profileSet(String key, String value) async {
    _profiles[key] = {
      'key': key,
      'value': value,
      'updated_at': _now(),
    };
  }

  /// REAL: Read the whole profile map.
  @override
  Future<Map<String, String>> profileAll() async {
    return {
      for (final e in _profiles.entries) e.key: e.value['value'] as String,
    };
  }

  // -------------------------------------------------------------- tool usage

  /// REAL: Append a tool-usage log row.
  @override
  Future<int> logToolUsage({
    required String tool,
    required String argsJson,
    String? resultSummary,
    required bool success,
    required int durationMs,
  }) async {
    final id = _allocId();
    _toolUsage.add({
      'id': id,
      'tool': tool,
      'args': argsJson,
      'result_summary': resultSummary,
      'success': success ? 1 : 0,
      'duration_ms': durationMs,
      'created_at': _now(),
    });
    return id;
  }

  /// REAL: Most recent tool-usage rows, newest first.
  @override
  Future<List<Map<String, Object?>>> recentToolUsage({int limit = 50}) async {
    final sorted = _toolUsage.toList()
      ..sort((a, b) {
        final cmp = (b['created_at'] as int)
            .compareTo(a['created_at'] as int);
        if (cmp != 0) return cmp;
        return (b['id'] as int).compareTo(a['id'] as int);
      });
    return sorted.take(limit).toList();
  }

  /// REAL: Fraction of successful calls for [tool] (1.0 when never called).
  @override
  Future<double> toolSuccessRate(String tool) async {
    final rows = _toolUsage.where((r) => r['tool'] == tool).toList();
    if (rows.isEmpty) return 1.0;
    final ok = rows.where((r) => (r['success'] as int) == 1).length;
    return ok / rows.length;
  }

  // ---------------------------------------------------------------- projects

  /// REAL: Upsert a project record.
  @override
  Future<void> saveProject(String id, String name, String dataJson) async {
    _projects[id] = {
      'id': id,
      'name': name,
      'data': dataJson,
      'updated_at': _now(),
    };
  }

  /// REAL: Fetch one project by id.
  @override
  Future<Map<String, Object?>?> getProject(String id) async {
    return _projects[id];
  }

  /// REAL: List projects, most recently updated first.
  @override
  Future<List<Map<String, Object?>>> listProjects() async {
    final rows = _projects.values.toList()
      ..sort((a, b) => (b['updated_at'] as int)
          .compareTo(a['updated_at'] as int));
    return rows;
  }

  /// REAL: Delete a project by id.
  @override
  Future<int> deleteProject(String id) async {
    return _projects.remove(id) == null ? 0 : 1;
  }

  // ------------------------------------------------------------------ skills

  /// REAL: Upsert a skill record.
  @override
  Future<void> saveSkill(
      String id, String name, String description, String dataJson) async {
    _skills[id] = {
      'id': id,
      'name': name,
      'description': description,
      'data': dataJson,
      'updated_at': _now(),
    };
  }

  /// REAL: List skills, most recently updated first.
  @override
  Future<List<Map<String, Object?>>> listSkills() async {
    final rows = _skills.values.toList()
      ..sort((a, b) => (b['updated_at'] as int)
          .compareTo(a['updated_at'] as int));
    return rows;
  }

  /// REAL: Find a skill by exact name.
  @override
  Future<Map<String, Object?>?> findSkillByName(String name) async {
    for (final row in _skills.values) {
      if (row['name'] == name) return row;
    }
    return null;
  }

  /// REAL: Delete a skill by id.
  @override
  Future<int> deleteSkill(String id) async {
    return _skills.remove(id) == null ? 0 : 1;
  }

  // ------------------------------------------------------------------- tasks

  /// REAL: Create (or replace) a task in 'running' status.
  @override
  Future<void> createTask(String id, String input) async {
    final now = _now();
    _tasks[id] = {
      'id': id,
      'input': input,
      'status': 'running',
      'created_at': now,
      'updated_at': now,
    };
  }

  /// REAL: Update a task's status.
  @override
  Future<void> updateTaskStatus(String id, String status) async {
    final row = _tasks[id];
    if (row != null) {
      row['status'] = status;
      row['updated_at'] = _now();
    }
  }

  /// REAL: Fetch one task by id.
  @override
  Future<Map<String, Object?>?> getTask(String id) async {
    return _tasks[id];
  }

  // ------------------------------------------------------------- task results

  /// REAL: Append a stage result for a task.
  @override
  Future<int> addTaskResult(
      String taskId, String stage, String outputJson) async {
    final id = _allocId();
    _taskResults.add({
      'id': id,
      'task_id': taskId,
      'stage': stage,
      'output': outputJson,
      'created_at': _now(),
    });
    return id;
  }

  /// REAL: Stage results for a task, oldest first.
  @override
  Future<List<Map<String, Object?>>> getTaskResults(String taskId) async {
    final rows =
        _taskResults.where((r) => r['task_id'] == taskId).toList()
          ..sort((a, b) {
            final cmp = (a['created_at'] as int)
                .compareTo(b['created_at'] as int);
            if (cmp != 0) return cmp;
            return (a['id'] as int).compareTo(b['id'] as int);
          });
    return rows;
  }

  // ---------------------------------------------------------------- failures

  /// REAL: Record a stage failure.
  @override
  Future<int> recordFailure(
      String taskId, String stage, String error, String? context) async {
    final id = _allocId();
    _failures.add({
      'id': id,
      'task_id': taskId,
      'stage': stage,
      'error': error,
      'context': context,
      'created_at': _now(),
    });
    return id;
  }

  /// REAL: Recent failures, newest first.
  @override
  Future<List<Map<String, Object?>>> listFailures({int limit = 50}) async {
    final sorted = _failures.toList()
      ..sort((a, b) {
        final cmp = (b['created_at'] as int)
            .compareTo(a['created_at'] as int);
        if (cmp != 0) return cmp;
        return (b['id'] as int).compareTo(a['id'] as int);
      });
    return sorted.take(limit).toList();
  }

  /// REAL: How many recorded failures start with [errorSignature].
  @override
  Future<int> countSimilarFailures(String errorSignature) async {
    return _failures
        .where((r) =>
            (r['error'] as String).startsWith(errorSignature))
        .length;
  }

  // ------------------------------------------------------------ failure rules

  /// REAL: Upsert a failure-prevention rule.
  @override
  Future<void> upsertFailureRule(
      String id, String pattern, String action) async {
    _failureRules[id] = {
      'id': id,
      'pattern': pattern,
      'action': action,
      'created_at': _now(),
    };
  }

  /// REAL: List failure rules, newest first.
  @override
  Future<List<Map<String, Object?>>> listFailureRules() async {
    final rows = _failureRules.values.toList()
      ..sort((a, b) => (b['created_at'] as int)
          .compareTo(a['created_at'] as int));
    return rows;
  }

  /// REAL: No-op — there is no database connection to release.
  @override
  Future<void> close() async {}

  Map<String, Object?>? _findById(
      List<Map<String, Object?>> rows, int id) {
    for (final row in rows) {
      if (row['id'] == id) return row;
    }
    return null;
  }
}
