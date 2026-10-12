import 'agent.dart';
import 'planner_agent.dart';

/// Refines a raw [Plan]: dependency ordering, deduplication, and per-step
/// rationale.
///
/// Real logic:
/// - topological sort honoring [PlanStep.dependsOn] (stable for independent
///   steps; cycles are broken deterministically with a reported note),
/// - drops exact duplicate steps (same tool/action/args),
/// - annotates each step with a one-line rationale in `metadata`-style
///   output so later stages can explain themselves.
class ReasoningAgent extends Agent {
  @override
  String get name => 'reasoning';

  @override
  String describe() =>
      'Refines the plan: orders steps by dependencies, removes duplicates, '
      'and attaches per-step rationale.';

  @override
  Future<AgentResult> execute(TaskContext ctx) async {
    final started = DateTime.now();
    try {
      final planJson = ctx.metadata['plan'] as Map<String, dynamic>?;
      if (planJson == null) {
        return AgentResult.fail(
            name, 'No plan in context metadata', started, DateTime.now());
      }
      final plan = _planFromJson(planJson);
      final refined = refine(plan);
      return AgentResult.ok(
        name,
        {
          'plan': refined.toJson(),
          'stepCount': refined.steps.length,
          'notes': refined.rationale,
        },
        started,
        DateTime.now(),
      );
    } catch (e) {
      return AgentResult.fail(name, 'Reasoning failed: $e', started, DateTime.now());
    }
  }

  /// Pure refinement logic — also used directly by the pipeline.
  Plan refine(Plan plan) {
    final notes = <String>[];

    // 1. Deduplicate exact repeats (same tool/action/args), keep first.
    final seen = <String>{};
    final deduped = <PlanStep>[];
    for (final step in plan.steps) {
      final key = '${step.tool}|${step.action}|${_argsKey(step.args)}';
      if (seen.add(key)) {
        deduped.add(step);
      } else {
        notes.add('Dropped duplicate step ${step.id} (${step.tool}.${step.action})');
      }
    }

    // 2. Topological order honoring dependsOn (Kahn's algorithm, stable).
    final ordered = _topoSort(deduped, notes);

    // 3. Attach rationale: describe why each step exists and its position.
    final annotated = <PlanStep>[];
    for (var i = 0; i < ordered.length; i++) {
      final s = ordered[i];
      final rationale = s.tool == 'none'
          ? 'No tool needed; answer from model knowledge.'
          : 'Step ${i + 1}/${ordered.length}: ${s.tool}.${s.action} '
              '${s.dependsOn.isEmpty ? '(independent)' : '(after ${s.dependsOn.join(', ')})'}';
      annotated.add(PlanStep(
        id: s.id,
        description: '${s.description} [$rationale]',
        tool: s.tool,
        action: s.action,
        args: s.args,
        dependsOn: s.dependsOn,
      ));
    }

    return Plan(
      goal: plan.goal,
      steps: annotated,
      rationale: [
        'Refined ${plan.steps.length} planned step(s) into ${annotated.length}.',
        ...notes,
      ].join(' '),
    );
  }

  String _argsKey(Map<String, dynamic> args) {
    final keys = args.keys.toList()..sort();
    return keys.map((k) => '$k=${args[k]}').join('&');
  }

  List<PlanStep> _topoSort(List<PlanStep> steps, List<String> notes) {
    final byId = {for (final s in steps) s.id: s};
    final indegree = <String, int>{};
    final outgoing = <String, List<String>>{};
    for (final s in steps) {
      indegree[s.id] = 0;
      outgoing[s.id] = [];
    }
    for (final s in steps) {
      for (final dep in s.dependsOn) {
        if (!byId.containsKey(dep)) {
          notes.add('Step ${s.id} depends on unknown step $dep; ignoring.');
          continue;
        }
        outgoing[dep]!.add(s.id);
        indegree[s.id] = (indegree[s.id] ?? 0) + 1;
      }
    }
    // Stable: always pick the earliest-planned available step.
    final order = {for (var i = 0; i < steps.length; i++) steps[i].id: i};
    final ready = steps
        .where((s) => indegree[s.id] == 0)
        .map((s) => s.id)
        .toList()
      ..sort((a, b) => order[a]!.compareTo(order[b]!));
    final result = <PlanStep>[];
    while (ready.isNotEmpty) {
      final id = ready.removeAt(0);
      result.add(byId[id]!);
      for (final next in outgoing[id]!) {
        indegree[next] = indegree[next]! - 1;
        if (indegree[next] == 0) {
          ready.add(next);
          ready.sort((a, b) => order[a]!.compareTo(order[b]!));
        }
      }
    }
    if (result.length < steps.length) {
      // Cycle: append the leftovers in original order, deterministically.
      final missing = steps.where((s) => !result.contains(s)).toList();
      notes.add(
          'Dependency cycle detected among ${missing.map((s) => s.id).join(', ')}; '
          'appended in plan order.');
      result.addAll(missing);
    }
    return result;
  }

  Plan _planFromJson(Map<String, dynamic> json) => Plan(
        goal: json['goal'] as String? ?? '',
        rationale: json['rationale'] as String? ?? '',
        steps: (json['steps'] as List? ?? const [])
            .map((s) => PlanStep.fromJson(Map<String, dynamic>.from(s as Map)))
            .toList(),
      );
}
