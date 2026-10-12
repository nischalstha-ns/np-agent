import '../memory/retrieval.dart';
import '../memory/short_term.dart';
import 'agent.dart';

/// REAL: Memory stage of the pipeline.
///
/// On every run it:
/// 1. records the current turn into short-term memory (working context), and
/// 2. retrieves the most relevant memories across short-term, long-term and
///    semantic layers via [RetrievalService] (embedding cosine + recency +
///    importance scoring).
class MemoryAgent extends Agent {
  /// REAL: The retrieval.
  final RetrievalService retrieval;
  /// REAL: The short term.
  final ShortTermMemory shortTerm;

  MemoryAgent({required this.retrieval, required this.shortTerm});

  /// REAL: The name.
  @override
  String get name => 'memory';

  @override
  String describe() =>
      'Retrieves relevant memories (embedding + recency + importance) and '
      'records the current turn into short-term memory.';

  /// REAL: Recall memories for [ctx]. Pure retrieval used directly by the pipeline.
  Future<List<ScoredMemory>> recall(TaskContext ctx, {int topK = 5}) {
    return retrieval.retrieve(
      ctx.input,
      layers: const ['short_term', 'long_term', 'semantic'],
      topK: topK,
    );
  }

  /// REAL: Executes.
  @override
  Future<AgentResult> execute(TaskContext ctx) async {
    /// REAL: The started.
    final started = DateTime.now();
    try {
      // 1. Record this turn as working context (best effort; never fatal).
      try {
        await shortTerm.save('turn_${ctx.taskId}', ctx.input, importance: 0.4);
      } catch (_) {
        // short-term write failure must not break the pipeline
      }
      // 2. Retrieve relevant memories.
      /// REAL: The memories.
      final memories = await recall(ctx);
      return AgentResult.ok(
        name,
        {
          'memories': memories.map((m) => m.toJson()).toList(),
          'count': memories.length,
        },
        started,
        DateTime.now(),
      );
    } catch (e) {
      return AgentResult.fail(name, 'Memory retrieval failed: $e', started, DateTime.now());
    }
  }
}
