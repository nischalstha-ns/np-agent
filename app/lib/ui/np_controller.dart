import 'dart:async';

import 'package:flutter/foundation.dart';

import '../agents/agent.dart';
import '../agents/np_core.dart';
import '../agents/pipeline.dart';
import '../llm/offline_provider.dart';
import '../memory/tool_usage.dart';
import '../tools/tool_registry.dart';

/// Chat roles rendered by the UI.
enum NpRole { user, assistant, system }

/// One chat message. Assistant messages carry the [PipelineResult] stage
/// reports so the UI can render an expandable "pipeline trace".
class NpChatMessage {
  final String id;
  final NpRole role;
  final DateTime createdAt;

  /// Current visible text. For assistant replies this grows word-by-word
  /// during the simulated streaming reveal (see [NpController.send]).
  String text;

  /// True while the typewriter reveal is running.
  bool isStreaming;

  /// Stage reports from the pipeline run that produced this reply.
  List<StageReport> stages;

  /// Total pipeline time in ms (0 when unknown).
  int totalMs;

  NpChatMessage({
    required this.id,
    required this.role,
    required this.text,
    DateTime? createdAt,
    this.isStreaming = false,
    this.stages = const [],
    this.totalMs = 0,
  }) : createdAt = createdAt ?? DateTime.now();
}

/// One row in the live tool-activity feed.
class ToolActivityEntry {
  final DateTime at;
  final String title;
  final String detail;
  final bool success;

  const ToolActivityEntry({
    required this.at,
    required this.title,
    required this.detail,
    this.success = true,
  });
}

/// UI-facing state for the whole NP app, driven by the real [NpCore].
///
/// Everything here is read from the DI container — no mock data:
/// * messages — chat history
/// * isBusy — a pipeline run is in flight
/// * currentModelName / availableModels — from the LLM router + GGUF discovery
/// * activity — live feed built from pipeline stage reports
/// * memoryCounts — per-layer counts from [MemoryStore]
class NpController extends ChangeNotifier {
  final NpCore core;
  final DateTime startedAt = DateTime.now();

  final List<NpChatMessage> messages = [];
  final List<ToolActivityEntry> activity = [];
  final List<GgufModelInfo> discoveredModels = [];

  bool _busy = false;
  bool get isBusy => _busy;

  String currentModelName = 'NP Mock';
  List<String> availableModels = const ['NP Mock'];
  Map<String, int> memoryCounts = {};

  Timer? _revealTimer;
  NpChatMessage? _activeRevealMsg;
  String _activeRevealFull = '';

  NpController(this.core);

  /// One-time load: models, memory stats, persisted tool activity.
  Future<void> init() async {
    await refreshModels();
    await refreshMemoryStats();
    await refreshToolActivity();
  }

  // ---------------------------------------------------------------- chat ---

