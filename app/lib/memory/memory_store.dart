import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// SQLite-backed memory store (via sqflite).
///
/// Tables:
/// - `memory_items(id, layer, key, content, embedding BLOB, created_at,
///   updated_at, importance)` — UNIQUE(layer, key); layers: short_term,
///   long_term, semantic.
/// - `user_profile(key PK, value, updated_at)`
/// - `tool_usage(id, tool, args, result_summary, success, duration_ms,
///   created_at)`
/// - `projects(id PK, name, data, updated_at)`
/// - `skills(id PK, name, description, data, updated_at)`
/// - `tasks(id PK, input, status, created_at, updated_at)`
/// - `task_results(id, task_id, stage, output, created_at)`
/// - `failures(id, task_id, stage, error, context, created_at)`
/// - `failure_rules(id PK, pattern, action, created_at)`
///
/// Timestamps are epoch milliseconds (UTC).
class MemoryStore {
  final Database _db;

  MemoryStore._(this._db);

  /// Open (creating if needed) the NP database.
  static Future<MemoryStore> open({String? dbPath}) async {
    final path = dbPath ?? p.join(await getDatabasesPath(), 'np_agent.db');
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE memory_items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            layer TEXT NOT NULL,
            key TEXT NOT NULL,
            content TEXT NOT NULL,
            embedding BLOB,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            importance REAL NOT NULL DEFAULT 0.5,
            UNIQUE(layer, key)
          )''');
        await db.execute(
            'CREATE INDEX idx_memory_layer ON memory_items(layer, updated_at)');
        await db.execute('''
          CREATE TABLE user_profile(
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE tool_usage(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tool TEXT NOT NULL,
            args TEXT NOT NULL,
            result_summary TEXT,
            success INTEGER NOT NULL,
            duration_ms INTEGER NOT NULL,
            created_at INTEGER NOT NULL
          )''');
        await db.execute(
            'CREATE INDEX idx_tool_usage ON tool_usage(tool, created_at)');
        await db.execute('''
          CREATE TABLE projects(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            data TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE skills(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT NOT NULL,
            data TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE tasks(
            id TEXT PRIMARY KEY,
            input TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE task_results(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_id TEXT NOT NULL,
            stage TEXT NOT NULL,
            output TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )''');
        await db.execute(
            'CREATE INDEX idx_task_results ON task_results(task_id, stage)');
        await db.execute('''
          CREATE TABLE failures(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_id TEXT NOT NULL,
            stage TEXT NOT NULL,
            error TEXT NOT NULL,
            context TEXT,
            created_at INTEGER NOT NULL
          )''');
        await db.execute('CREATE INDEX idx_failures ON failures(error)');
        await db.execute('''
          CREATE TABLE failure_rules(
            id TEXT PRIMARY KEY,
            pattern TEXT NOT NULL,
            action TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )''');
      },
    );
    return MemoryStore._(db);
  }

  Future<void> close() => _db.close();

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  // ---------------------------------------------------------------- memory
  // items

  /// Insert or replace a memory item (upsert on UNIQUE(layer, key)).
  Future<int> saveMemoryItem({
    required String layer,
    required String key,
    required String content,
    Uint8List? embedding,
    double importance = 0.5,
  }) async {
    final now = _now();
    return _db.insert(
      'memory_items',
      {
        'layer': layer,
        'key': key,
        'content': content,
        'embedding': embedding,
        'created_at': now,
        'updated_at': now,
        'importance': importance.clamp(0.0, 1.0),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Query memory items, optionally filtered to one layer or several.
  Future<List<Map<String, Object?>>> getMemoryItems({
    String? layer,
    List<String>? layers,
    int limit = 200,
    bool orderByRecency = false,
  }) async {
    String? where;
    List<Object?>? whereArgs;
    if (layer != null) {
      where = 'layer = ?';
      whereArgs = [layer];
    } else if (layers != null && layers.isNotEmpty) {
      where = 'layer IN (${List.filled(layers.length, '?').join(',')})';
      whereArgs = layers;
    }
    return _db.query(
      'memory_items',
      where: where,
      whereArgs: whereArgs,
      orderBy: orderByRecency ? 'updated_at DESC' : 'importance DESC, updated_at DESC',
      limit: limit,
    );
  }

  Future<Map<String, Object?>?> getMemoryItem(String layer, String key) async {
    final rows = await _db.query(
      'memory_items',
      where: 'layer = ? AND key = ?',
      whereArgs: [layer, key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> updateImportance(int id, double importance) => _db.update(
        'memory_items',
        {'importance': importance.clamp(0.0, 1.0), 'updated_at': _now()},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<int> touchMemoryItem(int id) => _db.update(
        'memory_items',
        {'updated_at': _now()},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<int> deleteMemoryItem(int id) =>
      _db.delete('memory_items', where: 'id = ?', whereArgs: [id]);

  Future<int> countMemoryItems(String layer) async {
    final rows = await _db.rawQuery(
        'SELECT COUNT(*) AS c FROM memory_items WHERE layer = ?', [layer]);
    return (rows.first['c'] as int?) ?? 0;
  }

  // ------------------------------------------------------------ user profile

  Future<String?> profileGet(String key) async {
    final rows = await _db.query('user_profile',
        where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> profileSet(String key, String value) async {
    await _db.insert(
      'user_profile',
      {'key': key, 'value': value, 'updated_at': _now()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, String>> profileAll() async {
    final rows = await _db.query('user_profile');
    return {
      for (final r in rows) (r['key'] as String): (r['value'] as String)
    };
  }

  // -------------------------------------------------------------- tool usage

  Future<int> logToolUsage({
    required String tool,
    required String argsJson,
    String? resultSummary,
    required bool success,
    required int durationMs,
  }) =>
      _db.insert('tool_usage', {
        'tool': tool,
        'args': argsJson,
        'result_summary': resultSummary,
        'success': success ? 1 : 0,
        'duration_ms': durationMs,
        'created_at': _now(),
      });

  Future<List<Map<String, Object?>>> recentToolUsage({int limit = 50}) =>
      _db.query('tool_usage', orderBy: 'created_at DESC', limit: limit);

  Future<double> toolSuccessRate(String tool) async {
    final rows = await _db.rawQuery(
        'SELECT COUNT(*) AS total, SUM(success) AS ok FROM tool_usage WHERE tool = ?',
        [tool]);
    final total = (rows.first['total'] as int?) ?? 0;
    if (total == 0) return 1.0;
    final ok = (rows.first['ok'] as int?) ?? 0;
    return ok / total;
  }

  // ---------------------------------------------------------------- projects

  Future<void> saveProject(String id, String name, String dataJson) async {
    await _db.insert(
      'projects',
      {'id': id, 'name': name, 'data': dataJson, 'updated_at': _now()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, Object?>?> getProject(String id) async {
    final rows =
        await _db.query('projects', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> listProjects() =>
      _db.query('projects', orderBy: 'updated_at DESC');

  Future<int> deleteProject(String id) =>
      _db.delete('projects', where: 'id = ?', whereArgs: [id]);

  // ------------------------------------------------------------------ skills

  Future<void> saveSkill(
      String id, String name, String description, String dataJson) async {
    await _db.insert(
      'skills',
      {
        'id': id,
        'name': name,
        'description': description,
        'data': dataJson,
        'updated_at': _now(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, Object?>>> listSkills() =>
      _db.query('skills', orderBy: 'updated_at DESC');

  Future<Map<String, Object?>?> findSkillByName(String name) async {
    final rows = await _db.query('skills',
        where: 'name = ?', whereArgs: [name], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> deleteSkill(String id) =>
      _db.delete('skills', where: 'id = ?', whereArgs: [id]);

  // ------------------------------------------------------------------- tasks

  Future<void> createTask(String id, String input) async {
    final now = _now();
    await _db.insert(
      'tasks',
      {
        'id': id,
        'input': input,
        'status': 'running',
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateTaskStatus(String id, String status) async {
    await _db.update(
      'tasks',
      {'status': status, 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, Object?>?> getTask(String id) async {
    final rows =
        await _db.query('tasks', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  // ------------------------------------------------------------- task results

  Future<int> addTaskResult(
      String taskId, String stage, String outputJson) async {
    return _db.insert('task_results', {
      'task_id': taskId,
      'stage': stage,
      'output': outputJson,
      'created_at': _now(),
    });
  }

  Future<List<Map<String, Object?>>> getTaskResults(String taskId) =>
      _db.query('task_results',
          where: 'task_id = ?',
          whereArgs: [taskId],
          orderBy: 'created_at ASC');

  // ---------------------------------------------------------------- failures

  Future<int> recordFailure(
      String taskId, String stage, String error, String? context) async {
    return _db.insert('failures', {
      'task_id': taskId,
      'stage': stage,
      'error': error,
      'context': context,
      'created_at': _now(),
    });
  }

  Future<List<Map<String, Object?>>> listFailures({int limit = 50}) =>
      _db.query('failures', orderBy: 'created_at DESC', limit: limit);

  /// How many recorded failures start with [errorSignature].
  Future<int> countSimilarFailures(String errorSignature) async {
    final rows = await _db.rawQuery(
        'SELECT COUNT(*) AS c FROM failures WHERE error LIKE ?',
        ['$errorSignature%']);
    return (rows.first['c'] as int?) ?? 0;
  }

  // ------------------------------------------------------------ failure rules

  Future<void> upsertFailureRule(
      String id, String pattern, String action) async {
    await _db.insert(
      'failure_rules',
      {
        'id': id,
        'pattern': pattern,
        'action': action,
        'created_at': _now(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, Object?>>> listFailureRules() =>
      _db.query('failure_rules', orderBy: 'created_at DESC');
}
