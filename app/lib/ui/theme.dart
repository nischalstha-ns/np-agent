import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// NP design system: dark-only Material 3, deep navy background, glowing
/// teal + violet accents ("Maya AI" flagship-assistant aesthetic).
///
/// Typography uses Google Fonts (Space Grotesk for display, Inter for body).
/// If the `google_fonts` package ever fails to resolve, swap the two
/// `GoogleFonts.*` calls below for plain [TextStyle]s — everything else is
/// package-free.

class NpColors {
  NpColors._();

  /// Deep navy/black app background.
  static const Color bg = Color(0xFF0A0E1A);

  /// Slightly lifted background for stacked surfaces.
  static const Color bgElevated = Color(0xFF0D1428);

  /// Card surface (used under glass layers).
  static const Color surface = Color(0xFF111A30);

  /// Primary glowing accent.
  static const Color teal = Color(0xFF2DD4BF);

  /// Secondary glowing accent.
  static const Color violet = Color(0xFF8B5CF6);

  /// Tertiary accent for mesh gradients.
  static const Color indigo = Color(0xFF6366F1);

  static const Color textPrimary = Color(0xFFE9EDF9);
  static const Color textSecondary = Color(0xFF9AA3C0);
  static const Color textFaint = Color(0xFF5F6B8C);

  static const Color success = Color(0xFF34D399);
  static const Color warning = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFF87171);

  static const LinearGradient brandGradient = LinearGradient(
    colors: [teal, violet],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient brandGradientSoft = LinearGradient(
    colors: [Color(0xFF2DD4BF), Color(0xFF8B5CF6), Color(0xFF6366F1)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class NpTheme {
  NpTheme._();

  static ThemeData dark() {
    final scheme = const ColorScheme.dark(
      primary: NpColors.teal,
      onPrimary: Color(0xFF06251F),
      secondary: NpColors.violet,
      onSecondary: Colors.white,
      tertiary: NpColors.indigo,
      surface: NpColors.surface,
      onSurface: NpColors.textPrimary,
      surfaceContainerHighest: NpColors.bgElevated,
      error: NpColors.danger,
    );

    final base = ThemeData(colorScheme: scheme);
    // Body: Inter; display/headline: Space Grotesk.
    final inter = GoogleFonts.interTextTheme(base.textTheme);
    final textTheme = inter
        .copyWith(
          displayLarge:
              GoogleFonts.spaceGrotesk(textStyle: inter.displayLarge),
          displayMedium:
              GoogleFonts.spaceGrotesk(textStyle: inter.displayMedium),
          displaySmall:
              GoogleFonts.spaceGrotesk(textStyle: inter.displaySmall),
          headlineLarge:
              GoogleFonts.spaceGrotesk(textStyle: inter.headlineLarge),
          headlineMedium:
              GoogleFonts.spaceGrotesk(textStyle: inter.headlineMedium),
          headlineSmall:
              GoogleFonts.spaceGrotesk(textStyle: inter.headlineSmall),
        )
        .apply(
          bodyColor: NpColors.textPrimary,
          displayColor: NpColors.textPrimary,
        );

    return base.copyWith(
      scaffoldBackgroundColor: NpColors.bg,
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: NpColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: NpColors.textSecondary),
      ),
      cardTheme: const CardThemeData(
        color: NpColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: Colors.white.withValues(alpha: 0.06),
        labelStyle: const TextStyle(color: NpColors.textPrimary, fontSize: 13),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        shape: const StadiumBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        hintStyle: const TextStyle(color: NpColors.textFaint),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xF20A0E1A),
        selectedItemColor: NpColors.teal,
        unselectedItemColor: NpColors.textFaint,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: NpColors.teal,
        unselectedLabelColor: NpColors.textFaint,
        indicatorColor: NpColors.teal,
        dividerColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? NpColors.teal : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? NpColors.teal.withValues(alpha: 0.35)
              : null,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: NpColors.teal,
        linearTrackColor: Color(0x22FFFFFF),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: NpColors.bgElevated,
        contentTextStyle: const TextStyle(color: NpColors.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dividerColor: Colors.white.withValues(alpha: 0.08),
    );
  }
}

/// Paints the signature NP "mesh" background: soft radial glows of teal,
/// violet and indigo over the deep navy base.
class MeshGradientPainter extends CustomPainter {
  const MeshGradientPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final blobs = <({Offset center, double radius, Color color})>[
      (
        center: Offset(size.width * 0.12, size.height * 0.06),
        radius: size.shortestSide * 0.55,
        color: NpColors.teal.withValues(alpha: 0.14),
      ),
      (
        center: Offset(size.width * 0.92, size.height * 0.22),
        radius: size.shortestSide * 0.62,
        color: NpColors.violet.withValues(alpha: 0.16),
      ),
      (
        center: Offset(size.width * 0.5, size.height * 1.02),
        radius: size.shortestSide * 0.7,
        color: NpColors.indigo.withValues(alpha: 0.12),
      ),
      (
        center: Offset(size.width * 0.85, size.height * 0.85),
        radius: size.shortestSide * 0.4,
        color: NpColors.teal.withValues(alpha: 0.07),
      ),
    ];
    for (final blob in blobs) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [blob.color, Colors.transparent],
          stops: const [0.0, 1.0],
        ).createShader(
          Rect.fromCircle(center: blob.center, radius: blob.radius),
        );
      canvas.drawCircle(blob.center, blob.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Full-screen mesh-gradient backdrop. Wrap page content with this.
class MeshBackground extends StatelessWidget {
  final Widget child;

  const MeshBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: CustomPaint(painter: MeshGradientPainter()),
        ),
        child,
      ],
    );
  }
}

