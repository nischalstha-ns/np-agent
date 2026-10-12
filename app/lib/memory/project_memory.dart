import 'dart:convert';

import 'memory_store.dart';

/// REAL: Typed wrapper over the `projects` table: per-project working memory
/// (goals, stack, open threads, decisions). `data` is a JSON object.
class ProjectMemory {
  final MemoryStore _store;

  const ProjectMemory(this._store);

  Future<void> save(String id, String name, Map<String, dynamic> data) =>
      _store.saveProject(id, name, jsonEncode(data));

  /// REAL: Returns.
  Future<Map<String, dynamic>?> get(String id) async {
    /// REAL: The row.
    final row = await _store.getProject(id);
    if (row == null) return null;
    return {
      'id': row['id'],
      'name': row['name'],
      'data': jsonDecode(row['data'] as String) as Map<String, dynamic>,
    };
  }

  /// REAL: Lists.
  Future<List<Map<String, dynamic>>> list() async {
    /// REAL: The rows.
    final rows = await _store.listProjects();
    return rows
        .map((r) => {
              'id': r['id'],
              'name': r['name'],
              'data': jsonDecode(r['data'] as String),
            })
        .toList();
  }

  /// REAL: Merge [patch] into the stored data object (shallow merge).
  Future<void> update(String id, Map<String, dynamic> patch) async {
    /// REAL: The existing.
    final existing = await get(id);
    /// REAL: The name.
    final name = (existing?['name'] as String?) ?? id;
    /// REAL: The data.
    final data = Map<String, dynamic>.from(
        (existing?['data'] as Map?)?.cast<String, dynamic>() ?? {});
    data.addAll(patch);
    await save(id, name, data);
  }

  /// REAL: Deletes.
  Future<int> delete(String id) => _store.deleteProject(id);
}
