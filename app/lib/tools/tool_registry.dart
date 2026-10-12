import 'tool.dart';

/// REAL: Central registry for all tools: registration, lookup, and
/// permission-checked dispatch.
///
/// Dispatch flow: resolve tool -> [Tool.checkPermission] -> (deny/approval
/// gate) -> [Tool.execute] with timing -> [Tool.verify] -> [ToolResult].
/// Every step is captured; unexpected exceptions become failed [ToolResult]s
/// rather than escaping.
class ToolRegistry {
  final Map<String, Tool> _tools = {};

  /// REAL: Register (or replace) a tool by its [Tool.name].
  void register(Tool tool) {
    _tools[tool.name] = tool;
  }

  /// REAL: Look up a tool. Throws [ToolNotFoundError] when missing.
  Tool get(String name) {
    /// REAL: The tool.
    final tool = _tools[name];
    if (tool == null) throw ToolNotFoundError(name);
    return tool;
  }

  /// REAL: Look up a tool, returning null when missing.
  Tool? getOrNull(String name) => _tools[name];

  /// REAL: The contains.
  bool contains(String name) => _tools.containsKey(name);

  /// REAL: Lists.
  List<Tool> list() => List.unmodifiable(_tools.values);

  /// REAL: The names.
  List<String> names() => List.unmodifiable(_tools.keys);

  /// REAL: Dispatch [call] through the permission gate, execution, and verification.
  ///
  /// [permissionOverride] may upgrade a `needsApproval` decision to allowed
  /// (used when the user pre-approved, or for tests). It is never consulted
  /// for `denied` decisions.
  Future<ToolResult> dispatch(
    ToolCall call, {
    Future<PermissionDecision> Function(ToolCall call)? permissionOverride,
  }) async {
    /// REAL: The sw.
    final sw = Stopwatch()..start();
    /// REAL: The fail.
    ToolResult fail(String error) {
      sw.stop();
      return ToolResult.fail(error, durationMs: sw.elapsedMilliseconds);
    }

    /// REAL: The tool.
    final tool = getOrNull(call.tool);
    if (tool == null) return fail('Unknown tool "${call.tool}"');

    // --- Layer 4: permission gate -----------------------------------------
    /// REAL: The decision.
    PermissionDecision decision;
    try {
      decision = await tool.checkPermission(call);
    } catch (e) {
      return fail('Permission check crashed for ${call.tool}: $e');
    }
    if (decision.isDenied) {
      return fail('Permission denied for $call: ${decision.reason}');
    }
    if (decision.needsApproval) {
      if (permissionOverride == null) {
        return fail('Approval required for $call: ${decision.reason}');
      }
      /// REAL: The override.
      final override = await permissionOverride(call);
      if (override.isDenied || override.needsApproval) {
        return fail(
            'Approval not granted for $call: ${override.reason}');
      }
    }

    // --- Layer 5: execution -------------------------------------------------
    /// REAL: The result.
    ToolResult result;
    try {
      result = await tool.execute(call);
    } catch (e) {
      return fail('Tool ${call.tool} threw: $e');
    }
    sw.stop();
    result = ToolResult(
      success: result.success,
      data: result.data,
      error: result.error,
      durationMs: sw.elapsedMilliseconds,
    );

    // --- Layer 6: verification --------------------------------------------
    if (result.success) {
      try {
        /// REAL: The valid.
        final valid = await tool.verify(call, result);
        if (!valid) {
          return ToolResult.fail(
            'Verification failed for $call: result did not match output schema',
            durationMs: result.durationMs,
          );
        }
      } catch (e) {
        return ToolResult.fail(
          'Verification crashed for $call: $e',
          durationMs: result.durationMs,
        );
      }
    }
    return result;
  }
}