/// Frosted-glass card: blur + translucent fill + hairline white border.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 20,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
    if (onTap == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(borderRadius),
      onTap: onTap,
      child: card,
    );
  }
}

/// Primary action button with the brand gradient and a soft glow.
class GlowButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final List<Color> gradientColors;

  const GlowButton({
    super.key,
    required this.child,
    this.onPressed,
    this.borderRadius = 16,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    this.gradientColors = const [NpColors.teal, NpColors.violet],
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          gradient: LinearGradient(colors: gradientColors),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: NpColors.teal.withValues(alpha: 0.35),
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: NpColors.violet.withValues(alpha: 0.25),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(borderRadius),
            onTap: onPressed,
            child: Padding(
              padding: padding,
              child: DefaultTextStyle(
                style: const TextStyle(
                  color: Color(0xFF06121A),
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
                child: IconTheme(
                  data: const IconThemeData(color: Color(0xFF06121A)),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular glowing icon button (used for the chat send button).
class GlowIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;

  const GlowIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [NpColors.teal, NpColors.violet],
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: NpColors.teal.withValues(alpha: 0.45),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Icon(icon, color: const Color(0xFF06121A), size: 22),
          ),
        ),
      ),
    );
  }
}

/// Small pill used for pipeline stage / status display.
class StagePill extends StatelessWidget {
  final String label;
  final bool success;
  final String? trailing;

  const StagePill({
    super.key,
    required this.label,
    this.success = true,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final color = success ? NpColors.teal : NpColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            success ? Icons.check_circle_outline : Icons.error_outline,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            trailing == null ? label : '$label · $trailing',
            style: TextStyle(color: color, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

/// Section header used across dashboard tabs.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: const TextStyle(
                        color: NpColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Gradient "NP" monogram used in app bars, bubbles and the boot screen.
class NpMonogram extends StatelessWidget {
  final double size;

  const NpMonogram({super.key, this.size = 36});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: NpColors.brandGradient,
        boxShadow: [
          BoxShadow(
            color: NpColors.teal.withValues(alpha: 0.45),
            blurRadius: size * 0.45,
            spreadRadius: 1,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        'NP',
        style: TextStyle(
          color: const Color(0xFF06121A),
          fontWeight: FontWeight.w800,
          fontSize: size * 0.36,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
