import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality, LiquidRoundedSuperellipse;

import '../theme/app_colors.dart';
import '../../features/search/search_tokens.dart';
import 'glass_panel.dart';

/// One selectable row in a [GlassPopupMenu].
class GlassMenuItem<T> {
  const GlassMenuItem({
    required this.value,
    required this.label,
    this.leading,
    this.color,
    this.dividerAbove = false,
    this.enabled = true,
    this.disabledReason,
  });

  /// The value reported back through [GlassPopupMenu.onSelected] when tapped.
  final T value;

  /// The row's text.
  final String label;

  /// Optional leading glyph/avatar shown left of the label.
  final Widget? leading;

  /// Optional label colour — e.g. a danger tint for a destructive action.
  /// Falls back to the standard ink colour when null.
  final Color? color;

  /// When true, a hairline divider is drawn above this row to separate it from
  /// the previous group (e.g. before a destructive action).
  final bool dividerAbove;

  /// When false the row is shown greyed-out and is not selectable — used for
  /// guarded actions (e.g. last-admin, SSO-managed) that should be visible but
  /// inert per the "disable, don't hide" rule.
  final bool enabled;

  /// Optional reason shown beneath a disabled row's label (the tooltip text).
  final String? disabledReason;
}

/// A reusable liquid-glass replacement for [PopupMenuButton].
///
/// Renders [child] as the tappable anchor and, on tap, opens a glass popover —
/// the same iOS-26 lens material as the global-search palette and board filter
/// (refraction + blur + specular rim, see [glass_panel.dart]). The currently
/// [value]-matched row is highlighted with a check; tapping a row reports it
/// through [onSelected] and closes the menu.
class GlassPopupMenu<T> extends StatefulWidget {
  const GlassPopupMenu({
    super.key,
    required this.items,
    required this.value,
    required this.onSelected,
    required this.child,
    this.width = 240,
    this.offset = 8,
    this.onOpenChanged,
  });

  /// The rows to show.
  final List<GlassMenuItem<T>> items;

  /// The currently selected value (highlighted in the list). May be `null`.
  final T value;

  /// Called with the tapped row's value.
  final ValueChanged<T> onSelected;

  /// The tappable anchor (e.g. a chip or button).
  final Widget child;

  /// Popover width.
  final double width;

  /// Vertical gap between the anchor and the popover.
  final double offset;

  /// Called with `true` when the menu opens and `false` when it closes.
  ///
  /// For anchors that share the screen with something floating of their own —
  /// the editor's selection overlay is the case this exists for. That overlay
  /// points at the words the menu now covers, so it has to step aside while
  /// the menu is up; nothing else can know when that is.
  final ValueChanged<bool>? onOpenChanged;

  @override
  State<GlassPopupMenu<T>> createState() => _GlassPopupMenuState<T>();
}

class _GlassPopupMenuState<T> extends State<GlassPopupMenu<T>> {
  final GlobalKey _anchorKey = GlobalKey();

  Future<void> _open() async {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final Rect anchorRect = (box != null && box.hasSize)
        ? (box.localToGlobal(Offset.zero) & box.size)
        : Rect.zero;

    // Capture the callback up-front: when this anchor lives inside a hover-gated
    // subtree (e.g. a tree row's action menu that only renders while hovered),
    // opening the dialog moves the pointer off the row, which unmounts the
    // anchor — and therefore this State — before the dialog returns. The owner
    // of [onSelected] (the parent screen) is still alive and guards its own
    // async work, so we must invoke it regardless of *our* mounted state; an
    // earlier `&& mounted` check here silently dropped the selection.
    final onSelected = widget.onSelected;
    // Captured for the same reason, and called in a `finally` for one more:
    // whatever was told to step aside has to be told to come back, including
    // when the menu is dismissed by the barrier rather than by a choice.
    final onOpenChanged = widget.onOpenChanged;
    onOpenChanged?.call(true);

    final _MenuResult<T>? selected;
    try {
      selected = await showGeneralDialog<_MenuResult<T>>(
        context: context,
        barrierDismissible: true,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, _, _) => _GlassPopupMenuDialog<T>(
          anchorRect: anchorRect,
          items: widget.items,
          value: widget.value,
          width: widget.width,
          gap: widget.offset,
        ),
        transitionBuilder: (_, _, _, child) => child,
      );
    } finally {
      onOpenChanged?.call(false);
    }

    if (selected != null) onSelected(selected.value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _open,
      behavior: HitTestBehavior.opaque,
      child: KeyedSubtree(key: _anchorKey, child: widget.child),
    );
  }
}

/// Wrapper so a `null` selection still distinguishes "picked null" from
/// "dismissed" (which returns `null` from the dialog).
class _MenuResult<T> {
  const _MenuResult(this.value);
  final T value;
}

