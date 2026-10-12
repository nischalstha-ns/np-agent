import '../memory/tool_usage.dart';
import '../tools/tool.dart';
import '../tools/tool_registry.dart';
import 'agent.dart';
import 'planner_agent.dart';
import 'safety_agent.dart';

/// REAL: A planned step paired with its tool call and safety decision.
class PlannedCall {
  /// REAL: The step.
  final PlanStep step;
  /// REAL: The call.
  final ToolCall? call; // null when step.tool == 'none'
  /// REAL: The decision.
  final SafetyDecision decision;
  /// REAL: The auto approve.
  final bool autoApprove;

  const PlannedCall({
    required this.step,
    required this.call,
    required this.decision,
    this.autoApprove = false,
  });

  /// REAL: True when this call may proceed to execution.
  bool get mayExecute =>
      call != null &&
      decision.allowed &&
      !(decision.requiresApproval && !autoApprove);

  Map<String, dynamic> toJson() => {
        'step': step.toJson(),
        'call': call?.toJson(),
        'decision': decision.toJson(),
        'mayExecute': mayExecute,
      };
}

/// REAL: The outcome of attempting one planned step.
class StepExecution {
  /// REAL: The step.
  final PlanStep step;
  /// REAL: The permission.
  final SafetyDecision permission;
  /// REAL: The result.
  final ToolResult? result;
  /// REAL: The blocked.
  final bool blocked;
  /// REAL: The skipped.
  final bool skipped; // step.tool == 'none'

  const StepExecution({
    required this.step,
    required this.permission,
    required this.result,
    required this.blocked,
    this.skipped = false,
  });

  Map<String, dynamic> toJson() => {
        'step': step.toJson(),
        'permission': permission.toJson(),
        'result': result?.toJson(),
        'blocked': blocked,
        'skipped': skipped,
      };
}

/// REAL: Selects tools for each plan step (via the safety gate) and executes them.
///
/// Selection and execution are separate so the pipeline can time, verify,
/// and learn from each phase independently.
class ToolAgent extends Agent {
  /// REAL: The registry.
  final ToolRegistry registry;
  /// REAL: The safety.
  final SafetyAgent safety;
  /// REAL: The usage.
  final ToolUsageMemory? usage;

  ToolAgent({
    required this.registry,
    required this.safety,
    this.usage,
  });

  /// REAL: The name.
  @override
  String get name => 'tools';

  @override
  String describe() =>
      'Selects tools for each plan step through the safety gate and '
      'executes the approved calls via the ToolRegistry.';

  /// REAL: Turn each plan step into a [PlannedCall], consulting the safety gate.
  /// Pure logic — also used directly by the pipeline.
  Future<List<PlannedCall>> selectTools(Plan plan,
      {bool autoApprove = false}) async {
    /// REAL: The out.
    final out = <PlannedCall>[];
    for (final step in plan.steps) {
      if (step.tool == 'none') {
        out.add(PlannedCall(
          step: step,
          call: null,
          decision: const SafetyDecision.allowed('no tool needed'),
          autoApprove: autoApprove,
        ));
        continue;
      }
      /// REAL: The call.
      final call =
          ToolCall(tool: step.tool, action: step.action, args: step.args);
      /// REAL: The decision.
      final decision = await safety.check(call);
      out.add(PlannedCall(
        step: step,
        call: call,
        decision: decision,
        autoApprove: autoApprove,
      ));
    }
    return out;
  }

  /// REAL: Execute the approved calls. Blocked/skipped steps produce a
  /// [StepExecution] without touching the registry.
  Future<List<StepExecution>> executeCalls(List<PlannedCall> calls) async {
    /// REAL: The out.
    final out = <StepExecution>[];
    for (final planned in calls) {
      if (planned.call == null) {
        out.add(StepExecution(
          step: planned.step,
          permission: planned.decision,
          result: null,
          blocked: false,
          skipped: true,
        ));
        continue;
      }
      if (!planned.mayExecute) {
        out.add(StepExecution(
          step: planned.step,
          permission: planned.decision,
          result: null,
          blocked: true,
        ));
        continue;
      }
      /// REAL: The result.
      final result = await registry.dispatch(planned.call!);
      // Record usage for the learning stage / dashboards (best effort).
      try {
        await usage?.log(
          tool: planned.call!.tool,
          args: {'action': planned.call!.action, ...planned.call!.args},
          resultSummary: _summarize(result),
          success: result.success,
          durationMs: result.durationMs,
        );
      } catch (_) {}
      out.add(StepExecution(
        step: planned.step,
        permission: planned.decision,
        result: result,
        blocked: false,
      ));
    }
    return out;
  }

  /// REAL: Convenience: select + execute in one go.
  Future<List<StepExecution>> executePlan(Plan plan,
          {bool autoApprove = false}) async =>
      executeCalls(await selectTools(plan, autoApprove: autoApprove));

  /// REAL: Executes.
  @override
  Future<AgentResult> execute(TaskContext ctx) async {
    /// REAL: The started.
    final started = DateTime.now();
    try {
      /// REAL: The plan json.
      final planJson = ctx.metadata['plan'] as Map<String, dynamic>?;
      if (planJson == null) {
        return AgentResult.fail(
            name, 'No plan in context metadata', started, DateTime.now());
      }
      /// REAL: The plan.
      final plan = Plan(
        goal: planJson['goal'] as String? ?? '',
        rationale: planJson['rationale'] as String? ?? '',
        steps: (planJson['steps'] as List? ?? const [])
            .map((s) => PlanStep.fromJson(Map<String, dynamic>.from(s as Map)))
            .toList(),
      );
      /// REAL: The auto approve.
      final autoApprove = ctx.metadata['autoApprove'] as bool? ?? false;
      /// REAL: The executions.
      final executions = await executePlan(plan, autoApprove: autoApprove);
      return AgentResult.ok(
        name,
        {
          'executions': executions.map((e) => e.toJson()).toList(),
          'executed': executions.where((e) => !e.blocked && !e.skipped).length,
          'blocked': executions.where((e) => e.blocked).length,
        },
        started,
        DateTime.now(),
      );
    } catch (e) {
      return AgentResult.fail(name, 'Tool stage failed: $e', started, DateTime.now());
    }
  }

  String _summarize(ToolResult result) {
    if (!result.success) return 'FAIL: ${result.error}';
    /// REAL: The data.
    final data = result.data;
    /// REAL: The text.
    final text = data == null ? '' : data.toString();
    return text.length > 160 ? '${text.substring(0, 160)}...' : text;
  }
}
