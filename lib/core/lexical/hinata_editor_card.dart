/// The frame around the editor: the surface it is written on.
///
/// `LexicalEditorField` draws a document and nothing else — deliberately, since
/// every design system disagrees about the border, the empty state and the
/// toolbar's bar. That left hinata's editor as bare text on the page: no edge,
/// no separation from the form around it, nothing saying "this is the thing you
/// type into". This is hinata's answer, in one place, so every authoring
/// surface in the app is framed identically.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderStack;

import '../theme/app_colors.dart';
import '../widgets/glass_panel.dart';

/// The glass card an editable document sits on.
///
/// A frosted surface rather than a real [GlassContainer] lens: an editor is
/// almost always inside a glass modal already, and a second backdrop sample
/// inside the first one both costs a full-screen blur per frame and reads as
/// mud. The rim, the warm fill and the focus ring are what carry the material.
class HinataEditorCard extends StatelessWidget {
  const HinataEditorCard({
    required this.child,
    super.key,
    this.toolbar,
    this.contextBar,
    this.footer,
    this.focused = false,
    this.radius = 16,
    this.stickyRect,
  });

  /// The height of the formatting strip.
  ///
  /// Fixed, and public, because the strip is drawn twice: once as a gap that
  /// holds its place in the column, and once as the bar itself floating over
  /// the writing area while the card is scrolled past.
  static const double toolbarHeight = 42;

  /// The writing area.
  final Widget child;

  /// The formatting strip along the top, drawn on its own tinted bar.
  final Widget? toolbar;

  /// A second strip under the toolbar, shown only when it has something to say
  /// — the code block's language picker.
  final Widget? contextBar;

  /// A strip under the writing area, for a host that wants one.
  final Widget? footer;

  /// Whether the editor has focus, which lifts the rim to the accent.
  final bool focused;

  /// Where the pinned formatting strip currently is, in global coordinates.
  ///
  /// Published rather than inferred: the floating quick actions have to know
  /// what is above the words they point at, and once the strip slides it is no
  /// longer wherever the card's top happens to be.
  final ValueNotifier<Rect?>? stickyRect;

  final double radius;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    final border = BorderRadius.circular(radius);

    return GlassPanelShadow(
      radius: border,
      shadows: focused ? _focusShadow : _restShadow(dark),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: border,
          // Top-lit: a surface brighter at the top than the bottom is what
          // reads as glass rather than as a flat rectangle.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? const [Color(0xFF23222F), Color(0xFF1B1A24)]
                : const [Color(0xFFFFFFFF), Color(0xFFFBFAF6)],
          ),
          border: Border.all(
            color: focused
                ? AppColors.accent.withValues(alpha: dark ? 0.55 : 0.5)
                : AppColors.hairline,
            width: focused ? 1.4 : 1,
          ),
        ),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: border,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The strip keeps its place in the flow even while it is
                  // drawn somewhere else, so nothing below it moves when it
                  // starts sticking.
                  if (toolbar != null) const SizedBox(height: toolbarHeight),
                  if (contextBar != null) _bar(child: contextBar!),
                  child,
                  ?footer,
                ],
              ),
            ),
            if (toolbar != null)
              _StickyBar(
                radius: border,
                rect: stickyRect,
                child: _bar(child: toolbar!, opaque: true),
              ),
            // The specular rim, over the content: it is the edge of the glass,
            // and an edge drawn under what it contains is not one.
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: GlassRimPainter(
                    radius: radius,
                    edge: dark
                        ? const Color(0x24FFFFFF)
                        : const Color(0xB3FFFFFF),
                    edgeSoft: dark
                        ? const Color(0x0FFFFFFF)
                        : const Color(0x4DFFFFFF),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One strip of chrome: tinted a shade off the writing area, hairline below.
  ///
  /// [opaque] for the strip that floats: at rest it sits on the card's own
  /// fill and a translucent tint reads as a shade of it, but once it is over
  /// the writing area the words underneath show straight through. This is the
  /// one place the ink cannot solve it — the text behind is arbitrary — so the
  /// floating copy stops being a tint and becomes a surface.
  static Widget _bar({required Widget child, bool opaque = false}) =>
      DecoratedBox(
        decoration: BoxDecoration(
          color: opaque
              ? AppColors.surfaceMuted
              : AppColors.surfaceMuted.withValues(alpha: 0.7),
          border: Border(bottom: BorderSide(color: AppColors.hairline)),
        ),
        child: child,
      );

  /// The card's shadow, kept almost entirely underneath it.
  ///
  /// A wide blur with no spread reaches as far sideways as it does downwards,
  /// and the editor is laid out to the full width of the column it sits in —
  /// so everything the shadow put beyond that width was cut off dead straight
  /// by the scroll viewport, leaving a dark band down each edge. Pulling the
  /// blur in with a negative spread leaves a few pixels of horizontal reach,
  /// which no clip can catch, and keeps the weight where a card's shadow
  /// belongs: below it.
  static List<BoxShadow> _restShadow(bool dark) => [
    BoxShadow(
      color: dark ? const Color(0x59000000) : const Color(0x12231F3F),
      offset: const Offset(0, 4),
      blurRadius: 12,
      spreadRadius: -8,
    ),
  ];

  static const List<BoxShadow> _focusShadow = [
    BoxShadow(
      color: Color(0x21D9A032),
      offset: Offset(0, 3),
      blurRadius: 12,
      spreadRadius: -7,
    ),
    BoxShadow(
      color: Color(0x14231F3F),
      offset: Offset(0, 5),
      blurRadius: 14,
      spreadRadius: -8,
    ),
  ];
}

