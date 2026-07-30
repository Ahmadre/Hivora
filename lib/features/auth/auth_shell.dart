import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality, LiquidRoundedSuperellipse;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/hex_mark.dart';
import '../search/search_tokens.dart';

/// Golden-ratio split threshold. At or above this width the auth screens show
/// the input pane (left, 38.2 %) beside a calm brand hero (right, 61.8 %). Below
/// it the content stacks centered and the hero recedes to the background — the
/// same components, compact.
const double kAuthSplitBreakpoint = 1024;

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// Bundled hero art. On the wide split [desktopLight]/[desktopDark] fill the
/// right pane (brand + copy overlaid); on compact [mobileLight]/[mobileDark] go
/// full-bleed behind the glass card. Pass `heroImages: null` to [AuthShell] to
/// fall back to the fully procedural [_AuroraBackground] instead.
class AuthHeroImages {
  const AuthHeroImages({
    required this.desktopLight,
    required this.desktopDark,
    required this.mobileLight,
    required this.mobileDark,
  });

  final String desktopLight;
  final String desktopDark;
  final String mobileLight;
  final String mobileDark;
}

/// The app's shipped hero set — serene anime scenes (a focused person at work)
/// in Hinata's navy→amber palette. Light is an airy sunlit studio; dark is a
/// calm amber-lamp dusk. Swap these four files to re-art-direct the look.
const kAppAuthHero = AuthHeroImages(
  desktopLight: 'assets/backgrounds/auth_hero_desktop_light.webp',
  desktopDark: 'assets/backgrounds/auth_hero_desktop_dark.webp',
  mobileLight: 'assets/backgrounds/auth_hero_mobile_light.webp',
  mobileDark: 'assets/backgrounds/auth_hero_mobile_dark.webp',
);

/// Shared responsive scaffold for every auth screen.
///
/// * Desktop & large tablet (≥ [kAuthSplitBreakpoint]): a φ split — [child]
///   (the form) on the left over the procedural Aurora Hive, the hero image on
///   the right with brand + copy overlaid.
/// * Mobile & tablet-portrait: [child] centered, the hero image full-bleed
///   behind the glass card under a theme-tinted legibility scrim.
///
/// The card's real liquid-glass refraction samples whatever is painted behind
/// it, so the same backdrop does double duty on both breakpoints.
class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.child,
    this.maxContentWidth = 440,
    this.heroImages = kAppAuthHero,
  });

  /// The screen's own content (usually an [AuthGlassCard] plus any footer).
  final Widget child;

  /// Max width of [child] in the input pane / compact column.
  final double maxContentWidth;

  /// Hero art. When null, the procedural [_AuroraBackground] is used instead of
  /// a bundled image.
  final AuthHeroImages? heroImages;

  @override
  Widget build(BuildContext context) {
    final hero = heroImages;
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= kAuthSplitBreakpoint;
          final dark = _isDark(context);

          // ---- Bundled image hero ----
          if (hero != null) {
            if (wide) {
              return Row(
                children: [
                  Expanded(
                    flex: 352,
                    // The form side rides on the procedural Aurora Hive so the
                    // glass card refracts real structure and the honeycomb
                    // lattice echoes the hero.
                    child: _AuroraBackground(
                      child: _InputPane(
                        maxContentWidth: maxContentWidth,
                        veil: true,
                        showBrand: false,
                        child: child,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 648,
                    child: _ImageHero(
                      image: dark ? hero.desktopDark : hero.desktopLight,
                      dark: dark,
                    ),
                  ),
                ],
              );
            }
            return _ImageBackdrop(
              image: dark ? hero.mobileDark : hero.mobileLight,
              child: _InputPane(
                maxContentWidth: maxContentWidth,
                veil: false,
                showBrand: true,
                child: child,
              ),
            );
          }

          // ---- Default fallback — procedural Aurora Hive ----
          return _AuroraBackground(
            child: wide
                ? Row(
                    children: [
                      Expanded(
                        flex: 352,
                        child: _InputPane(
                          maxContentWidth: maxContentWidth,
                          veil: true,
                          showBrand: false,
                          child: child,
                        ),
                      ),
                      const Expanded(flex: 648, child: _AuthHero()),
                    ],
                  )
                : _InputPane(
                    maxContentWidth: maxContentWidth,
                    veil: false,
                    showBrand: true,
                    child: child,
                  ),
          );
        },
      ),
    );
  }
}

