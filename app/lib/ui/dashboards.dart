import 'package:flutter/material.dart';

import '../llm/offline_provider.dart';
import '../memory/tool_usage.dart';
import 'app.dart';
import 'np_controller.dart';
import 'perf.dart';
import 'theme.dart';

/// Tabbed NP dashboard: tool activity, memory, model manager, performance,
/// and the agent control panel. Every panel reads live state from the real
/// [NpCore] via [NpController] — no mock data except the clearly-marked
/// simulated download rows in the Models tab.
class DashboardPage extends StatelessWidget {
  /// Tab to open first (0 activity, 1 memory, 2 models, 3 performance,
  /// 4 agents). The bottom-nav "Models" item opens with index 2.
  final int initialTab;

  const DashboardPage({super.key, this.initialTab = 0});

  static const _tabs = [
    (icon: Icons.bolt_outlined, label: 'Activity'),
    (icon: Icons.psychology_outlined, label: 'Memory'),
    (icon: Icons.memory_outlined, label: 'Models'),
    (icon: Icons.speed_outlined, label: 'Perf'),
    (icon: Icons.smart_toy_outlined, label: 'Agents'),
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      initialIndex: initialTab.clamp(0, _tabs.length - 1),
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final t in _tabs)
                Tab(icon: Icon(t.icon, size: 18), text: t.label),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _ActivityTab(),
                _MemoryTab(),
                _ModelsTab(),
                _PerformanceTab(),
                _AgentsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- activity ---

class _ActivityTab extends StatelessWidget {
  const _ActivityTab();

