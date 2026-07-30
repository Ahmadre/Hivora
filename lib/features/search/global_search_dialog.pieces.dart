part of 'global_search_dialog.dart';

// ─────────────────────────────── pieces ─────────────────────────────────────

class _IconTile extends StatelessWidget {
  const _IconTile({required this.tokens, required this.icon});
  final SearchTokens tokens;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: tokens.field,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.hairline),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 17, color: tokens.inkSoft),
    );
  }
}

/// Filled hexagon chip carrying a project key (the `.gs-pkey` clip-path).
class _HexChip extends StatelessWidget {
  const _HexChip({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 34,
      child: ClipPath(
        clipper: _HexClipper(),
        child: ColoredBox(
          color: color,
          child: Center(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HexClipper extends CustomClipper<Path> {
  // polygon(50% 0, 100% 25%, 100% 75%, 50% 100%, 0 75%, 0 25%)
  @override
  Path getClip(Size s) => Path()
    ..moveTo(s.width * 0.5, 0)
    ..lineTo(s.width, s.height * 0.25)
    ..lineTo(s.width, s.height * 0.75)
    ..lineTo(s.width * 0.5, s.height)
    ..lineTo(0, s.height * 0.75)
    ..lineTo(0, s.height * 0.25)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    required this.tokens,
    required this.icon,
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final SearchTokens tokens;
  final IconData icon;
  final String label;
  final int? count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? tokens.ink : tokens.inkSoft;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? tokens.tintStrong : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? tokens.edgeSoft : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(
                  fontFamily: AppTheme.fontMono,
                  fontSize: 10.5,
                  color: fg.withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EscPill extends StatelessWidget {
  const _EscPill({
    required this.tokens,
    required this.onTap,
    required this.mobile,
  });
  final SearchTokens tokens;
  final VoidCallback onTap;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    // On phones there's no keyboard, so keep a tappable X. On the wide (web /
    // desktop) layout show the boxed `esc` key hint instead — pressing Escape is
    // how you dismiss it there — kept tappable for mouse users.
    if (mobile) {
      return Tooltip(
        message: 'esc',
        child: IconButton(
          icon: const Icon(LucideIcons.x),
          color: tokens.inkSoft,
          onPressed: onTap,
          style: ButtonStyle(
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            ),
          ),
        ),
      );
    }
    return Tooltip(
      message: 'esc',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: _KbdHint(tokens: tokens, text: 'esc'),
        ),
      ),
    );
  }
}

class _KbdHint extends StatelessWidget {
  const _KbdHint({required this.tokens, required this.text});
  final SearchTokens tokens;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: tokens.field,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tokens.hairline),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: AppTheme.fontMono,
          fontSize: 11,
          color: tokens.inkSoft,
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({
    required this.tokens,
    required this.icon,
    required this.label,
  });
  final SearchTokens tokens;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 7),
      child: Row(
        children: [
          Icon(icon, size: 13, color: tokens.inkFaint),
          const SizedBox(width: 7),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: tokens.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentsHead extends StatelessWidget {
  const _RecentsHead({
    required this.tokens,
    required this.hasItems,
    required this.onClear,
  });
  final SearchTokens tokens;
  final bool hasItems;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 7),
      child: Row(
        children: [
          Text(
            context.t('search.recent.title').toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: tokens.inkFaint,
            ),
          ),
          const Spacer(),
          if (hasItems)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClear,
              child: Text(
                context.t('search.recent.clear'),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: tokens.inkSoft,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyDeep extends StatelessWidget {
  const _EmptyDeep({
    required this.tokens,
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final SearchTokens tokens;
  final IconData? icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 44, 20, 50),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: 0.5,
            child: icon == null
                ? const HexMark(size: 40, color: AppColors.accent)
                : Icon(icon, size: 30, color: tokens.inkFaint),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: tokens.inkSoft,
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: tokens.inkFaint),
            ),
          ),
        ],
      ),
    );
  }
}

class _FootHint extends StatelessWidget {
  const _FootHint({
    required this.tokens,
    required this.caps,
    required this.label,
  });
  final SearchTokens tokens;
  final List<String> caps;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in caps) ...[
          _Cap(tokens: tokens, text: c),
          const SizedBox(width: 6),
        ],
        Text(label, style: TextStyle(fontSize: 11.5, color: tokens.inkSoft)),
      ],
    );
  }
}

class _Cap extends StatelessWidget {
  const _Cap({required this.tokens, required this.text});
  final SearchTokens tokens;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: tokens.tintStrong,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: tokens.hairline),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: AppTheme.fontMono,
          fontSize: 11,
          color: tokens.ink,
        ),
      ),
    );
  }
}

/// Pointer-tracked radial sheen, soft-light blended (§3.6). Desktop only.
class _PointerGlare extends StatefulWidget {
  const _PointerGlare({
    required this.color,
    required this.enabled,
    required this.child,
  });
  final Color color;
  final bool enabled;
  final Widget child;

  @override
  State<_PointerGlare> createState() => _PointerGlareState();
}

class _PointerGlareState extends State<_PointerGlare> {
  Offset? _pos;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return MouseRegion(
      onHover: (e) => setState(() => _pos = e.localPosition),
      onExit: (_) => setState(() => _pos = null),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pos = _pos;
          return Stack(
            children: [
              widget.child,
              if (pos != null && constraints.hasBoundedWidth)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        backgroundBlendMode: BlendMode.softLight,
                        gradient: RadialGradient(
                          center: Alignment(
                            (pos.dx / constraints.maxWidth) * 2 - 1,
                            (pos.dy / constraints.maxHeight) * 2 - 1,
                          ),
                          radius: 220 / constraints.maxWidth,
                          colors: [
                            widget.color,
                            widget.color.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 1px specular rim: bright top-left → dim → bright bottom-right at 140°.
class _RimPainter extends CustomPainter {
  _RimPainter({
    required this.radius,
    required this.edge,
    required this.edgeSoft,
  });
  final double radius;
  final Color edge;
  final Color edgeSoft;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.5),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        [edge, edgeSoft, Colors.transparent, edgeSoft],
        const [0.0, 0.28, 0.52, 1.0],
      );
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.radius != radius || old.edge != edge || old.edgeSoft != edgeSoft;
}

/// Wraps matched query substrings in a highlight background (the `<mark>`).
List<InlineSpan> _highlightSpans(
  String text,
  String query,
  TextStyle base,
  Color markBg,
) {
  final terms = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (terms.isEmpty) return [TextSpan(text: text, style: base)];
  final escaped = terms.map(RegExp.escape).join('|');
  final re = RegExp('($escaped)', caseSensitive: false);
  final spans = <InlineSpan>[];
  var last = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > last) {
      spans.add(TextSpan(text: text.substring(last, m.start), style: base));
    }
    spans.add(
      TextSpan(
        text: text.substring(m.start, m.end),
        style: base.copyWith(backgroundColor: markBg),
      ),
    );
    last = m.end;
  }
  if (last < text.length) {
    spans.add(TextSpan(text: text.substring(last), style: base));
  }
  return spans;
}