/// The liquid-glass card that holds an auth form — the Liquid-Glass replacement
/// for the old `SoftCard` on these screens. Real refraction over the hero, with
/// a clipped drop shadow and glass fill tuned for text contrast.
class AuthGlassCard extends StatelessWidget {
  const AuthGlassCard({super.key, required this.child, this.padding});

  final Widget child;

  /// Defaults to a tighter inset on compact (phone) layouts so first-run
  /// screens like login fit on one screen without scrolling.
  final EdgeInsetsGeometry? padding;

  static const double _radius = 26;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final tokens = SearchTokens.of(brightness);
    final pad = padding ?? EdgeInsets.all(context.isCompact ? 22 : 32);
    return GlassPanelShadow(
      radius: BorderRadius.circular(_radius),
      shadows: tokens.panelShadow,
      child: GlassContainer(
        useOwnLayer: true,
        quality: GlassQuality.premium,
        clipBehavior: Clip.antiAlias,
        shape: const LiquidRoundedSuperellipse(borderRadius: _radius),
        settings: liquidGlassPanelSettings(
          glassFill: tokens.glassFill,
          dark: brightness == Brightness.dark,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(padding: pad, child: child),
        ),
      ),
    );
  }
}

/// The left (or compact, centered) column that holds the form. Scrolls and
/// stays vertically centered; on the split it lays a soft veil over the aurora
/// so the form text keeps its contrast.
class _InputPane extends StatelessWidget {
  const _InputPane({
    required this.child,
    required this.maxContentWidth,
    required this.veil,
    required this.showBrand,
  });

  final Widget child;
  final double maxContentWidth;
  final bool veil;

  /// On compact (no hero pane) the brand lockup rides above the card so the
  /// mark is never missing. On the wide split it's false — the hero owns it.
  final bool showBrand;

  @override
  Widget build(BuildContext context) {
    final paneChild = showBrand
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: HivBrandLockup(hexSize: context.isCompact ? 34 : 44),
              ),
              const SizedBox(height: 18),
              child,
            ],
          )
        : child;
    // No SafeArea: the backdrop and the scroll view run edge-to-edge to the
    // display bounds (immersive — no boxed-in clip line where scrolling content
    // gets cut). The safe-area insets are folded into the scroll padding
    // instead, so the first/last items still clear the status bar / home
    // indicator without the content being cut off.
    final insets = MediaQuery.paddingOf(context);
    final hPad = veil ? 36.0 : 24.0;
    final vPad = veil ? 40.0 : 18.0;
    final content = LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              hPad,
              vPad + insets.top,
              hPad,
              vPad + insets.bottom,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: paneChild,
              ),
            ),
          ),
        ),
      ),
    );
    if (!veil) return content;

    final dark = _isDark(context);
    final veilColor = dark ? const Color(0xFF0E0C18) : AppColors.canvas;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    veilColor.withValues(alpha: dark ? 0.34 : 0.42),
                    veilColor.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        content,
      ],
    );
  }
}

