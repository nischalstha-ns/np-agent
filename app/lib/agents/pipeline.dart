import '../memory/memory_store.dart';
import '../memory/retrieval.dart';
import 'agent.dart';
import 'learning_agent.dart';
import 'memory_agent.dart';
import 'planner_agent.dart';
import 'reasoning_agent.dart';
import 'tool_agent.dart';
import 'verification_agent.dart';

/// REAL: The pipeline stages, in execution order:
///
/// Input -> planner -> reasoning -> memory retrieval -> tool selection ->
/// execution -> verification -> learning -> Response.
enum PipelineStage {
  input,
  planning,
  reasoning,
  memory,
  toolSelection,
  execution,
  verification,
  learning,
  response,
}

/// REAL: Timing + outcome report for one stage.
class StageReport {
  /// REAL: Runs.
  final PipelineStage stage;
  /// REAL: The duration ms.
  final int durationMs;
  /// REAL: The success.
  final bool success;
  /// REAL: The detail.
  final String detail;

  const StageReport({
    required this.stage,
    required this.durationMs,
    required this.success,
    required this.detail,
  });

  Map<String, dynamic> toJson() => {
        'stage': stage.name,
        'durationMs': durationMs,
        'success': success,
        'detail': detail,
      };
}

/// REAL: The full outcome of one pipeline run.
class PipelineResult {
  /// REAL: The task id.
  final String taskId;
  /// REAL: The input.
  final String input;
  /// REAL: The response.
  final String response;
  /// REAL: The stages.
  final List<StageReport> stages;
  /// REAL: The success.
  final bool success;
  /// REAL: The error.
  final String? error;
  /// REAL: The total ms.
  final int totalMs;

  const PipelineResult({
    required this.taskId,
    required this.input,
    required this.response,
    required this.stages,
    required this.success,
    this.error,
    required this.totalMs,
  });

  /// REAL: The report for.
  StageReport? reportFor(PipelineStage stage) {
    for (final r in stages) {
      if (r.stage == stage) return r;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'input': input,
        'response': response,
        'success': success,
        if (error != null) 'error': error,
        'totalMs': totalMs,
        'stages': stages.map((s) => s.toJson()).toList(),
      };
}

/// REAL: The orchestrator: runs Input -> planner -> reasoning -> memory ->
/// tool selection -> execution -> verification -> learning -> Response.
///
/// Every stage is timed; any stage throwing is captured into a [StageReport],
/// persisted as a failure record via [LearningAgent], and aborts the run with
/// a user-facing error response (the failure is never swallowed silently).
class Pipeline {
  /// REAL: Stores.
  final MemoryStore store;
  /// REAL: The planner.
  final PlannerAgent planner;
  /// REAL: The reasoning.
  final ReasoningAgent reasoning;
  /// REAL: The memory.
  final MemoryAgent memory;
  /// REAL: The tools.
  final ToolAgent tools;
  /// REAL: The verification.
  final VerificationAgent verification;
  /// REAL: The learning.
  final LearningAgent learning;

  /// REAL: When true, `needsApproval` safety decisions are auto-approved
  /// (useful for tests / trusted local runs; default false).
  final bool autoApprove;

  const Pipeline({
    required this.store,
    required this.planner,
    required this.reasoning,
    required this.memory,
    required this.tools,
    required this.verification,
    required this.learning,
    this.autoApprove = false,
  });

