import 'dart:convert';

import 'memory_store.dart';

/// Typed wrapper over the `tool_usage` table: what the agent ran, with what
/// arguments, and whether it worked. Powers the learning stage and the tool
/// dashboard panel.
class ToolUsageMemory {
  final MemoryStore _store;

  const ToolUsageMemory(this._store);

  Future<int> log({
    required String tool,
    required Map<String, dynamic> args,
    String? resultSummary,
    required bool success,
    required int durationMs,
  }) =>
      _store.logToolUsage(
        tool: tool,
        argsJson: jsonEncode(args),
        resultSummary: resultSummary,
        success: success,
        durationMs: durationMs,
      );

  Future<List<Map<String, Object?>>> recent({int limit = 50}) =>
      _store.recentToolUsage(limit: limit);

  /// Fraction of successful runs for [tool] in recorded history (1.0 when
  /// the tool has never been used).
  Future<double> successRate(String tool) => _store.toolSuccessRate(tool);

  /// Per-tool aggregate stats: {tool, runs, failures, avgMs}.
  Future<List<Map<String, dynamic>>> stats() async {
    final rows = await _store.recentToolUsage(limit: 10000);
    final byTool = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      final tool = (row['tool'] as String?) ?? 'unknown';
      byTool.putIfAbsent(tool, () => []).add(row);
    }
    return byTool.entries.map((e) {
      final runs = e.value.length;
      final failures = e.value.where((r) => (r['success'] as int?) == 0).length;
      final totalMs = e.value.fold<int>(
          0, (sum, r) => sum + ((r['duration_ms'] as int?) ?? 0));
      return {
        'tool': e.key,
        'runs': runs,
        'failures': failures,
        'avgMs': runs == 0 ? 0 : totalMs ~/ runs,
      };
    }).toList();
  }
}