/// The open right pane on wide layouts, procedural fallback (heroImages null):
/// brand lockup, headline, sub, and three capability chips over the aurora.
class _AuthHero extends StatelessWidget {
  const _AuthHero();

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    Widget chip(IconData icon, String label) => _HeroChip(
      icon: icon,
      label: label,
      textColor: AppColors.ink,
      bg: Colors.white.withValues(alpha: dark ? 0.06 : 0.55),
      border: (dark ? Colors.white : AppColors.navy).withValues(
        alpha: dark ? 0.14 : 0.10,
      ),
      iconColor: AppColors.accent,
    );
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 48),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _BrandRow(onImage: false),
                  const SizedBox(height: 30),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Text(
                      context.t('authShell.heroTitle'),
                      style: TextStyle(
                        fontFamily: AppTheme.fontBrand,
                        fontSize: 36,
                        height: 1.08,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: Text(
                      context.t('authShell.heroBody'),
                      style: TextStyle(
                        fontSize: 15.5,
                        height: 1.5,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      chip(
                        LucideIcons.layoutDashboard,
                        context.t('authShell.chipBoards'),
                      ),
                      chip(LucideIcons.zap, context.t('authShell.chipSprints')),
                      chip(LucideIcons.users, context.t('authShell.chipTeam')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({
    required this.icon,
    required this.label,
    required this.textColor,
    required this.bg,
    required this.border,
    required this.iconColor,
  });

  final IconData icon;
  final String label;
  final Color textColor;
  final Color bg;
  final Color border;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// The wide hero pane in image mode: the bundled art under a theme-aware scrim,
/// with the brand + headline + capability chips laid over the calm top area.
///
/// Text colour tracks the image's luminance (which follows the theme): white on
/// the dark dusk image, deep navy on the bright sunlit one — white-on-bright
/// would wash out. The scrim lifts contrast accordingly (dark veil vs. a soft
/// paper veil), strongest at the top where the brand + headline sit.
class _ImageHero extends StatelessWidget {
  const _ImageHero({required this.image, required this.dark});

  final String image;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final textColor = dark ? Colors.white : AppColors.navyDeep;
    final subColor = dark
        ? Colors.white.withValues(alpha: 0.82)
        : AppColors.navy.withValues(alpha: 0.72);
    final scrim = dark
        ? const [
            Color(0xA6120F20),
            Color(0x33120F20),
            Color(0x00120F20),
            Color(0x59120F20),
          ]
        : const [
            Color(0xBBF4F3EF),
            Color(0x40F4F3EF),
            Color(0x00F4F3EF),
            Color(0x1FF4F3EF),
          ];
    Widget chip(IconData icon, String label) => _HeroChip(
      icon: icon,
      label: label,
      textColor: textColor,
      bg: dark
          ? Colors.white.withValues(alpha: 0.16)
          : Colors.white.withValues(alpha: 0.62),
      border: dark
          ? Colors.white.withValues(alpha: 0.28)
          : AppColors.navy.withValues(alpha: 0.12),
      iconColor: dark ? AppColors.accent : AppColors.accentStrong,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(image, fit: BoxFit.cover, alignment: Alignment.center),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: scrim,
              stops: const [0.0, 0.34, 0.62, 1.0],
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(56, 72, 56, 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BrandRow(onImage: true, dark: dark),
                  const SizedBox(height: 30),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Text(
                      context.t('authShell.heroTitle'),
                      style: TextStyle(
                        fontFamily: AppTheme.fontBrand,
                        fontSize: 36,
                        height: 1.08,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        color: textColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Text(
                      context.t('authShell.heroBody'),
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: subColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      chip(
                        LucideIcons.layoutDashboard,
                        context.t('authShell.chipBoards'),
                      ),
                      chip(LucideIcons.zap, context.t('authShell.chipSprints')),
                      chip(LucideIcons.users, context.t('authShell.chipTeam')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The horizontal brand lockup (amber hex tile + "hinata" wordmark) used in the
/// hero panes. [onImage] switches the wordmark to a theme-aware colour that
/// reads over the art.
class _BrandRow extends StatelessWidget {
  const _BrandRow({required this.onImage, this.dark = false});

  final bool onImage;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final wordColor = onImage
        ? (dark ? Colors.white : AppColors.navyDeep)
        : AppColors.ink;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(13),
          ),
          alignment: Alignment.center,
          child: const HexMark(size: 27, color: AppColors.navyDeep),
        ),
        const SizedBox(width: 13),
        Text(
          'hinata',
          style: TextStyle(
            fontFamily: AppTheme.fontBrand,
            fontSize: 25,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: wordColor,
          ),
        ),
      ],
    );
  }
}

/// Compact image mode: the mobile art full-bleed behind the glass card, under a
/// theme-tinted legibility scrim (strongest top/bottom where raw text sits).
class _ImageBackdrop extends StatelessWidget {
  const _ImageBackdrop({required this.image, required this.child});

  final String image;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    final scrim = dark ? const Color(0xFF0E0C18) : AppColors.canvas;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(image, fit: BoxFit.cover, alignment: Alignment.center),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scrim.withValues(alpha: dark ? 0.60 : 0.58),
                scrim.withValues(alpha: dark ? 0.38 : 0.36),
                scrim.withValues(alpha: dark ? 0.58 : 0.60),
                scrim.withValues(alpha: dark ? 0.72 : 0.78),
              ],
              stops: const [0.0, 0.46, 0.8, 1.0],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// The "Aurora Hive" backdrop — a deep-navy (dark) / warm-paper (light) diagonal
/// gradient with amber · indigo · ember radial glows and a faint honeycomb
/// lattice. Fully procedural, theme-aware, cached in a [RepaintBoundary] because
/// it never animates — the card's glass refracts it.
class _AuroraBackground extends StatelessWidget {
  const _AuroraBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(child: _AuroraLayers(dark: dark)),
        ),
        child,
      ],
    );
  }
}

class _AuroraLayers extends StatelessWidget {
  const _AuroraLayers({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF1B1830), Color(0xFF131024), Color(0xFF1A1430)]
              : const [Color(0xFFF7F5EE), Color(0xFFF4F3EF), Color(0xFFF1EBDD)],
        ),
      ),
      child: Stack(
        children: [
          _glow(
            top: -150,
            right: -110,
            size: 460,
            color: AppColors.accent,
            alpha: dark ? 0.16 : 0.20,
          ),
          _glow(
            bottom: -170,
            left: -130,
            size: 520,
            color: dark ? const Color(0xFF5E58BE) : AppColors.navy,
            alpha: dark ? 0.30 : 0.14,
          ),
          _glow(
            bottom: -60,
            right: 40,
            size: 340,
            color: const Color(0xFFC85A32),
            alpha: dark ? 0.13 : 0.07,
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _HexGridPainter(
                  color: (dark ? AppColors.accent : AppColors.navy).withValues(
                    alpha: dark ? 0.05 : 0.04,
                  ),
                ),
              ),
            ),
          ),
          // Soft top-left specular sheen for the glass-light feel.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.center,
                    colors: [
                      Colors.white.withValues(alpha: dark ? 0.05 : 0.12),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow({
    double? top,
    double? bottom,
    double? left,
    double? right,
    required double size,
    required Color color,
    required double alpha,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: alpha),
                color.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A faint pointy-top honeycomb lattice. Static — repaints only on theme change.
class _HexGridPainter extends CustomPainter {
  _HexGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a == 0) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    const r = 34.0;
    final hw = math.sqrt(3) * r; // hex width (flat-to-flat)
    const vs = 1.5 * r; // vertical row spacing
    for (var row = -1; row * vs < size.height + r; row++) {
      final y = row * vs;
      final off = row.isOdd ? hw / 2 : 0.0;
      for (var x = -hw; x < size.width + hw; x += hw) {
        _hex(canvas, Offset(x + off, y), r, paint);
      }
    }
  }

  void _hex(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final a = (-90 + 60 * i) * math.pi / 180;
      final p = Offset(
        center.dx + r * math.cos(a),
        center.dy + r * math.sin(a),
      );
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_HexGridPainter oldDelegate) => oldDelegate.color != color;
}
