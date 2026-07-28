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
  });

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
                  if (toolbar != null) _bar(child: toolbar!),
                  if (contextBar != null) _bar(child: contextBar!),
                  child,
                  ?footer,
                ],
              ),
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
  static Widget _bar({required Widget child}) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted.withValues(alpha: 0.7),
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
