import '../tools/tool.dart';
import 'agent.dart';
import 'planner_agent.dart';
import 'safety_agent.dart';
import 'tool_agent.dart';

/// Outcome of verifying a plan's executions.
class VerificationReport {
  final bool passed;
  final List<String> issues;
  final Map<String, bool> stepResults;

  const VerificationReport({
    required this.passed,
    required this.issues,
    required this.stepResults,
  });

  int get succeeded => stepResults.values.where((v) => v).length;
  int get total => stepResults.length;

  Map<String, dynamic> toJson() => {
        'passed': passed,
        'issues': issues,
        'stepResults': stepResults,
        'succeeded': succeeded,
        'total': total,
      };
}

/// Checks execution output against the plan.
///
/// Real logic per step:
/// - skipped (`tool: none`) steps trivially pass,
/// - blocked steps fail with the safety reason,
/// - failed tool results fail with the tool error,
/// - steps whose args carry `expectContains` additionally require that
///   substring to appear in the stringified tool output.
class VerificationAgent extends Agent {
  @override
  String get name => 'verification';

  @override
  String describe() =>
      'Verifies each executed step against the plan: success flags, '
      'safety blocks, and optional expected-output matching.';

  /// Pure verification logic — also used directly by the pipeline.
  VerificationReport verifyPlan(Plan plan, List<StepExecution> executions) {
    final issues = <String>[];
    final stepResults = <String, bool>{};

    for (final e in executions) {
      if (e.skipped) {
        stepResults[e.step.id] = true;
        continue;
      }
      if (e.blocked) {
        issues.add('Step ${e.step.id} (${e.step.description}) was blocked: '
            '${e.permission.reason}');
        stepResults[e.step.id] = false;
        continue;
      }
      final result = e.result;
      if (result == null || !result.success) {
        issues.add('Step ${e.step.id} (${e.step.description}) failed: '
            '${result?.error ?? 'no result'}');
        stepResults[e.step.id] = false;
        continue;
      }
      final expect = e.step.args['expectContains'];
      if (expect is String && expect.isNotEmpty) {
        final haystack = '${result.data}';
        if (!haystack.contains(expect)) {
          issues.add('Step ${e.step.id}: output did not contain '
              'expected "$expect"');
          stepResults[e.step.id] = false;
          continue;
        }
      }
      stepResults[e.step.id] = true;
    }

    // Steps in the plan with no execution record at all.
    for (final step in plan.steps) {
      if (!stepResults.containsKey(step.id)) {
        issues.add('Step ${step.id} (${step.description}) was never executed');
        stepResults[step.id] = false;
      }
    }

    return VerificationReport(
      passed: issues.isEmpty,
      issues: issues,
      stepResults: stepResults,
    );
  }

  @override
  Future<AgentResult> execute(TaskContext ctx) async {
    final started = DateTime.now();
    try {
      final report = _reportFromMetadata(ctx.metadata);
      if (report == null) {
        return AgentResult.fail(name,
            'No plan/executions in context metadata', started, DateTime.now());
      }
      return AgentResult.ok(
          name, {'report': report.toJson()}, started, DateTime.now());
    } catch (e) {
      return AgentResult.fail(
          name, 'Verification failed: $e', started, DateTime.now());
    }
  }

  /// Rebuild a report from serialized plan + executions (Agent interface path).
  /// The pipeline itself always calls [verifyPlan] with live objects.
  VerificationReport? _reportFromMetadata(Map<String, dynamic> metadata) {
    final planJson = metadata['plan'] as Map<String, dynamic>?;
    final execJson = metadata['executions'] as List?;
    if (planJson == null || execJson == null) return null;

    final plan = Plan(
      goal: planJson['goal'] as String? ?? '',
      rationale: planJson['rationale'] as String? ?? '',
      steps: (planJson['steps'] as List? ?? const [])
          .map((s) => PlanStep.fromJson(Map<String, dynamic>.from(s as Map)))
          .toList(),
    );

    final executions = <StepExecution>[];
    for (final raw in execJson) {
      final m = Map<String, dynamic>.from(raw as Map);
      final step =
          PlanStep.fromJson(Map<String, dynamic>.from(m['step'] as Map));
      final perm = Map<String, dynamic>.from(m['permission'] as Map? ?? {});
      final resJson = m['result'] as Map?;
      ToolResult? result;
      if (resJson != null) {
        result = (resJson['success'] as bool? ?? false)
            ? ToolResult.ok(resJson['data'],
                durationMs: (resJson['durationMs'] as int?) ?? 0)
            : ToolResult.fail(
                resJson['error']?.toString() ?? 'failed',
                durationMs: (resJson['durationMs'] as int?) ?? 0,
              );
      }
      executions.add(StepExecution(
        step: step,
        permission: SafetyDecision(
          allowed: perm['allowed'] as bool? ?? false,
          requiresApproval: perm['requiresApproval'] as bool? ?? false,
          reason: perm['reason'] as String? ?? '',
        ),
        result: result,
        blocked: m['blocked'] as bool? ?? false,
        skipped: m['skipped'] as bool? ?? false,
      ));
    }
    return verifyPlan(plan, executions);
  }
}