/// The formatting strip, kept on screen while the card is scrolled past.
///
/// The editor is deliberately not its own scroll view — the host is a form or
/// a sheet that scrolls, and a second viewport here would trap the gesture and
/// strand the save bar off-screen. The cost was that the strip is an ordinary
/// row in that scroll: writing past the first screenful carried every
/// formatting control away with it, and applying bold meant scrolling back up
/// to find the button and then back down to find the caret.
///
/// So it stays inside the card and slides down as the card's top passes the
/// viewport's, stopping before it reaches the bottom of the writing area — a
/// strip pinned over the last line of a field is in the way rather than to
/// hand.
///
/// Positioned rather than translated, deliberately. A translating render
/// object (Transform, AnimatedSlide, FractionalTranslation) in a hover path
/// asserts `!debugNeedsLayout` on the web every time the mouse tracker
/// hit-tests it during layout churn, and this strip is both hovered and
/// re-laid-out on every scroll frame. Moving it by parent data re-lays it out
/// instead, which is exactly what a hit-test after layout expects.
class _StickyBar extends StatefulWidget {
  const _StickyBar({required this.child, required this.radius, this.rect});

  final Widget child;

  /// Where this strip ended up, for whoever has to keep clear of it.
  final ValueNotifier<Rect?>? rect;

  /// The card's corner radius, so the pinned strip is clipped to the same
  /// edge it is drawn against.
  final BorderRadius radius;

  @override
  State<_StickyBar> createState() => _StickyBarState();
}

class _StickyBarState extends State<_StickyBar> {
  ScrollPosition? _position;
  double _offset = 0;

  /// The card and the viewport, resolved once.
  ///
  /// [_follow] is a scroll listener: it runs on every frame of every scroll,
  /// for as long as the editor is mounted. Walking the element tree for an
  /// ancestor that cannot change, and re-registering an inherited dependency,
  /// are not things to do from there.
  RenderStack? _card;
  RenderBox? _viewport;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _card = null;
    _viewport = null;
    final position = Scrollable.maybeOf(context)?.position;
    if (identical(position, _position)) return;
    _position?.removeListener(_follow);
    _position = position?..addListener(_follow);
    // The card can already be scrolled past on the first frame — a deep link
    // straight to a comment, or a rebuild while the reader is halfway down.
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
  }

  @override
  void dispose() {
    _position?.removeListener(_follow);
    widget.rect?.value = null;
    super.dispose();
  }

  /// How far the strip has to slide to stay at the top of what is visible.
  void _follow() {
    // The card, not this widget: a Positioned reports its child's box, so
    // measuring this element would measure the strip against itself and chase
    // its own offset every frame.
    if (!mounted) return;
    // Resolved on first use, not in didChangeDependencies: that runs before
    // the first layout, when the ancestor's render object does not exist yet
    // and a null would be cached for the lifetime of the widget. Neither
    // answer can change afterwards, so one successful lookup is enough.
    final card = _card ??= context.findAncestorRenderObjectOfType<RenderStack>();
    final viewport = _viewport ??= switch (_position?.context
        .storageContext
        .findRenderObject()) {
      final RenderBox box => box,
      _ => null,
    };
    if (card == null || viewport == null) return;
    if (!card.hasSize || !card.attached || !viewport.hasSize) return;

    // The card's top in the viewport's coordinates: negative once it has been
    // scrolled past, which is exactly how far the strip has to come down.
    final top = card.localToGlobal(Offset.zero, ancestor: viewport).dy;

    // Scrolled out of sight: there is nothing to pin, and nothing above the
    // words for the quick actions to keep clear of either.
    if (top > viewport.size.height || top + card.size.height < 0) {
      widget.rect?.value = null;
      return;
    }

    // Never past the writing area: the strip stops with a line's worth of text
    // still under it rather than sitting on the last one.
    final room = card.size.height - HinataEditorCard.toolbarHeight * 2;
    final next = (-top).clamp(0.0, room < 0 ? 0.0 : room);

    // One gate for both effects. The rect is in global coordinates, so its
    // origin moves on every scroll frame even while the strip is not pinned at
    // all — publishing it ungated woke the quick actions once a frame for a
    // position that had not changed relative to anything they care about.
    if ((next - _offset).abs() < 0.5) return;
    _publish(card, next);
    setState(() => _offset = next);
  }

  /// Reports the strip's own rectangle, after the frame that placed it.
  void _publish(RenderBox card, double offset) {
    final notifier = widget.rect;
    if (notifier == null) return;
    final origin = card.localToGlobal(Offset(0, offset));
    notifier.value = Rect.fromLTWH(
      origin.dx,
      origin.dy,
      card.size.width,
      HinataEditorCard.toolbarHeight,
    );
  }

  @override
  Widget build(BuildContext context) => Positioned(
    top: _offset,
    left: 0,
    right: 0,
    child: ClipRRect(
      borderRadius: _offset > 0
          ? BorderRadius.zero
          : BorderRadius.only(
              topLeft: widget.radius.topLeft,
              topRight: widget.radius.topRight,
            ),
      child: widget.child,
    ),
  );
}

/// The prompt shown over an empty document.
///
/// Over it, never in it: a placeholder that was text in the model would be
/// saved, exported, indexed and mailed out in a digest.
class HinataEditorPlaceholder extends StatelessWidget {
  const HinataEditorPlaceholder({
    required this.text,
    required this.visible,
    required this.padding,
    required this.fontSize,
    super.key,
  });

  final String text;
  final bool visible;

  /// The writing area's padding, so the prompt starts where the caret does.
  final EdgeInsetsGeometry padding;

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    // Absent rather than transparent while there is text: an invisible
    // placeholder is still read out by a screen reader and still found by find.
    if (!visible) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: IgnorePointer(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: fontSize, color: AppColors.inkFaint),
        ),
      ),
    );
  }
}
