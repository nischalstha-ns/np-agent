/// The six-layer Tool contract used across NP.
///
/// Every tool implements the same six layers:
///   1. [description]   — what the tool does (shown to the planner/LLM).
///   2. [inputSchema]   — JSON-schema-ish map of accepted arguments.
///   3. [outputSchema]  — JSON-schema-ish map describing the result shape.
///   4. [checkPermission] — the tool's own permission policy for a call.
///   5. [execute]       — runs the call and returns a [ToolResult].
///   6. [verify]        — post-check that the result is sane for the call.
library;

/// What a caller wants a tool to do.
class ToolCall {
  final String tool;
  final String action;
  final Map<String, dynamic> args;

  const ToolCall({
    required this.tool,
    required this.action,
    this.args = const {},
  });

  factory ToolCall.fromJson(Map<String, dynamic> json) => ToolCall(
        tool: json['tool'] as String,
        action: json['action'] as String,
        args: Map<String, dynamic>.from(json['args'] as Map? ?? const {}),
      );

  Map<String, dynamic> toJson() => {'tool': tool, 'action': action, 'args': args};

  @override
  String toString() => '$tool.$action($args)';
}

enum PermissionKind { allowed, needsApproval, denied }

/// The outcome of [Tool.checkPermission].
class PermissionDecision {
  final PermissionKind kind;
  final String reason;

  const PermissionDecision(this.kind, this.reason);

  const PermissionDecision.allowed([this.reason = 'allowed'])
      : kind = PermissionKind.allowed;

  const PermissionDecision.needsApproval([this.reason = 'requires approval'])
      : kind = PermissionKind.needsApproval;

  const PermissionDecision.denied([this.reason = 'denied'])
      : kind = PermissionKind.denied;

  bool get isAllowed => kind == PermissionKind.allowed;
  bool get needsApproval => kind == PermissionKind.needsApproval;
  bool get isDenied => kind == PermissionKind.denied;

  Map<String, dynamic> toJson() => {'kind': kind.name, 'reason': reason};

  @override
  String toString() => 'Permission(${kind.name}): $reason';
}

/// The outcome of [Tool.execute].
class ToolResult {
  final bool success;
  final dynamic data;
  final String? error;
  final int durationMs;

  const ToolResult({
    required this.success,
    this.data,
    this.error,
    this.durationMs = 0,
  });

  factory ToolResult.ok(dynamic data, {int durationMs = 0}) =>
      ToolResult(success: true, data: data, durationMs: durationMs);

  factory ToolResult.fail(String error, {int durationMs = 0}) =>
      ToolResult(success: false, error: error, durationMs: durationMs);

  Map<String, dynamic> toJson() => {
        'success': success,
        if (data != null) 'data': data,
        if (error != null) 'error': error,
        'durationMs': durationMs,
      };

  @override
  String toString() =>
      success ? 'ToolResult(ok, ${durationMs}ms)' : 'ToolResult(fail: $error)';
}

/// Six-layer tool contract. See library doc comment.
abstract class Tool {
  /// Stable machine name, e.g. 'file'.
  String get name;

  /// Layer 1: human/LLM-readable description.
  String get description;

  /// Layer 2: accepted arguments, e.g.
  /// `{'action': 'read', 'args': {'path': {'type': 'string', 'required': true}}}`.
  Map<String, dynamic> get inputSchema;

  /// Layer 3: shape of [ToolResult.data] on success.
  Map<String, dynamic> get outputSchema;

  /// Layer 4: the tool's own permission policy for [call].
  Future<PermissionDecision> checkPermission(ToolCall call);

  /// Layer 5: run the call.
  Future<ToolResult> execute(ToolCall call);

  /// Layer 6: post-execution sanity check of [result] for [call].
  /// Returns true when the result looks valid.
  Future<bool> verify(ToolCall call, ToolResult result);
}

/// Thrown by [ToolRegistry] when dispatching to an unknown tool.
class ToolNotFoundError extends StateError {
  ToolNotFoundError(String name) : super('Unknown tool "$name"');
}
