/// Lexical, wearing hinata's design tokens.
library;

import 'package:flutter/widgets.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'callout_node.dart';

/// Whether the app is currently in dark mode. Read per call: the neutral
/// tokens are theme-aware getters, so a cached answer goes stale on a switch.
bool get _dark => AppColors.brightness == Brightness.dark;

/// Accent and icon for one callout flavour.
///
/// The kinds are content, not decoration — a warning and a tip mean different
/// things — so each gets its own hue rather than a shared "aside" box. The
/// flavour is carried by the hue and the glyph and nothing else: a printed
/// label is a design decision nobody has asked for, and the key one used to
/// name did not exist in either locale.
class CalloutStyle {
  const CalloutStyle(this.hue, this.icon);

  /// Hue driving the tint, border and icon, so the four stay a family.
  final double hue;

  /// Lucide glyph. The app uses Lucide exclusively.
  final IconData icon;

  /// The flavour's accent at full strength.
  Color get accent => HSLColor.fromAHSL(
    1,
    hue,
    _dark ? 0.55 : 0.62,
    _dark ? 0.66 : 0.44,
  ).toColor();

  /// The tint behind the block.
  Color get fill => accent.withValues(alpha: _dark ? 0.13 : 0.08);

  /// The block's left rule.
  Color get rule => accent.withValues(alpha: 0.55);
}

/// The four callout flavours, styled.
const Map<CalloutKind, CalloutStyle> calloutStyles = {
  CalloutKind.info: CalloutStyle(211, LucideIcons.info),
  CalloutKind.warn: CalloutStyle(28, LucideIcons.triangleAlert),
  CalloutKind.note: CalloutStyle(268, LucideIcons.notebookPen),
  CalloutKind.tip: CalloutStyle(152, LucideIcons.lightbulb),
};

/// The selection chrome around an editable image, in hinata's accent.
///
/// The bundle's own is a blue borrowed from nothing in this product, and the
/// handles are the most visible thing about editing an image — so they get the
/// honey accent, a rounded square rather than a hard one, and a shadow, because
/// a 10-pixel dot has to stay findable over a screenshot of anything.
LexicalImageStyle hinataImageStyle() => LexicalImageStyle(
  accent: AppColors.accent,
  handleFill: AppColors.accentStrong,
  handleBorder: _dark ? const Color(0xFF1C1B25) : const Color(0xFFFFFFFF),
  handleSize: 11,
  handleRadius: 3.5,
  outlineWidth: 1.5,
  handleShadows: const [
    BoxShadow(color: Color(0x33231F3F), blurRadius: 4, offset: Offset(0, 1)),
  ],
);

/// The palette Lexical draws with, taken from the app's theme tokens.
///
/// Read at call time rather than held in a `const`: the neutral tokens are
/// theme-aware getters, so a cached palette would keep the light colours after
/// a switch to dark.
LexicalPalette hinataPalette() => LexicalPalette(
  text: AppColors.ink,
  muted: AppColors.inkSoft,
  accent: AppColors.accent,
  surface: AppColors.surfaceMuted,
  border: AppColors.hairline,
  highlight: AppColors.accentSoft.withValues(alpha: 0.5),
);

/// Default space below each top-level block, derived from the body size.
///
/// The renderer pads *below* every block, including the last, so a surface with
/// little room — a comment row, where that padding reads as a gap before the
/// reactions — passes a smaller value rather than trying to claw it back with
/// negative padding, which Flutter refuses outright.
double hinataBlockSpacing(double fontSize) => fontSize * 0.75;

/// The document theme: hinata's type scale and colours over Lexical's defaults.
///
/// [fontSize] sets the body size everything else scales from — a comment reads
/// at a smaller size than a knowledge-base article, and every heading, code
/// block and callout follows it rather than being re-specified per surface.
LexicalTheme hinataLexicalTheme({
  double fontSize = 15,
  double? blockSpacing,
  Map<String, BlockLayoutBuilder> extraLayouts = const {},
}) {
  final spacing = blockSpacing ?? hinataBlockSpacing(fontSize);
  final palette = hinataPalette();
  final base = TextStyle(
    fontFamily: AppTheme.fontUi,
    fontSize: fontSize,
    height: 1.68,
    color: AppColors.ink,
  );

  final theme = defaultLexicalTheme(
    baseTextStyle: base,
    palette: palette,
    blockSpacing: spacing,
    monospaceFamily: AppTheme.fontMono,
  );

  return LexicalTheme(
    baseTextStyle: theme.baseTextStyle,
    textFormatStyles: theme.textFormatStyles,
    blockStyles: {
      ...theme.blockStyles,
      // Callouts are hinata's own block, so the bundle has no style for them.
      // The flavour tint is drawn by the block layout (the style is resolved by
      // node type, and there are four kinds of one type), and so is the inset —
      // the padding belongs *inside* the tinted box, and declaring it here too
      // stacked the two into an inset twice as deep as either asked for.
      'callout': BlockStyle(spacing: spacing * 1.2),
      'horizontalrule': BlockStyle(spacing: spacing * 1.6),
    },
    blockStyleResolver: theme.blockStyleResolver,
    textStyleResolver: theme.textStyleResolver,
    markerBuilders: theme.markerBuilders,
    blockLayouts: {...theme.blockLayouts, ...extraLayouts},
    tokenBuilders: theme.tokenBuilders,
    styleResolver: theme.styleResolver,
    defaultBlockStyle: theme.defaultBlockStyle,
    linkStyle: theme.linkStyle,
    codeTextStyle: theme.codeTextStyle,
    selectionColor: theme.selectionColor,
    caretColor: theme.caretColor,
    caretWidth: theme.caretWidth,
  );
}