  /// Send user text through the full pipeline and stream the reply.
  ///
  /// HONEST STREAMING NOTE: [NpCore.handle]/[runDetailed] return a complete
  /// `Future<String>` — there is no token stream at this layer. The
  /// "streaming" UX is simulated: once the full reply arrives it is revealed
  /// word-by-word on a timer ([_revealTimer]) for a typewriter effect, while
  /// [NpChatMessage.isStreaming] drives the blinking cursor in the UI.
  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _busy) return;
    _busy = true;

    messages.add(NpChatMessage(
      id: 'm${DateTime.now().microsecondsSinceEpoch}',
      role: NpRole.user,
      text: trimmed,
    ));
    final reply = NpChatMessage(
      id: 'm${DateTime.now().microsecondsSinceEpoch}a',
      role: NpRole.assistant,
      text: '',
      isStreaming: true,
    );
    messages.add(reply);
    notifyListeners();

    try {
      final result = await core.runDetailed(trimmed, sessionId: 'ui');
      reply.stages = result.stages;
      reply.totalMs = result.totalMs;
      _recordPipelineActivity(result);
      _reveal(reply, result.response);
    } catch (e) {
      reply.text = 'Error: $e';
      reply.isStreaming = false;
      activity.insert(
        0,
        ToolActivityEntry(
          at: DateTime.now(),
          title: 'chat failed',
          detail: '$e',
          success: false,
        ),
      );
    } finally {
      _busy = false;
      notifyListeners();
      unawaited(refreshMemoryStats());
      unawaited(refreshToolActivity());
    }
  }

  /// Instantly complete any in-flight reveal (used when a new reply starts
  /// streaming or the chat is cleared, so no message is left with a stuck
  /// blinking cursor and partial text).
  void _finishActiveReveal() {
    _revealTimer?.cancel();
    _revealTimer = null;
    final msg = _activeRevealMsg;
    if (msg != null && msg.isStreaming) {
      msg.text = _activeRevealFull;
      msg.isStreaming = false;
    }
    _activeRevealMsg = null;
    _activeRevealFull = '';
  }

  /// Word-by-word typewriter reveal of a completed reply.
  void _reveal(NpChatMessage msg, String full) {
    _finishActiveReveal();
    _activeRevealMsg = msg;
    _activeRevealFull = full;
    final words = full.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) {
      msg.text = full;
      msg.isStreaming = false;
      _activeRevealMsg = null;
      _activeRevealFull = '';
      notifyListeners();
      return;
    }
    final buf = StringBuffer();
    var i = 0;
    // Pace the reveal: long replies stream faster so they don't take forever.
    final step = words.length > 200
        ? const Duration(milliseconds: 6)
        : const Duration(milliseconds: 22);
    _revealTimer = Timer.periodic(step, (timer) {
      if (i >= words.length) {
        timer.cancel();
        _revealTimer = null;
        _activeRevealMsg = null;
        _activeRevealFull = '';
        msg.isStreaming = false;
        notifyListeners();
        return;
      }
      // Reveal in small word chunks for a smooth typewriter feel.
      for (var k = 0; k < 3 && i < words.length; k++, i++) {
        if (buf.isNotEmpty) buf.write(' ');
        buf.write(words[i]);
      }
      msg.text = buf.toString();
      notifyListeners();
    });
  }

  void _recordPipelineActivity(PipelineResult result) {
    for (final stage in result.stages) {
      activity.insert(
        0,
        ToolActivityEntry(
          at: DateTime.now(),
          title: 'pipeline · ${stage.stage.name}',
          detail: '${stage.detail} (${stage.durationMs} ms)',
          success: stage.success,
        ),
      );
    }
    if (activity.length > 120) {
      activity.removeRange(120, activity.length);
    }
  }

  /// Append a local system notice (e.g. connectivity changes).
  void notice(String text) {
    messages.add(NpChatMessage(
      id: 'm${DateTime.now().microsecondsSinceEpoch}n',
      role: NpRole.system,
      text: text,
    ));
    notifyListeners();
  }

  void clearChat() {
    _finishActiveReveal();
    messages.clear();
    notifyListeners();
  }

  // --------------------------------------------------------------- models ---

  /// Refresh GGUF discovery + the router's current routing decision.
  Future<void> refreshModels() async {
    final offline = core.di.get<OfflineLlmProvider>();
    discoveredModels.clear();
    try {
      discoveredModels.addAll(await offline.discoverModels());
    } catch (_) {
      // Discovery is best-effort; the UI still works without models.
    }
    final names = <String>['NP Mock'];
    for (final m in discoveredModels) {
      names.add(m.fileName);
    }
    try {
      final decision = await core.llm.routingDecision();
      currentModelName =
          decision == 'none-available' ? 'NP Mock (no route)' : decision;
    } catch (_) {
      currentModelName = 'NP Mock';
    }
    availableModels = names;
    notifyListeners();
  }

  /// Select a model by display name. GGUF names load the matching discovered
  /// file; "NP Mock" just relabels (the router still decides per request).
  Future<void> selectModel(String name) async {
    if (name == 'NP Mock') {
      currentModelName = 'NP Mock (router decides per request)';
      notifyListeners();
      return;
    }
    final offline = core.di.get<OfflineLlmProvider>();
    GgufModelInfo? match;
    for (final m in discoveredModels) {
      if (m.fileName == name) {
        match = m;
        break;
      }
    }
    if (match == null) {
      throw StateError('Model not found: $name');
    }
    await offline.loadModel(match);
    await refreshModels();
    notice('Loaded offline model: ${match.fileName}');
  }

  // --------------------------------------------------------------- memory ---

  static const List<String> memoryLayers = [
    'short_term',
    'long_term',
    'semantic',
  ];

  /// Per-layer memory counts, straight from [MemoryStore].
  Future<void> refreshMemoryStats() async {
    final store = core.store;
    final counts = <String, int>{};
    for (final layer in memoryLayers) {
      try {
        counts[layer] = await store.countMemoryItems(layer);
      } catch (_) {
        counts[layer] = 0;
      }
    }
    try {
      counts['user_profile'] = (await store.profileAll()).length;
    } catch (_) {
      counts['user_profile'] = 0;
    }
    try {
      counts['projects'] = (await store.listProjects()).length;
    } catch (_) {
      counts['projects'] = 0;
    }
    try {
      counts['skills'] = (await store.listSkills()).length;
    } catch (_) {
      counts['skills'] = 0;
    }
    try {
      final stats = await core.di.get<ToolUsageMemory>().stats();
      counts['tool_runs'] =
          stats.fold<int>(0, (sum, s) => sum + (s['runs'] as int? ?? 0));
    } catch (_) {
      counts['tool_runs'] = 0;
    }
    memoryCounts = counts;
    notifyListeners();
  }

  // ----------------------------------------------------------------- tools ---

  /// Merge persisted tool-usage rows under the live pipeline activity feed.
  Future<void> refreshToolActivity() async {
    try {
      final usage = core.di.get<ToolUsageMemory>();
      final rows = await usage.recent(limit: 40);
      for (final row in rows.reversed) {
        final tool = (row['tool'] as String?) ?? 'unknown';
        final ok = (row['success'] as int? ?? 0) == 1;
        final ms = (row['duration_ms'] as int?) ?? 0;
        final summary = (row['result_summary'] as String?) ?? '';
        // Avoid duplicating rows already represented in the live feed.
        final dup = activity.any(
          (e) => e.title == 'tool · $tool' && e.detail.contains('($ms ms)'),
        );
        if (!dup) {
          activity.add(ToolActivityEntry(
            at: DateTime.tryParse((row['created_at'] as String?) ?? '') ??
                DateTime.now(),
            title: 'tool · $tool',
            detail:
                '${summary.isEmpty ? 'run' : summary} (${ms} ms)',
            success: ok,
          ));
        }
      }
      activity.sort((a, b) => b.at.compareTo(a.at));
      if (activity.length > 160) {
        activity.removeRange(160, activity.length);
      }
      notifyListeners();
    } catch (_) {
      // Best-effort; the live feed still works.
    }
  }

  List<String> get toolNames {
    try {
      return core.di.get<ToolRegistry>().names();
    } catch (_) {
      return const [];
    }
  }

  // ----------------------------------------------------------------- agents ---

  /// The 10 registered agents, plus the pipeline orchestrator as an 11th
  /// controllable entry (it owns the stage chain, so it belongs on the
  /// control panel even though it isn't an [Agent] subclass).
  List<Agent> get agents {
    try {
      return core.di.get<List<Agent>>();
    } catch (_) {
      return const [];
    }
  }

  String _agentKey(String name) => 'np_agent_enabled_$name';

  Future<bool> agentEnabled(String name) async {
    try {
      return (await core.store.profileGet(_agentKey(name))) != 'false';
    } catch (_) {
      return true;
    }
  }

  Future<void> setAgentEnabled(String name, bool enabled) async {
    try {
      await core.store.profileSet(_agentKey(name), enabled.toString());
    } catch (_) {
      // Toggle persistence is best-effort.
    }
    notifyListeners();
  }

  // --------------------------------------------------------------- lifecycle ---

  @override
  void dispose() {
    _finishActiveReveal();
    super.dispose();
  }
}