class _GlassPopupMenuDialog<T> extends StatelessWidget {
  const _GlassPopupMenuDialog({
    required this.anchorRect,
    required this.items,
    required this.value,
    required this.width,
    required this.gap,
  });

  final Rect anchorRect;
  final List<GlassMenuItem<T>> items;
  final T value;
  final double width;
  final double gap;

  static const double _margin = 12;
  static const double _radius = 18;

  @override
  Widget build(BuildContext context) {
    final tokens = SearchTokens.of(Theme.of(context).brightness);
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final anim = ModalRoute.of(context)!.animation!;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final panelWidth = math.min(width, size.width - _margin * 2);

    // Prefer aligning the popover's left edge to the anchor; clamp on-screen.
    double left = anchorRect.left;
    left = left.clamp(
      _margin,
      math.max(_margin, size.width - panelWidth - _margin),
    );

    final belowTop = anchorRect.bottom + gap;
    final roomBelow = size.height - belowTop - _margin - pad.bottom;
    final roomAbove = anchorRect.top - gap - _margin - pad.top;
    final placeAbove = roomBelow < 200 && roomAbove > roomBelow;
    final maxHeight = (placeAbove ? roomAbove : roomBelow).clamp(140.0, 480.0);
    final top = placeAbove ? null : belowTop;
    final bottom = placeAbove ? (size.height - anchorRect.top + gap) : null;

    final panel = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: panelWidth, maxHeight: maxHeight),
      child: GlassPanelShadow(
        radius: BorderRadius.circular(_radius),
        shadows: tokens.panelShadow,
        child: _glassPanel(context, tokens),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          bottom: bottom,
          width: panelWidth,
          child: AnimatedBuilder(
            animation: anim,
            builder: (_, child) {
              if (reduceMotion) {
                return Opacity(opacity: anim.value, child: child);
              }
              final t = const Cubic(
                0.34,
                1.3,
                0.64,
                1,
              ).transform(anim.value.clamp(0.0, 1.0));
              return Opacity(
                opacity: (anim.value / 0.6).clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.92 + 0.08 * t,
                  alignment: placeAbove
                      ? Alignment.bottomLeft
                      : Alignment.topLeft,
                  child: child,
                ),
              );
            },
            child: panel,
          ),
        ),
      ],
    );
  }

  Widget _glassPanel(BuildContext context, SearchTokens tokens) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final content = Stack(
      children: [
        Material(
          type: MaterialType.transparency,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            shrinkWrap: true,
            itemCount: items.length,
            itemBuilder: (_, i) {
              final item = items[i];
              final row = _MenuRow<T>(
                tokens: tokens,
                item: item,
                selected: item.value == value,
                onTap: item.enabled
                    ? () =>
                          Navigator.of(context).pop(_MenuResult<T>(item.value))
                    : null,
              );
              if (!item.dividerAbove) return row;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 5,
                    ),
                    color: tokens.hairline,
                  ),
                  row,
                ],
              );
            },
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _RimPainter(
                radius: _radius,
                edge: tokens.edge,
                edgeSoft: tokens.edgeSoft,
              ),
            ),
          ),
        ),
      ],
    );
    return GlassContainer(
      useOwnLayer: true,
      quality: GlassQuality.premium,
      clipBehavior: Clip.antiAlias,
      shape: const LiquidRoundedSuperellipse(borderRadius: _radius),
      settings: liquidGlassPanelSettings(
        glassFill: tokens.glassFill,
        dark: dark,
      ),
      child: content,
    );
  }
}

class _MenuRow<T> extends StatefulWidget {
  const _MenuRow({
    required this.tokens,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final SearchTokens tokens;
  final GlassMenuItem<T> item;
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<_MenuRow<T>> createState() => _MenuRowState<T>();
}

class _MenuRowState<T> extends State<_MenuRow<T>> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final disabled = !widget.item.enabled;
    final ink = disabled
        ? (widget.item.color ?? t.ink).withValues(alpha: 0.4)
        : (widget.item.color ?? t.ink);
    final row = GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: widget.selected
              ? t.selTint
              : (_hover && !disabled ? t.rowHover : Colors.transparent),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            if (widget.item.leading != null) ...[
              SizedBox(
                width: 22,
                child: Center(
                  child: Opacity(
                    opacity: disabled ? 0.4 : 1,
                    child: widget.item.leading,
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                  if (disabled && widget.item.disabledReason != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        widget.item.disabledReason!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: t.ink.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.selected) ...[
              const SizedBox(width: 8),
              const Icon(
                LucideIcons.check,
                size: 17,
                color: AppColors.accentStrong,
              ),
            ],
          ],
        ),
      ),
    );
    if (disabled) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: row,
    );
  }
}

/// 1px specular rim — matches the global-search / board-filter panels.
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
