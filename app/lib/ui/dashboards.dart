import 'dart:async';

import '../agents/agent.dart';
import '../agents/pipeline.dart';
import '../hf/huggingface_client.dart';
import '../llm/offline_provider.dart';
import '../memory/memory_store.dart';

/// Dashboard panels as state-holding classes exposing streams.
///
/// Each panel wraps a real NP subsystem (tool usage table, memory counts,
/// active downloads, discovered models, last pipeline timings, registered
/// agents) and exposes its state over a broadcast [Stream]. A Flutter widget
/// layer renders these; the logic here is UI-framework-free.
///
/// These are "placeholders" only in the sense that no Material widgets ship
/// in this scaffold — every panel reads live state.
class PanelState<T> {
  final _controller = StreamController<T>.broadcast();
  T _value;

  PanelState(this._value);

  T get value => _value;
  Stream<T> get stream => _controller.stream;

  void update(T next) {
    _value = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  void dispose() => _controller.close();
}

/// Recent tool executions from the `tool_usage` table.
class ToolPanel {
  final MemoryStore store;
  final PanelState<List<Map<String, dynamic>>> usages =
      PanelState(const []);

  ToolPanel(this.store);

  Future<void> refresh({int limit = 50}) async {
    final rows = await store.recentToolUsage(limit: limit);
    usages.update(rows
        .map((r) => {
              'tool': r['tool'],
              'success': (r['success'] as int?) == 1,
              'durationMs': r['duration_ms'],
              'at': DateTime.fromMillisecondsSinceEpoch(
                      (r['created_at'] as int?) ?? 0)
                  .toIso8601String(),
              'summary': r['result_summary'],
            })
        .toList());
  }

  void dispose() => usages.dispose();
}

/// Memory layer counts + newest semantic facts.
class MemoryPanel {
  final MemoryStore store;
  final PanelState<Map<String, dynamic>> state = PanelState(const {});

  MemoryPanel(this.store);

  Future<void> refresh() async {
    final shortTerm = await store.countMemoryItems('short_term');
    final longTerm = await store.countMemoryItems('long_term');
    final semantic = await store.countMemoryItems('semantic');
    final failures = await store.listFailures(limit: 5);
    state.update({
      'shortTerm': shortTerm,
      'longTerm': longTerm,
      'semantic': semantic,
      'recentFailures': failures
          .map((f) => {
                'stage': f['stage'],
                'error': f['error'],
              })
          .toList(),
    });
  }

  void dispose() => state.dispose();
}

/// Active HuggingFace downloads (progress events).
class DownloadPanel {
  final HuggingFaceClient client;
  final PanelState<DownloadProgress?> active = PanelState(null);
  final PanelState<List<String>> completed = PanelState(const []);

  DownloadPanel(this.client);

  /// Start a download; progress flows into [active], finished files into
  /// [completed]. Errors are rethrown to the caller.
  Future<void> startDownload({
    required String repoId,
    required String fileName,
    required String destDir,
    String? expectedSha256,
  }) {
    final done = Completer<void>();
    client
        .downloadModel(
          repoId: repoId,
          fileName: fileName,
          destDir: destDir,
          expectedSha256: expectedSha256,
        )
        .listen(
      (progress) => active.update(progress),
      onDone: () {
        completed.update([...completed.value, '$repoId/$fileName']);
        active.update(null);
        done.complete();
      },
      onError: (Object e) {
        active.update(null);
        done.completeError(e);
      },
      cancelOnError: true,
    );
    return done.future;
  }

  void dispose() {
    active.dispose();
    completed.dispose();
  }
}

/// Discovered GGUF models + currently loaded model.
class ModelPanel {
  final OfflineLlmProvider offline;
  final PanelState<List<GgufModelInfo>> models = PanelState(const []);
  final PanelState<GgufModelInfo?> loaded = PanelState(null);

  ModelPanel(this.offline);

  Future<void> refresh() async {
    final found = await offline.discoverModels();
    models.update(found);
    loaded.update(offline.currentModel);
  }

  Future<void> load(GgufModelInfo model) async {
    await offline.loadModel(model);
    loaded.update(offline.currentModel);
  }

  void dispose() {
    models.dispose();
    loaded.dispose();
  }
}

/// Timings of the most recent pipeline run, per stage.
class PerformancePanel {
  final PanelState<List<StageReport>> stages = PanelState(const []);
  final PanelState<int> totalMs = PanelState(0);

  void record(PipelineResult result) {
    stages.update(result.stages);
    totalMs.update(result.totalMs);
  }

  double get averageStageMs {
    final s = stages.value;
    if (s.isEmpty) return 0;
    return s.fold<int>(0, (sum, r) => sum + r.durationMs) / s.length;
  }

  StageReport? get slowestStage {
    final s = stages.value;
    if (s.isEmpty) return null;
    return s.reduce((a, b) => a.durationMs >= b.durationMs ? a : b);
  }

  void dispose() {
    stages.dispose();
    totalMs.dispose();
  }
}

/// Registered agents with their descriptions.
class AgentPanel {
  final List<Agent> agents;
  final PanelState<List<Map<String, String>>> items;

  AgentPanel(this.agents)
      : items = PanelState(agents
            .map((a) => {'name': a.name, 'description': a.describe()})
            .toList());
}

/// All panels in one place, constructed from live NP subsystems.
class Dashboards {
  final ToolPanel tools;
  final MemoryPanel memory;
  final DownloadPanel downloads;
  final ModelPanel models;
  final PerformancePanel performance;
  final AgentPanel agents;

  Dashboards({
    required this.tools,
    required this.memory,
    required this.downloads,
    required this.models,
    required this.performance,
    required this.agents,
  });

  factory Dashboards.create({
    required MemoryStore store,
    required HuggingFaceClient hfClient,
    required OfflineLlmProvider offline,
    required List<Agent> agentList,
  }) =>
      Dashboards(
        tools: ToolPanel(store),
        memory: MemoryPanel(store),
        downloads: DownloadPanel(hfClient),
        models: ModelPanel(offline),
        performance: PerformancePanel(),
        agents: AgentPanel(agentList),
      );

  Future<void> refreshAll() async {
    await tools.refresh();
    await memory.refresh();
    await models.refresh();
  }

  void dispose() {
    tools.dispose();
    memory.dispose();
    downloads.dispose();
    models.dispose();
    performance.dispose();
  }
}
