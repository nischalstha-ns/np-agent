import '../tools/tool.dart';
import '../tools/tool_registry.dart';
import 'agent.dart';
import 'planner_agent.dart';
import 'safety_agent.dart';
import 'tool_agent.dart';

/// Runs named multi-step automation routines.
///
/// A routine is an ordered list of [ToolCall]s executed sequentially through
/// the same safety gate + registry dispatch as the normal tool stage, so a
/// routine can never bypass permissions. Execution stops at the first failed
/// or blocked call; the transcript records every step.
class AutomationAgent extends Agent {
  final ToolRegistry registry;
  final SafetyAgent safety;

  /// Named routines: routine name -> ordered tool calls.
  final Map<String, List<ToolCall>> routines = {};

  AutomationAgent({required this.registry, required this.safety});

  @override
  String get name => 'automation';

  @override
  String describe() =>
      'Runs named multi-step automation routines through the safety gate '
      'and tool registry, stopping at the first failure.';

  void registerRoutine(String name, List<ToolCall> calls) {
    routines[name] = List.unmodifiable(calls);
  }

  List<String> listRoutines() => List.unmodifiable(routines.keys);

  /// Execute routine [name] sequentially. Returns the per-step transcript.
  Future<List<StepExecution>> runRoutine(String name,
      {bool autoApprove = false}) async {
    final calls = routines[name];
    if (calls == null) {
      throw ArgumentError('Unknown routine "$name"');
    }
    final transcript = <StepExecution>[];
    for (var i = 0; i < calls.length; i++) {
      final call = calls[i];
      // Wrap the raw call in a synthetic plan step for uniform reporting.
      final step = PlanStep(
        id: 'routine:$name:$i',
        description: 'Routine "$name" step ${i + 1}: ${call.tool}.${call.action}',
        tool: call.tool,
        action: call.action,
        args: call.args,
      );
      final decision = await safety.check(call);
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

  @override
  Future<AgentResult> execute(TaskContext ctx) async {
    final started = DateTime.now();
    try {
      final routine = ctx.metadata['routine'] as String?;
      if (routine == null || routine.isEmpty) {
        return AgentResult.ok(
          name,
          {'routines': listRoutines()},
          started,
          DateTime.now(),
        );
      }
      final autoApprove = ctx.metadata['autoApprove'] as bool? ?? false;
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
