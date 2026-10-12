import '../tools/tool.dart';
import '../tools/tool_registry.dart';
import 'agent.dart';
import 'planner_agent.dart';
import 'safety_agent.dart';
import 'tool_agent.dart';

/// REAL: Runs named multi-step automation routines.
///
/// A routine is an ordered list of [ToolCall]s executed sequentially through
/// the same safety gate + registry dispatch as the normal tool stage, so a
/// routine can never bypass permissions. Execution stops at the first failed
/// or blocked call; the transcript records every step.
class AutomationAgent extends Agent {
  /// REAL: The registry.
  final ToolRegistry registry;
  /// REAL: The safety.
  final SafetyAgent safety;

  /// REAL: Named routines: routine name -> ordered tool calls.
  final Map<String, List<ToolCall>> routines = {};

  AutomationAgent({required this.registry, required this.safety});

  /// REAL: The name.
  @override
  String get name => 'automation';

  @override
  String describe() =>
      'Runs named multi-step automation routines through the safety gate '
      'and tool registry, stopping at the first failure.';

  /// REAL: Registers routine.
  void registerRoutine(String name, List<ToolCall> calls) {
    routines[name] = List.unmodifiable(calls);
  }

  /// REAL: Lists routines.
  List<String> listRoutines() => List.unmodifiable(routines.keys);

  /// REAL: Execute routine [name] sequentially. Returns the per-step transcript.
  Future<List<StepExecution>> runRoutine(String name,
      {bool autoApprove = false}) async {
    /// REAL: The calls.
    final calls = routines[name];
    if (calls == null) {
      throw ArgumentError('Unknown routine "$name"');
    }
    /// REAL: The transcript.
    final transcript = <StepExecution>[];
    for (var i = 0; i < calls.length; i++) {
      /// REAL: The call.
      final call = calls[i];
      // Wrap the raw call in a synthetic plan step for uniform reporting.
      /// REAL: The step.
      final step = PlanStep(
        id: 'routine:$name:$i',
        description: 'Routine "$name" step ${i + 1}: ${call.tool}.${call.action}',
        tool: call.tool,
        action: call.action,
        args: call.args,
      );
      /// REAL: The decision.
      final decision = await safety.check(call);
      /// REAL: The may execute.
      final mayExecute =
          decision.allowed && !(decision.requiresApproval && !autoApprove);
      if (!mayExecute) {
        transcript.add(StepExecution(
          step: step,
          permission: decision,
          result: null,
          blocked: true,
        ));
        break;
      }
      /// REAL: The result.
      final result = await registry.dispatch(call);
      transcript.add(StepExecution(
        step: step,
        permission: decision,
        result: result,
        blocked: false,
      ));
      if (!result.success) break; // stop at first failure
    }
    return transcript;
  }

  /// REAL: Executes.
  @override
  Future<AgentResult> execute(TaskContext ctx) async {
    /// REAL: The started.
    final started = DateTime.now();
    try {
      /// REAL: The routine.
      final routine = ctx.metadata['routine'] as String?;
      if (routine == null || routine.isEmpty) {
        return AgentResult.ok(
          name,
          {'routines': listRoutines()},
          started,
          DateTime.now(),
        );
      }
      /// REAL: The auto approve.
      final autoApprove = ctx.metadata['autoApprove'] as bool? ?? false;
      /// REAL: The transcript.
      final transcript = await runRoutine(routine, autoApprove: autoApprove);
      return AgentResult.ok(
        name,
        {
          'routine': routine,
          'steps': transcript.length,
          'transcript': transcript.map((e) => e.toJson()).toList(),
        },
        started,
        DateTime.now(),
      );
    } catch (e) {
      return AgentResult.fail(
          name, 'Automation failed: $e', started, DateTime.now());
    }
  }
}
