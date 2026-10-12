import '../tools/tool.dart';
import '../tools/tool_registry.dart';
import 'agent.dart';

/// Outcome of the safety gate.
class SafetyDecision {
  final bool allowed;
  final bool requiresApproval;
  final String reason;

  const SafetyDecision({
    required this.allowed,
    required this.requiresApproval,
    required this.reason,
  });

  const SafetyDecision.allowed([this.reason = 'allowed by policy'])
      : allowed = true,
        requiresApproval = false;

  const SafetyDecision.needsApproval([this.reason = 'requires approval'])
      : allowed = true,
        requiresApproval = true;

  const SafetyDecision.denied([this.reason = 'denied by policy'])
      : allowed = false,
        requiresApproval = false;

  Map<String, dynamic> toJson() => {
        'allowed': allowed,
        'requiresApproval': requiresApproval,
        'reason': reason,
      };

  @override
  String toString() =>
      'Safety(allowed=$allowed, approval=$requiresApproval): $reason';
}

extension PermissionDecisionX on PermissionDecision {
  SafetyDecision toSafetyDecision() {
    switch (kind) {
      case PermissionKind.allowed:
        return SafetyDecision.allowed(reason);
      case PermissionKind.needsApproval:
        return SafetyDecision.needsApproval(reason);
      case PermissionKind.denied:
        return SafetyDecision.denied(reason);
    }
  }
}

/// Permission gate consulted by the [ToolAgent] before every tool execution.
///
/// Layered policy:
/// 1. Unknown tool -> denied.
/// 2. Global denylist (automation routines marked dangerous, raw `none`
///    pseudo-tool is always fine).
/// 3. Otherwise delegate to the tool's own [Tool.checkPermission].
class SafetyAgent extends Agent {
  final ToolRegistry registry;

  /// Tool names that always require explicit user approval regardless of
  /// what the tool itself says.
  static const Set<String> alwaysApprove = {'automation'};

  /// Tool names that are hard-denied at the gate.
  static const Set<String> hardDenied = {};

  SafetyAgent(this.registry);

  @override
  String get name => 'safety';

  @override
  String describe() =>
      'Permission gate: approves, escalates, or denies every tool call '
      'before it executes.';

  /// The actual gate used by the pipeline (not just the Agent interface).
  Future<SafetyDecision> check(ToolCall call) async {
    if (call.tool == 'none') {
      return const SafetyDecision.allowed('no tool invocation');
    }
    final tool = registry.getOrNull(call.tool);
    if (tool == null) {
      return SafetyDecision.denied('Unknown tool "${call.tool}"');
    }
    if (hardDenied.contains(call.tool)) {
      return SafetyDecision.denied('Tool "${call.tool}" is disabled by policy');
    }
    final decision = await tool.checkPermission(call);
    if (decision.isDenied) return decision.toSafetyDecision();
    if (alwaysApprove.contains(call.tool)) {
      return SafetyDecision.needsApproval(
          'Tool "${call.tool}" always requires approval by policy');
    }
    return decision.toSafetyDecision();
  }

  @override
  Future<AgentResult> execute(TaskContext ctx) async {
    final started = DateTime.now();
    final callJson = ctx.metadata['toolCall'] as Map<String, dynamic>?;
    if (callJson == null) {
      return AgentResult.ok(
        name,
        {
          'policy': 'gate',
          'alwaysApprove': alwaysApprove.toList(),
          'hardDenied': hardDenied.toList(),
          'note': 'Pass {"toolCall": {...}} in metadata to evaluate one call.',
        },
        started,
        DateTime.now(),
      );
    }
    final decision = await check(ToolCall.fromJson(callJson));
    return AgentResult.ok(
        name, {'decision': decision.toJson()}, started, DateTime.now());
  }
}
