import 'dart:convert';

import '../memory/memory_store.dart';
import 'agent.dart';
import 'planner_agent.dart';
import 'tool_agent.dart';
import 'verification_agent.dart';

/// Learning stage of the pipeline.
///
/// Real logic:
/// - persists every run's stage outputs into `task_results`,
/// - records stage failures into `failures` (also called directly by the
///   pipeline's error path),
/// - promotes a repeated failure signature (>= 3 similar failures) into a
///   `failure_rules` entry so future runs can warn before repeating it.
class LearningAgent extends Agent {
  final MemoryStore store;

  /// How many similar failures trigger a learned rule.
  final int ruleThreshold;

  LearningAgent({required this.store, this.ruleThreshold = 3});

  @override
  String get name => 'learning';

  @override
  String describe() =>
      'Writes task results and failure records to memory, and promotes '
      'repeated failures into learned failure rules.';

  /// Record one stage's output for [taskId].
  Future<void> recordTaskResult(
      String taskId, String stage, Map<String, dynamic> output) {
    return store.addTaskResult(taskId, stage, jsonEncode(output));
  }

  /// Record a failure; promote to a failure rule when the same signature
  /// has been seen [ruleThreshold] times or more.
  Future<void> recordFailure(
    String taskId,
    String stage,
    String error,
    String? context,
  ) async {
    await store.recordFailure(taskId, stage, error, context);
    final signature = _signature(error);
    final count = await store.countSimilarFailures(signature);
    if (count >= ruleThreshold) {
      await store.upsertFailureRule(
        'rule_${signature.hashCode.toUnsigned(32)}',
        signature,
        'warn: this failure has occurred $count times — '
        'revise the plan before retrying the same approach',
      );
    }
  }

  /// Full learning pass after a pipeline run. Returns a short lesson string
  /// that the response stage can quote.
  Future<String> learnFromRun({
    required String taskId,
    required Plan plan,
    required List<StepExecution> executions,
    required VerificationReport verification,
  }) async {
    await recordTaskResult(taskId, 'plan', plan.toJson());
    await recordTaskResult(taskId, 'executions', {
      'executions': executions.map((e) => e.toJson()).toList(),
    });
    await recordTaskResult(taskId, 'verification', verification.toJson());

    // Each failed execution becomes a failure record (feeds rule promotion).
    for (final e in executions) {
      if (e.blocked) {
        await recordFailure(taskId, 'execution',
            'Blocked ${e.step.tool}.${e.step.action}: ${e.permission.reason}', e.step.description);
      } else if (e.result != null && !e.result!.success) {
        await recordFailure(taskId, 'execution',
            '${e.step.tool}.${e.step.action}: ${e.result!.error}', e.step.description);
      }
    }
    for (final issue in verification.issues) {
      await recordFailure(taskId, 'verification', issue, null);
    }

    final rules = await store.listFailureRules();
    final lesson = verification.passed
        ? 'Run succeeded: ${verification.succeeded}/${verification.total} steps verified.'
        : 'Run partially failed: ${verification.succeeded}/${verification.total} steps verified. '
            'Issues: ${verification.issues.join('; ')}';
    return rules.isEmpty
        ? lesson
        : '$lesson Learned rules on file: ${rules.length}.';
  }

  /// Short stable signature used to group similar failures.
  String _signature(String error) {
    final singleLine = error.replaceAll(RegExp(r'\s+'), ' ').trim();
    return singleLine.length > 120
        ? singleLine.substring(0, 120)
        : singleLine;
  }

  @override
  Future<AgentResult> execute(TaskContext ctx) async {
    final started = DateTime.now();
    try {
      final taskId = ctx.taskId;
      final stage = ctx.metadata['stage'] as String? ?? 'adhoc';
      final output =
          Map<String, dynamic>.from(ctx.metadata['output'] as Map? ?? {});
      await recordTaskResult(taskId, stage, output);
      return AgentResult.ok(
          name, {'recorded': true, 'stage': stage}, started, DateTime.now());
    } catch (e) {
      return AgentResult.fail(name, 'Learning failed: $e', started, DateTime.now());
    }
  }
}
