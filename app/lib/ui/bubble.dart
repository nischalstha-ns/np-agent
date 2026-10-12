import 'package:flutter/material.dart';

import 'theme.dart';

/// Handle for a shown [NpBubble]; call [hide] to remove the overlay.
class NpBubbleHandle {
  final OverlayEntry _entry;
  bool _hidden = false;

  NpBubbleHandle(this._entry);

  void hide() {
    if (_hidden) return;
    _hidden = true;
    _entry.remove();
  }
}

/// Floating NP bubble: a draggable, glowing glass circle shown in an
/// [OverlayEntry] above the whole app. Tapping it dismisses the bubble and
/// fires [onOpen] (the host navigates to / expands the chat window).
class NpBubble {
  NpBubble._();

  static NpBubbleHandle show(
    BuildContext context, {
    required VoidCallback onOpen,
  }) {
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _DraggableBubble(
        onTap: () {
          entry.remove();
          onOpen();
        },
      ),
    );
    overlay.insert(entry);
    return NpBubbleHandle(entry);
  }
}

class _DraggableBubble extends StatefulWidget {
  final VoidCallback onTap;

  const _DraggableBubble({required this.onTap});

  @override
  State<_DraggableBubble> createState() => _DraggableBubbleState();
}

class _DraggableBubbleState extends State<_DraggableBubble>
    with SingleTickerProviderStateMixin {
  Offset? _pos;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    _pos ??= Offset(screen.width - 92, screen.height * 0.62);

    return Positioned(
      left: _pos!.dx,
      top: _pos!.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _pos = _pos! + d.delta),
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) => Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: NpColors.brandGradient,
              boxShadow: [
                BoxShadow(
                  color: NpColors.teal
                      .withValues(alpha: 0.35 + 0.3 * _pulse.value),
                  blurRadius: 22 + 14 * _pulse.value,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: NpColors.violet
                      .withValues(alpha: 0.25 + 0.2 * _pulse.value),
                  blurRadius: 34,
                  spreadRadius: 3,
                ),
              ],
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            alignment: Alignment.center,
            child: child,
          ),
          child: const Text(
            'NP',
            style: TextStyle(
              color: Color(0xFF06121A),
              fontWeight: FontWeight.w800,
              fontSize: 20,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