  @override
  Widget build(BuildContext context) {
    final controller = NpScope.of(context);
    return RefreshIndicator(
      color: NpColors.teal,
      onRefresh: () async {
        await controller.refreshToolActivity();
        await controller.refreshMemoryStats();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
        children: [
          const SectionHeader(
            title: 'Live tool activity',
            subtitle: 'Pipeline stages + tool runs, newest first',
          ),
          if (controller.activity.isEmpty)
            const GlassCard(
              child: Text(
                'Nothing yet — send a message in Chat and the pipeline '
                'stages will stream in here.',
                style: TextStyle(
                    color: NpColors.textSecondary, fontSize: 13),
              ),
            )
          else
            for (final entry in controller.activity.take(40))
              _ActivityRow(entry: entry),
          const SectionHeader(
            title: 'Per-tool stats',
            subtitle: 'Aggregated from the tool_usage memory table',
          ),
          _ToolStatsCard(controller: controller),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final ToolActivityEntry entry;

  const _ActivityRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = entry.success ? NpColors.teal : NpColors.danger;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(
                      color: color.withValues(alpha: 0.7), blurRadius: 6),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.detail,
                    style: const TextStyle(
                        color: NpColors.textSecondary, fontSize: 12),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _timeOfDay(entry.at),
              style: const TextStyle(
                  color: NpColors.textFaint, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  String _timeOfDay(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _ToolStatsCard extends StatelessWidget {
  final NpController controller;

  const _ToolStatsCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _load(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const GlassCard(
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final stats = snap.data!;
        if (stats.isEmpty) {
          return const GlassCard(
            child: Text(
              'No tool runs recorded yet.',
              style: TextStyle(
                  color: NpColors.textSecondary, fontSize: 13),
            ),
          );
        }
        return GlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < stats.length; i++) ...[
                _ToolStatRow(stat: stats[i]),
                if (i < stats.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _load() async {
    try {
      final usage = controller.core.di.get<ToolUsageMemory>();
      final stats = await usage.stats();
      stats.sort((a, b) =>
          (b['runs'] as int? ?? 0).compareTo(a['runs'] as int? ?? 0));
      return stats;
    } catch (_) {
      return const [];
    }
  }
}

class _ToolStatRow extends StatelessWidget {
  final Map<String, dynamic> stat;

  const _ToolStatRow({required this.stat});

  @override
  Widget build(BuildContext context) {
    final runs = stat['runs'] as int? ?? 0;
    final failures = stat['failures'] as int? ?? 0;
    final avgMs = stat['avgMs'] as int? ?? 0;
    final okRate = runs == 0 ? 1.0 : (runs - failures) / runs;
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: NpColors.teal.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.build_outlined,
                size: 16, color: NpColors.teal),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${stat['tool']}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '$runs runs · ${(okRate * 100).toStringAsFixed(0)}% ok · ${avgMs}ms avg',
            style: const TextStyle(
                color: NpColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- memory ---

class _MemoryTab extends StatelessWidget {
  const _MemoryTab();

  @override
  Widget build(BuildContext context) {
    final controller = NpScope.of(context);
    final counts = controller.memoryCounts;
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    return RefreshIndicator(
      color: NpColors.teal,
      onRefresh: controller.refreshMemoryStats,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
        children: [
          const SectionHeader(
            title: 'Memory layers',
            subtitle: 'Live counts from the on-device SQLite memory store',
            trailing: null,
          ),
          GlassCard(
            child: Row(
              children: [
                const NpMonogram(size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$total',
                        style: const TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w800),
                      ),
                      const Text(
                        'total memory records',
                        style: TextStyle(
                            color: NpColors.textSecondary, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh,
                      color: NpColors.textSecondary),
                  onPressed: controller.refreshMemoryStats,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.35,
            children: [
              for (final e in counts.entries)
                _MemoryCountCard(
                  label: _prettyLayer(e.key),
                  count: e.value,
                  icon: _layerIcon(e.key),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _prettyLayer(String key) => switch (key) {
        'short_term' => 'Short-term',
        'long_term' => 'Long-term',
        'semantic' => 'Semantic',
        'user_profile' => 'User profile',
        'projects' => 'Projects',
        'skills' => 'Skills',
        'tool_runs' => 'Tool runs',
        _ => key,
      };

  IconData _layerIcon(String key) => switch (key) {
        'short_term' => Icons.bolt_outlined,
        'long_term' => Icons.archive_outlined,
        'semantic' => Icons.hub_outlined,
        'user_profile' => Icons.person_outline,
        'projects' => Icons.folder_outlined,
        'skills' => Icons.auto_awesome_outlined,
        'tool_runs' => Icons.build_outlined,
        _ => Icons.circle_outlined,
      };
}

class _MemoryCountCard extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;

  const _MemoryCountCard({
    required this.label,
    required this.count,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: NpColors.violet, size: 20),
          const SizedBox(height: 8),
          Text(
            '$count',
            style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            style: const TextStyle(
                color: NpColors.textSecondary, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- models ---

class _ModelsTab extends StatefulWidget {
  const _ModelsTab();

  @override
  State<_ModelsTab> createState() => _ModelsTabState();
}

class _ModelsTabState extends State<_ModelsTab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dl;

  @override
  void initState() {
    super.initState();
    // Drives the *simulated* download rows below.
    _dl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat();
  }

  @override
  void dispose() {
    _dl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = NpScope.of(context);
    final offline = controller.core.llm.offline;
    final models = controller.discoveredModels;
    final current = offline.currentModel;

    return RefreshIndicator(
      color: NpColors.teal,
      onRefresh: controller.refreshModels,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
        children: [
          const SectionHeader(
            title: 'Offline models',
            subtitle: 'GGUF files discovered on this device',
          ),
          GlassCard(
            child: Row(
              children: [
                Icon(
                  offline.engineLinked
                      ? Icons.check_circle
                      : Icons.warning_amber_rounded,
                  color: offline.engineLinked
                      ? NpColors.success
                      : NpColors.warning,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        offline.engineLinked
                            ? 'llama.cpp engine linked'
                            : 'Engine not linked',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13.5),
                      ),
                      Text(
                        offline.engineLinked
                            ? 'Offline inference is ready.'
                            : 'Models are discoverable, but inference needs a '
                                'llama.cpp build for this platform.',
                        style: const TextStyle(
                            color: NpColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (models.isEmpty)
            const GlassCard(
              child: Text(
                'No .gguf files found in /models, /gguf or '
                '/downloaded_models yet.',
                style: TextStyle(
                    color: NpColors.textSecondary, fontSize: 13),
              ),
            )
          else
            for (final m in models)
              _ModelRow(
                model: m,
                isCurrent: current?.path == m.path,
                onLoad: () => _loadModel(controller, m),
              ),
          const SectionHeader(
            title: 'Downloads',
            subtitle: 'Simulated rows — real HuggingFace downloads '
                'plug in here',
          ),
          // NOTE: these two rows are intentionally fake progress UI used
          // to validate the layout; they are not real downloads.
          _SimulatedDownload(
            fileName: 'llama-3.2-3b-Q4_K_M.gguf',
            progress: _dl,
            phase: 0.0,
          ),
          const SizedBox(height: 8),
          _SimulatedDownload(
            fileName: 'qwen2.5-1.5b-Q8_0.gguf',
            progress: _dl,
            phase: 0.45,
          ),
        ],
      ),
    );
  }

  Future<void> _loadModel(
      NpController controller, GgufModelInfo model) async {
    try {
      await controller.selectModel(model.fileName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Loaded ${model.fileName}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Load failed: $e')),
        );
      }
    }
  }
}

class _ModelRow extends StatelessWidget {
  final GgufModelInfo model;
  final bool isCurrent;
  final VoidCallback onLoad;

  const _ModelRow({
    required this.model,
    required this.isCurrent,
    required this.onLoad,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                gradient: NpColors.brandGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.memory,
                  size: 18, color: Color(0xFF06121A)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.fileName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${model.quant ?? 'quant?'} · '
                    '${model.sizeMb.toStringAsFixed(0)} MB',
                    style: const TextStyle(
                        color: NpColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (isCurrent)
              const StagePill(label: 'loaded')
            else
              TextButton(
                onPressed: onLoad,
                child: const Text('Load'),
              ),
          ],
        ),
      ),
    );
  }
}

class _SimulatedDownload extends StatelessWidget {
  final String fileName;
  final Animation<double> progress;
  final double phase;

  const _SimulatedDownload({
    required this.fileName,
    required this.progress,
    required this.phase,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) {
        final v = (progress.value + phase) % 1.0;
        return GlassCard(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      fileName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${(v * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                        color: NpColors.teal,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: v,
                  minHeight: 6,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------ performance ---

class _PerformanceTab extends StatelessWidget {
  const _PerformanceTab();

  @override
  Widget build(BuildContext context) {
    final controller = NpScope.of(context);
    return FutureBuilder<Map<String, String>>(
      future: collectPerfStats(
        startedAt: controller.startedAt,
        messageCount: controller.messages.length,
        toolCallCount: controller.activity
            .where((e) => e.title.startsWith('tool ·'))
            .length,
      ),
      builder: (context, snap) {
        final stats = snap.data ?? const <String, String>{};
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
          children: [
            const SectionHeader(
              title: 'Performance',
              subtitle: 'Real process stats where the platform allows',
            ),
            if (stats.isEmpty)
              const GlassCard(
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child:
                        CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.5,
                children: [
                  for (final e in stats.entries)
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            e.key,
                            style: const TextStyle(
                                color: NpColors.textSecondary,
                                fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            e.value,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            const SectionHeader(
              title: 'Registered tools',
              subtitle: 'Live from the ToolRegistry',
            ),
            GlassCard(
              padding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final name in controller.toolNames)
                      StagePill(label: name),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ----------------------------------------------------------------- agents ---

class _AgentsTab extends StatefulWidget {
  const _AgentsTab();

  @override
  State<_AgentsTab> createState() => _AgentsTabState();
}

class _AgentsTabState extends State<_AgentsTab> {
  Map<String, bool>? _enabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    final controller = NpScope.of(context);
    final map = <String, bool>{};
    for (final agent in controller.agents) {
      map[agent.name] = await controller.agentEnabled(agent.name);
    }
    map['pipeline'] = await controller.agentEnabled('pipeline');
    if (mounted) setState(() => _enabled = map);
  }

  @override
  Widget build(BuildContext context) {
    final controller = NpScope.of(context);
    final agents = controller.agents;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      children: [
        const SectionHeader(
          title: 'Agent control',
          subtitle: 'Enable / disable agents — toggles persist in memory',
        ),
        if (_enabled == null)
          const GlassCard(
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else ...[
          for (final agent in agents)
            _AgentRow(
              name: agent.name,
              description: agent.describe(),
              enabled: _enabled![agent.name] ?? true,
              onChanged: (v) => _toggle(controller, agent.name, v),
            ),
          // 11th entry: the pipeline orchestrator itself.
          _AgentRow(
            name: 'pipeline',
            description:
                'Stage orchestrator: input → planning → reasoning → memory → '
                'tools → verification → learning → response.',
            enabled: _enabled!['pipeline'] ?? true,
            onChanged: (v) => _toggle(controller, 'pipeline', v),
          ),
        ],
      ],
    );
  }

  Future<void> _toggle(
      NpController controller, String name, bool value) async {
    await controller.setAgentEnabled(name, value);
    if (mounted) {
      setState(() => _enabled![name] = value);
    }
  }
}

class _AgentRow extends StatelessWidget {
  final String name;
  final String description;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _AgentRow({
    required this.name,
    required this.description,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: SwitchListTile(
          value: enabled,
          onChanged: onChanged,
          secondary: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (enabled ? NpColors.teal : NpColors.textFaint)
                  .withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.smart_toy_outlined,
              size: 18,
              color: enabled ? NpColors.teal : NpColors.textFaint,
            ),
          ),
          title: Text(
            name,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: enabled
                  ? NpColors.textPrimary
                  : NpColors.textFaint,
            ),
          ),
          subtitle: Text(
            description,
            style: const TextStyle(
                color: NpColors.textSecondary, fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