  /// REAL: Run one user input through the full stage chain.
  Future<PipelineResult> run(String input, {String sessionId = 'default'}) async {
    /// REAL: The task id.
    final taskId = 'task_${DateTime.now().millisecondsSinceEpoch}';
    /// REAL: The started all.
    final startedAll = DateTime.now();
    /// REAL: The reports.
    final reports = <StageReport>[];
    await store.createTask(taskId, input);

    PipelineResult finish({
      required String response,
      required bool success,
      String? error,
    }) {
      /// REAL: The total ms.
      final totalMs = DateTime.now().difference(startedAll).inMilliseconds;
      return PipelineResult(
        taskId: taskId,
        input: input,
        response: response,
        stages: List.unmodifiable(reports),
        success: success,
        error: error,
        totalMs: totalMs,
      );
    }

    /// REAL: Run one stage with timing + failure capture.
    Future<T> stage<T>(
      PipelineStage s,
      Future<T> Function() fn, {
      String Function(T value)? describe,
    }) async {
      /// REAL: The sw.
      final sw = Stopwatch()..start();
      try {
        /// REAL: The value.
        final value = await fn();
        sw.stop();
        reports.add(StageReport(
          stage: s,
          durationMs: sw.elapsedMilliseconds,
          success: true,
          detail: describe == null ? 'ok' : describe(value),
        ));
        return value;
      } catch (e, st) {
        sw.stop();
        reports.add(StageReport(
          stage: s,
          durationMs: sw.elapsedMilliseconds,
          success: false,
          detail: e.toString(),
        ));
        // Failure records are written even when the run aborts.
        try {
          await learning.recordFailure(
              taskId, s.name, e.toString(), st.toString());
        } catch (_) {
          // Recording must never mask the original failure.
        }
        rethrow;
      }
    }

    try {
      // --- 1. Input -------------------------------------------------------
      /// REAL: The clean input.
      final cleanInput = await stage<String>(PipelineStage.input, () async {
        /// REAL: The trimmed.
        final trimmed = input.trim();
        if (trimmed.isEmpty) throw ArgumentError('Empty input');
        if (trimmed.length > 8000) {
          throw ArgumentError('Input too long (${trimmed.length} chars)');
        }
        return trimmed;
      }, describe: (v) => '${v.length} chars');

      /// REAL: The ctx.
      final ctx = TaskContext(
          taskId: taskId, input: cleanInput, sessionId: sessionId);

      // --- 2. Planner ------------------------------------------------------
      /// REAL: The plan.
      final plan = await stage<Plan>(
        PipelineStage.planning,
        () async => planner.producePlan(cleanInput),
        describe: (p) => '${p.steps.length} step(s)',
      );

      // --- 3. Reasoning (refine) -------------------------------------------
      /// REAL: The refined.
      final refined = await stage<Plan>(
        PipelineStage.reasoning,
        () async => reasoning.refine(plan),
        describe: (p) => '${p.steps.length} step(s) after refine',
      );

      // --- 4. Memory retrieval ---------------------------------------------
      /// REAL: The memories.
      final memories = await stage<List<ScoredMemory>>(
        PipelineStage.memory,
        () async {
          // Record this turn as working context (mirrors MemoryAgent.execute;
          // best effort — a write failure must never break the run).
          try {
            await memory.shortTerm
                .save('turn_$taskId', cleanInput, importance: 0.4);
          } catch (_) {}
          return memory.recall(ctx);
        },
        describe: (m) => '${m.length} memor(ies)',
      );

      // --- 5. Tool selection (safety-gated) ---------------------------------
      /// REAL: The calls.
      final calls = await stage<List<PlannedCall>>(
        PipelineStage.toolSelection,
        () => tools.selectTools(refined, autoApprove: autoApprove),
        describe: (c) =>
            '${c.where((x) => x.mayExecute).length}/${c.length} approved',
      );

      // --- 6. Execution ------------------------------------------------------
      /// REAL: The executions.
      final executions = await stage<List<StepExecution>>(
        PipelineStage.execution,
        () => tools.executeCalls(calls),
        describe: (e) =>
            '${e.where((x) => !x.blocked && !x.skipped && (x.result?.success ?? false)).length}/${e.length} succeeded',
      );

      // --- 7. Verification ---------------------------------------------------
      /// REAL: The report.
      final report = await stage<VerificationReport>(
        PipelineStage.verification,
        () async => verification.verifyPlan(refined, executions),
        describe: (r) =>
            r.passed ? 'all ${r.total} steps passed' : r.issues.join('; '),
      );

      // --- 8. Learning -------------------------------------------------------
      /// REAL: The lesson.
      final lesson = await stage<String>(
        PipelineStage.learning,
        () => learning.learnFromRun(
          taskId: taskId,
          plan: refined,
          executions: executions,
          verification: report,
        ),
        describe: (l) => l,
      );

      // --- 9. Response -------------------------------------------------------
      /// REAL: The response.
      final response = await stage<String>(
        PipelineStage.response,
        () async =>
            _composeResponse(cleanInput, refined, executions, report, memories, lesson),
        describe: (r) => '${r.length} chars',
      );

      await store.updateTaskStatus(taskId, report.passed ? 'done' : 'done_with_issues');
      return finish(response: response, success: true);
    } catch (e) {
      try {
        await store.updateTaskStatus(taskId, 'failed');
      } catch (_) {}
      /// REAL: The failed stage.
      final failedStage =
          reports.isNotEmpty ? reports.last.stage.name : 'input';
      return finish(
        response: 'I ran into an error during the "$failedStage" stage: $e',
        success: false,
        error: e.toString(),
      );
    }
  }

