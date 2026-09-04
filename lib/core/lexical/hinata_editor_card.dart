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
import 'package:flutter/rendering.dart' show RenderAbstractViewport;

import '../theme/app_colors.dart';
import '../widgets/glass_panel.dart';

/// The glass card an editable document sits on.
///
/// A frosted surface rather than a real [GlassContainer] lens: an editor is
/// almost always inside a glass modal already, and a second backdrop sample
/// inside the first one both costs a full-screen blur per frame and reads as
/// mud. The rim, the warm fill and the focus ring are what carry the material.
class HinataEditorCard extends StatefulWidget {
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
  /// Fixed, and public, because the strip is drawn twice: once as a gap holding
  /// its place in the column, and once as the bar itself over the writing area
  /// while the card is scrolled past.
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

  /// Where the pinned strip currently is, in global coordinates, or null while
  /// it is not pinned. The floating quick actions read it to stay clear.
  final ValueNotifier<Rect?>? stickyRect;

  final double radius;

  @override
  State<HinataEditorCard> createState() => _HinataEditorCardState();
}

class _HinataEditorCardState extends State<HinataEditorCard> {
  /// Identifies the card's own box for the pinned strip, so the measurement
  /// cannot be re-anchored by an ancestor someone introduces later.
  final GlobalKey _body = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.brightness == Brightness.dark;
    final border = BorderRadius.circular(widget.radius);

    return GlassPanelShadow(
      radius: border,
      shadows: widget.focused ? _focusShadow : _restShadow(dark),
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
        ),
        // The rim is drawn *over* the card, not behind it. The pinned
        // formatting strip is opaque and reaches both edges, so a border
        // painted underneath was covered exactly where the strip was — the
        // card lost its outline for the height of its own toolbar.
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: border,
            border: Border.all(
              color: widget.focused
                  ? AppColors.accent.withValues(alpha: dark ? 0.55 : 0.5)
                  : AppColors.hairline,
              width: widget.focused ? 1.4 : 1,
            ),
          ),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: border,
                // The strip lives *inside* the clip, so whatever it is asked to
                // do it can never be drawn outside the card's edge.
                child: Stack(
                  key: _body,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // A gap holding the strip's place, so nothing below it
                        // moves when it starts sticking.
                        if (widget.toolbar != null)
                          const SizedBox(
                            height: HinataEditorCard.toolbarHeight,
                          ),
                        if (widget.contextBar != null)
                          _bar(child: widget.contextBar!),
                        widget.child,
                        ?widget.footer,
                      ],
                    ),
                    if (widget.toolbar != null)
                      _StickyBar(
                        card: _body,
                        rect: widget.stickyRect,
                        radius: border,
                        child: _bar(child: widget.toolbar!, opaque: true),
                      ),
                  ],
                ),
              ),
              // The specular rim, over the content: it is the edge of the glass,
              // and an edge drawn under what it contains is not one.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: GlassRimPainter(
                      radius: widget.radius,
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
      ),
    );
  }

  /// One strip of chrome: tinted a shade off the writing area, hairline below.
  ///
  /// [opaque] for the strip that floats: at rest a translucent tint reads as a
  /// shade of the card's own fill, but once it is over the writing area the
  /// words underneath show straight through it.
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
/// strand the save bar off-screen. The cost is that the strip is an ordinary
/// row in the host's scroll: writing past the first screenful carried every
/// control away with it, so applying bold meant scrolling up to find the
/// button and back down to find the caret.
///
/// So it slides down as the card's top passes the viewport's, and stops before
/// it reaches the bottom of the writing area — a strip pinned over the last
/// line of a field is in the way rather than to hand.
///
/// Three things this has to get right, each of which it got wrong before:
///
///  * **It measures itself against the real viewport.** `Scrollable.of` gives
///    the scrollable's own element, whose box is not the scrolling one when
///    the host wraps it — in a sheet that was a whole chrome's worth of error,
///    and the strip ended up hovering in the middle of the text.
///  * **It reads the scroll offset, not the card's paint transform.** The
///    position notifies its listeners while the new offset is being applied,
///    a frame before anything is laid out at it, so a transform read here
///    still describes the previous scroll. On the page the error was invisible
///    because the two agreed often enough; in a sheet the strip trailed a
///    whole gesture behind and travelled *downwards* while the reader scrolled
///    up, which is what made it look like it randomly detached.
///  * **It measures the card by identity, not by type.** An ancestor lookup
///    for `RenderStack` finds whichever stack happens to be nearest, and a
///    glass overlay or a badge wrapper introduced later would silently
///    re-anchor the maths with no error anywhere.
///  * **It cannot leave the card.** It is inside the card's clip, and its
///    travel is bounded by the card's own height, so there is no scroll
///    position that detaches it from the edge it belongs to.
///
/// Positioned rather than translated: a translating render object in a hover
/// path asserts `!debugNeedsLayout` on the web whenever the mouse tracker
/// hit-tests it during layout churn, and this strip is both hovered and
/// re-laid-out on every scroll frame.
class _StickyBar extends StatefulWidget {
  const _StickyBar({
    required this.card,
    required this.child,
    required this.radius,
    this.rect,
  });

