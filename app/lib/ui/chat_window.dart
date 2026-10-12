import 'package:flutter/material.dart';

import '../agents/pipeline.dart';
import 'app.dart';
import 'np_controller.dart';
import 'theme.dart';
import 'voice_overlay.dart';

/// The flagship NP chat experience: streaming typewriter replies, suggestion
/// chips, a glassmorphic input bar with glowing send button, voice input,
/// and an expandable pipeline trace under each assistant reply.
class ChatWindow extends StatefulWidget {
  const ChatWindow({super.key});

  @override
  State<ChatWindow> createState() => _ChatWindowState();
}

class _ChatWindowState extends State<ChatWindow> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  static const _suggestions = [
    'List my files',
    'What can you do?',
    'Search the web',
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  NpController _controller(BuildContext context) => NpScope.of(context);

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    await _controller(context).send(text);
  }

  Future<void> _openVoice() async {
    // VoiceOverlay returns mock-transcribed text (until the speech engine
    // is wired); null means the user cancelled.
    final transcript = await VoiceOverlay.show(context);
    if (transcript != null && mounted) {
      _input.text = transcript;
      _input.selection = TextSelection.fromPosition(
        TextPosition(offset: _input.text.length),
      );
    }
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller(context);
    // Keep the latest message visible as the typewriter streams.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Column(
      children: [
        Expanded(
          child: controller.messages.isEmpty
              ? _EmptyState(onSuggestion: (s) => controller.send(s))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                  itemCount: controller.messages.length,
                  itemBuilder: (context, i) {
                    final msg = controller.messages[i];
                    return _MessageRow(message: msg);
                  },
                ),
        ),
        _SuggestionChips(
          suggestions: _suggestions,
          enabled: !controller.isBusy,
          onTap: (s) => controller.send(s),
        ),
        _InputBar(
          controller: _input,
          enabled: !controller.isBusy,
          onSend: _send,
          onVoice: _openVoice,
        ),
      ],
    );
  }
}

/// Welcome hero shown before the first message.
class _EmptyState extends StatelessWidget {
  final ValueChanged<String> onSuggestion;

  const _EmptyState({required this.onSuggestion});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const NpMonogram(size: 72),
            const SizedBox(height: 20),
            ShaderMask(
              shaderCallback: (bounds) =>
                  NpColors.brandGradient.createShader(bounds),
              child: Text(
                'Hey, I\'m NP',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your hybrid offline + online AI operator.\nAsk me to run tools, remember things,\nand get work done.',
              textAlign: TextAlign.center,
              style: TextStyle(color: NpColors.textSecondary, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                for (final s in ['List my files', 'What can you do?', 'Search the web'])
                  ActionChip(
                    label: Text(s),
                    avatar: const Icon(Icons.auto_awesome,
                        size: 15, color: NpColors.teal),
                    onPressed: () => onSuggestion(s),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionChips extends StatelessWidget {
  final List<String> suggestions;
  final bool enabled;
  final ValueChanged<String> onTap;

  const _SuggestionChips({
    required this.suggestions,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => ActionChip(
          label: Text(suggestions[i]),
          onPressed: enabled ? () => onTap(suggestions[i]) : null,
        ),
      ),
    );
  }
}

/// Glassmorphic input bar with mic + glowing send button.
class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final Future<void> Function() onSend;
  final Future<void> Function() onVoice;

  const _InputBar({
    required this.controller,
    required this.enabled,
    required this.onSend,
    required this.onVoice,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      child: GlassCard(
        borderRadius: 28,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Voice input',
              icon: const Icon(Icons.mic_none_outlined),
              color: NpColors.teal,
              onPressed: enabled ? () => onVoice() : null,
            ),
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                style: const TextStyle(color: NpColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Ask NP anything…',
                  filled: false,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 4),
            GlowIconButton(
              icon: enabled ? Icons.arrow_upward : Icons.more_horiz,
              onPressed: enabled ? () => onSend() : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  final NpChatMessage message;

  const _MessageRow({required this.message});

  @override
  Widget build(BuildContext context) {
    switch (message.role) {
      case NpRole.user:
        return _UserBubble(message: message);
      case NpRole.assistant:
        return _AssistantBubble(message: message);
      case NpRole.system:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Text(
              message.text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: NpColors.textFaint,
                  fontSize: 12,
                  fontStyle: FontStyle.italic),
            ),
          ),
        );
    }
  }
}

class _UserBubble extends StatelessWidget {
  final NpChatMessage message;

  const _UserBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(left: 56, top: 6, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7C5CFC), Color(0xFF5B3DF0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(6),
          ),
          boxShadow: [
            BoxShadow(
              color: NpColors.violet.withValues(alpha: 0.3),
              blurRadius: 16,
            ),
          ],
        ),
        child: SelectableText(
          message.text,
          style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.45),
        ),
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  final NpChatMessage message;

  const _AssistantBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 40, top: 6, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: NpMonogram(size: 30),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GlassCard(
              borderRadius: 18,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.text.isEmpty && message.isStreaming)
                    const _ThinkingDots()
                  else
                    SelectableText.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: message.text,
                            style: const TextStyle(
                              color: NpColors.textPrimary,
                              fontSize: 14.5,
                              height: 1.5,
                            ),
                          ),
                          if (message.isStreaming)
                            const WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: _BlinkingCursor(),
                            ),
                        ],
                      ),
                    ),
                  if (message.stages.isNotEmpty)
                    _PipelineTrace(
                      stages: message.stages,
                      totalMs: message.totalMs,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three bouncing dots while the pipeline produces the reply.
class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
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
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final t = (_ctrl.value * 3 - i).clamp(0.0, 1.0);
          final scale = 0.5 + 0.5 * (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
            width: 8 * scale + 4,
            height: 8 * scale + 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: NpColors.teal.withValues(alpha: 0.4 + 0.6 * scale),
              boxShadow: [
                BoxShadow(
                  color: NpColors.teal.withValues(alpha: 0.5 * scale),
                  blurRadius: 8,
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

/// Blinking block cursor shown while the typewriter reveal is streaming.
class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor();

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 8,
        height: 16,
        margin: const EdgeInsets.only(left: 3),
        decoration: BoxDecoration(
          color: NpColors.teal,
          borderRadius: BorderRadius.circular(2),
          boxShadow: [
            BoxShadow(
              color: NpColors.teal.withValues(alpha: 0.8),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}

/// Expandable pipeline stage trace under an assistant reply.
class _PipelineTrace extends StatelessWidget {
  final List<StageReport> stages;
  final int totalMs;

  const _PipelineTrace({required this.stages, required this.totalMs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          expansionTileTheme: const ExpansionTileThemeData(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.only(top: 6),
          ),
        ),
        child: ExpansionTile(
          title: Text(
            'Pipeline trace · ${stages.length} stages · ${totalMs}ms',
            style: const TextStyle(
              color: NpColors.textFaint,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          trailing: const Icon(Icons.expand_more,
              size: 18, color: NpColors.textFaint),
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in stages)
                  StagePill(
                    label: s.stage.name,
                    success: s.success,
                    trailing: '${s.durationMs}ms',
                  ),
              ],
            ),
            const SizedBox(height: 6),
            for (final s in stages)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(
                        s.stage.name,
                        style: const TextStyle(
                            color: NpColors.textFaint, fontSize: 11.5),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        s.detail,
                        style: const TextStyle(
                            color: NpColors.textSecondary, fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
