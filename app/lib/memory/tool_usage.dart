import 'dart:convert';

import 'memory_store.dart';

/// REAL: Typed wrapper over the `tool_usage` table: what the agent ran, with what
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

  /// REAL: Fraction of successful runs for [tool] in recorded history (1.0 when
  /// the tool has never been used).
  Future<double> successRate(String tool) => _store.toolSuccessRate(tool);

  /// REAL: Per-tool aggregate stats: {tool, runs, failures, avgMs}.
  Future<List<Map<String, dynamic>>> stats() async {
    /// REAL: The rows.
    final rows = await _store.recentToolUsage(limit: 10000);
    /// REAL: The by tool.
    final byTool = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      /// REAL: The tool.
      final tool = (row['tool'] as String?) ?? 'unknown';
      byTool.putIfAbsent(tool, () => []).add(row);
    }
    return byTool.entries.map((e) {
      /// REAL: The runs.
      final runs = e.value.length;
      /// REAL: The failures.
      final failures = e.value.where((r) => (r['success'] as int?) == 0).length;
      /// REAL: The total ms.
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