  /// The card's own box, keyed by the card itself.
  final GlobalKey card;

  /// The card's corner radius. Once the strip has slid off the card's top it
  /// *is* the top edge as far as a reader can see, so it carries the same
  /// rounded corners rather than reading as a bar laid across the page.
  final BorderRadius radius;

  final Widget child;

  /// Where this strip ended up, for whoever has to keep clear of it.
  final ValueNotifier<Rect?>? rect;

  @override
  State<_StickyBar> createState() => _StickyBarState();
}

class _StickyBarState extends State<_StickyBar> {
  ScrollPosition? _position;
  double _offset = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (identical(position, _position)) return;
    _position?.removeListener(_follow);
    _position = position?..addListener(_follow);
    // The card can already be scrolled past on the first frame — a deep link
    // straight to a comment, or a rebuild halfway down the page.
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
  }

  @override
  void dispose() {
    _position?.removeListener(_follow);
    widget.rect?.value = null;
    super.dispose();
  }

  void _follow() {
    if (!mounted) return;
    final position = _position;
    if (position == null || !position.hasPixels) return;
    final box = widget.card.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return;
    // The scrolling box itself, whatever the host wrapped it in.
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;

    // How far the card's top has gone past the viewport's, which is exactly
    // how far the strip has to come down to stay level with it.
    //
    // Read from the scroll offset against the card's place in the scroll, and
    // deliberately *not* from the card's paint transform: this runs from the
    // position's own notification, which is sent while the new offset is being
    // applied and before the frame it produces has been laid out. The paint
    // transform therefore still describes the *previous* scroll — so the strip
    // trailed a whole gesture behind, and scrolling back up moved it further
    // down. `getOffsetToReveal` is layout data about where the card sits in
    // the scrollable's content, which the current offset does not change.
    final past = position.pixels - viewport.getOffsetToReveal(box, 0).offset;

    // Bounded by the card: it stops with a line's worth of writing still
    // under it rather than sitting on the last one, and it can never travel
    // far enough to part company with the card's edge.
    final room = box.size.height - HinataEditorCard.toolbarHeight * 2;
    final next = past.clamp(0.0, room < 0 ? 0.0 : room);

    if ((next - _offset).abs() < 0.5) return;
    setState(() => _offset = next);
    // After the frame, for the same reason the offset above is not read from
    // the card's transform: here there is no layout-space equivalent to fall
    // back on, since what the quick actions need is a screen rectangle.
    WidgetsBinding.instance.addPostFrameCallback((_) => _publish());
  }

  /// Reports the strip's own rectangle, so the quick actions can avoid it.
  void _publish() {
    if (!mounted || widget.rect == null) return;
    final card = widget.card.currentContext?.findRenderObject();
    if (card is! RenderBox || !card.hasSize || !card.attached) return;
    final origin = card.localToGlobal(Offset(0, _offset));
    widget.rect!.value = Rect.fromLTWH(
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
    // Once the strip has slid off the card's own top it *is* the top edge
    // as far as a reader can see, so it carries the card's corners rather
    // than reading as a bar laid across the page.
    child: ClipRRect(
      borderRadius: BorderRadius.only(
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
