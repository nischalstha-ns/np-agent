import 'dart:convert';

import 'memory_store.dart';

/// REAL: Typed wrapper over the `skills` table: learned capabilities the agent can
/// invoke later (playbooks, API notes, prompt templates). `data` is a JSON
/// object describing how to use the skill.
class SkillMemory {
  final MemoryStore _store;

  const SkillMemory(this._store);

  Future<void> save(
    String id,
    String name,
    String description,
    Map<String, dynamic> data,
  ) =>
      _store.saveSkill(id, name, description, jsonEncode(data));

  /// REAL: Lists.
  Future<List<Map<String, dynamic>>> list() async {
    /// REAL: The rows.
    final rows = await _store.listSkills();
    return rows
        .map((r) => {
              'id': r['id'],
              'name': r['name'],
              'description': r['description'],
              'data': jsonDecode(r['data'] as String),
            })
        .toList();
  }

  /// REAL: Finds by name.
  Future<Map<String, dynamic>?> findByName(String name) async {
    /// REAL: The row.
    final row = await _store.findSkillByName(name);
    if (row == null) return null;
    return {
      'id': row['id'],
      'name': row['name'],
      'description': row['description'],
      'data': jsonDecode(row['data'] as String),
    };
  }

  /// REAL: Deletes.
  Future<int> delete(String id) => _store.deleteSkill(id);
}
