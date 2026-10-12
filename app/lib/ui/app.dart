import 'package:flutter/material.dart';

import '../agents/np_core.dart';
import 'bubble.dart';
import 'chat_window.dart';
import 'dashboards.dart';
import 'np_controller.dart';
import 'theme.dart';

/// NP Flutter entry point widget.
class NpApp extends StatelessWidget {
  const NpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NP — Maya AI',
      theme: NpTheme.dark(),
      debugShowCheckedModeBanner: false,
      home: const NpBootstrap(),
    );
  }
}

/// Boots [NpCore] once, showing a sleek pulsing-logo loading screen while
/// the DI container, memory store and model discovery initialize.
class NpBootstrap extends StatefulWidget {
  const NpBootstrap({super.key});

  @override
  State<NpBootstrap> createState() => _NpBootstrapState();
}

class _NpBootstrapState extends State<NpBootstrap> {
  NpCore? _core;
  NpController? _controller;
  String? _error;
  String _bootStep = 'Warming up the neural core…';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      setState(() => _bootStep = 'Opening memory store…');
      final core = await NpCore.initialize();
      if (!mounted) {
        await core.dispose();
        return;
      }
      setState(() => _bootStep = 'Discovering offline models…');
      final controller = NpController(core);
      await controller.init();
      if (!mounted) {
        controller.dispose();
        await core.dispose();
        return;
      }
      setState(() {
        _core = core;
        _controller = controller;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _core?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: MeshBackground(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: GlassCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        color: NpColors.danger, size: 40),
                    const SizedBox(height: 12),
                    const Text(
                      'NP failed to start',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(
                          color: NpColors.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    GlowButton(
                      onPressed: () {
                        setState(() {
                          _error = null;
                          _bootStep = 'Retrying…';
                        });
                        _boot();
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_core == null || _controller == null) {
      return Scaffold(
        body: MeshBackground(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PulsingNpLogo(),
                const SizedBox(height: 28),
                const Text(
                  'NP',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 6,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Maya AI · hybrid offline + online agent',
                  style: TextStyle(
                      color: NpColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 180,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: const LinearProgressIndicator(minHeight: 3),
                  ),
                ),
                const SizedBox(height: 12),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _bootStep,
                    key: ValueKey(_bootStep),
                    style: const TextStyle(
                        color: NpColors.textFaint, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return NpScope(
      controller: _controller!,
      child: const HomeShell(),
    );
  }
}

/// Pulsing NP monogram for the boot screen.
class PulsingNpLogo extends StatefulWidget {
  const PulsingNpLogo({super.key});

  @override
  State<PulsingNpLogo> createState() => _PulsingNpLogoState();
}

class _PulsingNpLogoState extends State<PulsingNpLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        return Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: NpColors.teal.withValues(alpha: 0.25 + 0.35 * t),
                blurRadius: 30 + 30 * t,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Transform.scale(
            scale: 1.0 + 0.06 * t,
            child: const NpMonogram(size: 96),
          ),
        );
      },
    );
  }
}

/// Inherited access to the [NpController]; widgets use `NpScope.of(context)`
/// to read (and subscribe to) controller state.
class NpScope extends InheritedNotifier<NpController> {
  const NpScope({
    super.key,
    required NpController controller,
    required super.child,
  }) : super(notifier: controller);

  static NpController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<NpScope>();
    assert(scope != null, 'NpScope.of() called outside an NpScope');
    return scope!.notifier!;
  }
}

/// Home shell: bottom navigation across Chat / Dashboard / Models, a shared
/// app bar with model picker + floating-bubble toggle.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  NpBubbleHandle? _bubble;

  void _toggleBubble() {
    if (_bubble != null) {
      _bubble!.hide();
      _bubble = null;
      return;
    }
    _bubble = NpBubble.show(
      context,
      onOpen: () {
        _bubble = null;
        setState(() => _tab = 0);
      },
    );
  }

  @override
  void dispose() {
    _bubble?.hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = NpScope.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Row(
          children: [
            const NpMonogram(size: 34),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NP', style: TextStyle(fontSize: 17)),
                Text(
                  'Maya AI',
                  style: TextStyle(
                    fontSize: 11,
                    color: NpColors.textSecondary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          _ModelPicker(controller: controller),
          IconButton(
            tooltip: 'Floating bubble',
            icon: const Icon(Icons.bubble_chart_outlined),
            onPressed: _toggleBubble,
          ),
        ],
      ),
      body: MeshBackground(
        child: SafeArea(
          child: IndexedStack(
            index: _tab,
            children: const [
              ChatWindow(),
              DashboardPage(),
              // Models tab jumps straight to the Models dashboard tab.
              DashboardPage(initialTab: 2),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.memory_outlined),
            activeIcon: Icon(Icons.memory),
            label: 'Models',
          ),
        ],
      ),
    );
  }
}

/// Model picker dropdown in the app bar: lists "NP Mock" plus discovered
/// GGUF model files and the router's current decision.
class _ModelPicker extends StatelessWidget {
  final NpController controller;

  const _ModelPicker({required this.controller});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Select model',
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.smart_toy_outlined, size: 18),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Text(
              _shortName(controller.currentModelName),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: NpColors.textSecondary,
              ),
            ),
          ),
          const Icon(Icons.arrow_drop_down, size: 18),
        ],
      ),
      color: NpColors.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      onSelected: (name) async {
        try {
          await controller.selectModel(name);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Model: $name')),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not load model: $e')),
            );
          }
        }
      },
      itemBuilder: (context) => [
        for (final name in controller.availableModels)
          PopupMenuItem<String>(
            value: name,
            child: Row(
              children: [
                Icon(
                  name == 'NP Mock'
                      ? Icons.auto_awesome_outlined
                      : Icons.memory_outlined,
                  size: 16,
                  color: NpColors.teal,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: NpColors.textPrimary, fontSize: 13),
                  ),
                ),
                if (name == controller.currentModelName ||
                    _shortName(controller.currentModelName) == name)
                  const Icon(Icons.check,
                      size: 16, color: NpColors.teal),
              ],
            ),
          ),
      ],
    );
  }

  String _shortName(String decision) {
    // routingDecision() returns e.g. "offline (model.gguf)".
    final m = RegExp(r'\(([^)]+)\)').firstMatch(decision);
    return m?.group(1) ?? decision;
  }
}
