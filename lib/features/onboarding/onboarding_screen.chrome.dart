part of 'onboarding_screen.dart';

// ───────────────────────── background ─────────────────────────

class _BackgroundGradient extends StatelessWidget {
  const _BackgroundGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [_bgTop, _bgMid, _bgBot],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
    );
  }
}

/// Three softly-drifting colour orbs, redrawn from the ambient clock.
class _Orbs extends StatelessWidget {
  const _Orbs({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = animation.value * 2 * math.pi;
          return Stack(
            children: [
              _orb(
                size: 360,
                color: const Color(0x33D9A032), // amber .20
                top: -120 + math.sin(t) * 24,
                right: -130 + math.cos(t * 0.8) * 18,
              ),
              _orb(
                size: 300,
                color: const Color(0x296450D2), // violet .16
                bottom: 20 + math.cos(t * 0.9) * 26,
                left: -90 + math.sin(t * 1.1) * 20,
              ),
              _orb(
                size: 220,
                color: const Color(0x12C85A32), // warm .07
                top: 360 + math.sin(t * 1.3) * 22,
                right: -40 + math.cos(t) * 16,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _orb({
    required double size,
    required Color color,
    double? top,
    double? bottom,
    double? left,
    double? right,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
            stops: const [0.0, 0.7],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── chrome ─────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.visible, required this.onSkip});

  final bool visible;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 240),
        opacity: visible ? 1 : 0,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 20),
            child: TextButton(
              onPressed: visible ? onSkip : null,
              style: TextButton.styleFrom(
                foregroundColor: _white(0.45),
                textStyle: const TextStyle(
                  fontFamily: AppTheme.fontUi,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              child: Text(context.t('onboarding.skip')),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.index,
    required this.total,
    required this.isLast,
    required this.onCta,
  });

  final int index;
  final int total;
  final bool isLast;
  final VoidCallback onCta;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [_navFade, Color(0x00000000)],
          stops: [0.45, 1.0],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < total; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutBack,
                  margin: const EdgeInsets.symmetric(horizontal: 3.5),
                  height: 6,
                  width: i == index ? 28 : 6,
                  decoration: BoxDecoration(
                    color: i == index ? _amber : _white(0.22),
                    borderRadius: BorderRadius.circular(3),
                    // Keep the shadow present with a constant (positive) blur and
                    // only fade its alpha — the width uses Curves.easeOutBack,
                    // which overshoots past its endpoints, and lerping a shadow
                    // to/from null under that overshoot yields a negative blur
                    // radius (assertion crash). A constant blurRadius stays
                    // non-negative through the overshoot.
                    boxShadow: [
                      BoxShadow(
                        color: _amber.withValues(
                          alpha: i == index ? 0.55 : 0.0,
                        ),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _CtaButton(isLast: isLast, onTap: onCta),
          ),
        ],
      ),
    );
  }
}

class _CtaButton extends StatefulWidget {
  const _CtaButton({required this.isLast, required this.onTap});

  final bool isLast;
  final VoidCallback onTap;

  @override
  State<_CtaButton> createState() => _CtaButtonState();
}

class _CtaButtonState extends State<_CtaButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final isLast = widget.isLast;
    final label = context.t(
      isLast ? 'onboarding.getStarted' : 'onboarding.continue',
    );

    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: BackdropFilter(
            filter: isLast
                ? ImageFilter.blur()
                : ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                gradient: isLast
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_amber, _amber2],
                      )
                    : null,
                color: isLast ? null : _white(0.10),
                border: Border.all(
                  color: isLast ? Colors.transparent : _white(0.16),
                ),
                boxShadow: isLast
                    ? [
                        BoxShadow(
                          color: _amber.withValues(alpha: 0.40),
                          blurRadius: 30,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: AppTheme.fontUi,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.15,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── slides ─────────────────────────

class _WelcomeSlide extends StatelessWidget {
  const _WelcomeSlide({required this.glow});

  final Animation<double> glow;

  @override
  Widget build(BuildContext context) {
    // The brand hero scales up on wider canvases so it never reads as a small
    // phone artefact stranded in the middle of a desktop window.
    final tile = switch (context.layoutSize) {
      LayoutSize.compact => 132.0,
      LayoutSize.medium => 168.0,
      LayoutSize.expanded => 200.0,
    };
    final glowSize = tile * 1.6;
    final word = switch (context.layoutSize) {
      LayoutSize.compact => 42.0,
      LayoutSize.medium => 54.0,
      LayoutSize.expanded => 66.0,
    };
    final tagline = switch (context.layoutSize) {
      LayoutSize.compact => 14.5,
      LayoutSize.medium => 17.0,
      LayoutSize.expanded => 19.0,
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: glowSize,
              height: glowSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // pulsing amber glow
                  AnimatedBuilder(
                    animation: glow,
                    builder: (context, child) {
                      final p =
                          0.5 + 0.5 * math.sin(glow.value * 2 * math.pi * 6.7);
                      return Opacity(
                        opacity: 0.7 + 0.3 * p,
                        child: Transform.scale(
                          scale: 1 + 0.13 * p,
                          child: child,
                        ),
                      );
                    },
                    child: Container(
                      width: glowSize,
                      height: glowSize,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [Color(0x47D9A032), Color(0x00D9A032)],
                          stops: [0.0, 0.65],
                        ),
                      ),
                    ),
                  ),
                  // glass tile + brand mark
                  _GlassTile(
                    size: tile,
                    radius: tile * 0.29,
                    child: HexMark(size: tile * 0.53),
                  ),
                ],
              ),
            ),
            SizedBox(height: tile * 0.21),
            Text(
              'hinata',
              style: TextStyle(
                fontFamily: AppTheme.fontBrand,
                fontSize: word,
                fontWeight: FontWeight.w700,
                letterSpacing: -2,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.t('onboarding.tagline'),
              style: TextStyle(
                fontFamily: AppTheme.fontUi,
                fontSize: tagline,
                color: _white(0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureSlide extends StatelessWidget {
  const _FeatureSlide({
    required this.labelKey,
    required this.titleKey,
    required this.bodyKey,
    required this.card,
  });

  final String labelKey;
  final String titleKey;
  final String bodyKey;
  final Widget card;

  @override
  Widget build(BuildContext context) {
    return switch (context.layoutSize) {
      // Phone: visual on top, centred text below.
      LayoutSize.compact => _stacked(context, scale: 1, cardWidth: null),
      // Tablet portrait: same stack, scaled up and tighter to a max width.
      LayoutSize.medium => _stacked(context, scale: 1.28, cardWidth: 440),
      // Desktop / tablet landscape: two-column hero.
      LayoutSize.expanded => _split(context),
    };
  }

  Widget _stacked(
    BuildContext context, {
    required double scale,
    required double? cardWidth,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: cardWidth ?? 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              cardWidth == null
                  ? _GlassCard(child: card)
                  : _scaledCard(maxWidth: cardWidth),
              SizedBox(height: 28 * scale),
              _text(context, scale: scale, align: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _split(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 5,
                child: _text(
                  context,
                  scale: 1.4,
                  align: TextAlign.left,
                  crossAxis: CrossAxisAlignment.start,
                  bodyMaxWidth: 380,
                ),
              ),
              const SizedBox(width: 56),
              Expanded(
                flex: 6,
                child: Align(
                  alignment: Alignment.center,
                  child: _scaledCard(maxWidth: 480),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The mini-UI card is authored at a fixed 360px "design width"; on wider
  /// layouts we scale that whole composition uniformly so the inner type stays
  /// in proportion instead of stretching the columns and shrinking the text.
  Widget _scaledCard({required double maxWidth}) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(width: 360, child: _GlassCard(child: card)),
      ),
    );
  }

  Widget _text(
    BuildContext context, {
    required double scale,
    required TextAlign align,
    CrossAxisAlignment crossAxis = CrossAxisAlignment.center,
    double bodyMaxWidth = 290,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxis,
      children: [
        Text(
          context.t(labelKey).toUpperCase(),
          style: TextStyle(
            fontFamily: AppTheme.fontUi,
            fontSize: 10.5 * scale,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
            color: _amber,
          ),
        ),
        SizedBox(height: 7 * scale),
        Text(
          context.t(titleKey),
          textAlign: align,
          style: TextStyle(
            fontFamily: AppTheme.fontBrand,
            fontSize: 31 * scale,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
            height: 1.1,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 11 * scale),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: bodyMaxWidth),
          child: Text(
            context.t(bodyKey),
            textAlign: align,
            style: TextStyle(
              fontFamily: AppTheme.fontUi,
              fontSize: 13.5 * scale,
              height: 1.7,
              color: _white(0.48),
            ),
          ),
        ),
      ],
    );
  }
}
