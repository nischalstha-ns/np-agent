import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Full-screen voice input overlay with an animated waveform.
///
/// NOTE: transcription is currently **mocked** — the overlay returns a
/// canned transcript string on "Done" so the chat input flow works end to
/// end. When the speech engine (SpeechAgent) is wired, replace
/// [_mockTranscript] with the real recognizer output.
class VoiceOverlay extends StatefulWidget {
  const VoiceOverlay({super.key});

  /// Shows the overlay. Returns the transcribed text, or null on cancel.
  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => const VoiceOverlay(),
    );
  }

  @override
  State<VoiceOverlay> createState() => _VoiceOverlayState();
}

class _VoiceOverlayState extends State<VoiceOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // Mock transcript inserted into the chat input on "Done".
  static const _mockTranscript = 'Hey NP, what can you do?';

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  tooltip: 'Cancel',
                  icon: const Icon(Icons.close, color: NpColors.textSecondary),
                  onPressed: () => Navigator.of(context).pop(null),
                ),
              ),
              const Spacer(),
              _Waveform(controller: _ctrl),
              const SizedBox(height: 32),
              ShaderMask(
                shaderCallback: (b) =>
                    NpColors.brandGradient.createShader(b),
                child: const Text(
                  'Listening…',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Speak now — NP is listening',
                style: TextStyle(
                    color: NpColors.textSecondary, fontSize: 13.5),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: NpColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: NpColors.warning.withValues(alpha: 0.4)),
                ),
                child: const Text(
                  'demo transcription',
                  style: TextStyle(
                      color: NpColors.warning, fontSize: 11.5),
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: NpColors.textSecondary,
                      side: BorderSide(
                          color:
                              Colors.white.withValues(alpha: 0.2)),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 26, vertical: 14),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 14),
                  GlowButton(
                    borderRadius: 28,
                    onPressed: () =>
                        Navigator.of(context).pop(_mockTranscript),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check, size: 18),
                        SizedBox(width: 8),
                        Text('Use transcript'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Animated waveform bars driven by a looping [AnimationController].
class _Waveform extends StatelessWidget {
  final AnimationController controller;

  const _Waveform({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(27, (i) {
            final phase = controller.value * 2 * math.pi;
            final wave =
                (math.sin(phase + i * 0.55) * 0.5 + 0.5); // 0..1
            final wave2 =
                (math.sin(phase * 1.7 + i * 0.9) * 0.5 + 0.5);
            final h = 14 + 86 * wave * (0.4 + 0.6 * wave2);
            final t = i / 26;
            final color = Color.lerp(NpColors.teal, NpColors.violet, t)!;
            return Container(
              width: 5,
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: LinearGradient(
                  colors: [color.withValues(alpha: 0.55), color],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 8,
                  ),
                ],
              ),
            );
          }),
        );
      },
    );
  }
}