  /// REAL: Compose the final user-facing response from stage artifacts.
  String _composeResponse(
    String input,
    Plan plan,
    List<StepExecution> executions,
    VerificationReport report,
    List<ScoredMemory> memories,
    String lesson,
  ) {
    /// REAL: The buf.
    final buf = StringBuffer();

    /// REAL: The tool outputs.
    final toolOutputs = <String>[];
    for (final e in executions) {
      if (e.skipped || e.blocked) continue;
      /// REAL: The data.
      final data = e.result?.data;
      if (data != null) {
        /// REAL: The text.
        final text = _renderToolData(e.step.tool, e.step.action, data);
        if (text.isNotEmpty) toolOutputs.add(text);
      }
    }

    if (toolOutputs.isNotEmpty) {
      buf.writeln(toolOutputs.join('\n\n'));
    } else if (report.passed) {
      buf.writeln('Done. ${plan.steps.length} step(s) completed.');
    }

    /// REAL: The blocked.
    final blocked = executions.where((e) => e.blocked).toList();
    if (blocked.isNotEmpty) {
      buf.writeln();
      buf.writeln('Held for your approval:');
      for (final b in blocked) {
        buf.writeln('- ${b.step.description}: ${b.permission.reason}');
      }
    }

    if (!report.passed) {
      buf.writeln();
      buf.writeln('Verification notes:');
      for (final issue in report.issues) {
        buf.writeln('- $issue');
      }
    }

    if (memories.isNotEmpty) {
      /// REAL: The relevant.
      final relevant =
          memories.where((m) => m.similarity > 0.15).take(3).toList();
      if (relevant.isNotEmpty) {
        buf.writeln();
        buf.writeln('Related context I recalled:');
        for (final m in relevant) {
          /// REAL: The snippet.
          final snippet = m.content.length > 120
              ? '${m.content.substring(0, 120)}...'
              : m.content;
          buf.writeln('- [${m.layer}] $snippet');
        }
      }
    }

    /// REAL: The text.
    final text = buf.toString().trim();
    if (text.isEmpty) {
      // No tool output at all (e.g. direct-answer plan): fall back to a
      // summary so the user never gets an empty reply.
      return 'Understood: "$input". ${lesson.trim()}';
    }
    return text;
  }

  String _renderToolData(String tool, String action, dynamic data) {
    if (data is Map) {
      // Prefer known shapes; otherwise stringify compactly.
      if (data.containsKey('content')) return '${data['content']}';
      if (data.containsKey('body')) {
        /// REAL: The body.
        final body = '${data['body']}';
        return body.length > 1500 ? '${body.substring(0, 1500)}...' : body;
      }
      if (data.containsKey('stdout')) {
        /// REAL: The out.
        final out = '${data['stdout']}';
        /// REAL: The err.
        final err = '${data['stderr']}';
        /// REAL: The exit.
        final exit = data['exitCode'];
        /// REAL: The parts.
        final parts = <String>[];
        if (out.trim().isNotEmpty) parts.add(out.trim());
        if (err.trim().isNotEmpty) parts.add('stderr: ${err.trim()}');
        parts.add('(exit code: $exit)');
        return parts.join('\n');
      }
      if (data.containsKey('entries')) {
        /// REAL: The entries.
        final entries = (data['entries'] as List).take(50).map((e) {
          /// REAL: The m.
          final m = Map<String, dynamic>.from(e as Map);
          return '- [${m['type']}] ${m['path']}';
        }).join('\n');
        return entries;
      }
      /// REAL: The flat.
      final flat = data.entries.map((e) => '${e.key}: ${e.value}').join('\n');
      return flat.length > 1500 ? '${flat.substring(0, 1500)}...' : flat;
    }
    /// REAL: The text.
    final text = '$data';
    return text.length > 1500 ? '${text.substring(0, 1500)}...' : text;
  }
}
