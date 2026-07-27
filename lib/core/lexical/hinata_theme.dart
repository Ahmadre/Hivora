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

/// Accent, icon and label for one callout flavour.
///
/// The kinds are content, not decoration — a warning and a tip mean different
/// things — so each gets its own hue rather than a shared "aside" box.
class CalloutStyle {
  const CalloutStyle(this.hue, this.icon, this.labelKey);

  /// Hue driving the tint, border and icon, so the four stay a family.
  final double hue;

  /// Lucide glyph. The app uses Lucide exclusively.
  final IconData icon;

  /// i18n key for the flavour's name.
  final String labelKey;

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
  CalloutKind.info: CalloutStyle(211, LucideIcons.info, 'kb.callout.info'),
  CalloutKind.warn: CalloutStyle(
    28,
    LucideIcons.triangleAlert,
    'kb.callout.warn',
  ),
  CalloutKind.note: CalloutStyle(
    268,
    LucideIcons.notebookPen,
    'kb.callout.note',
  ),
  CalloutKind.tip: CalloutStyle(152, LucideIcons.lightbulb, 'kb.callout.tip'),
};

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

/// The document theme: hinata's type scale and colours over Lexical's defaults.
///
/// [fontSize] sets the body size everything else scales from — a comment reads
/// at a smaller size than a knowledge-base article, and every heading, code
/// block and callout follows it rather than being re-specified per surface.
LexicalTheme hinataLexicalTheme({
  double fontSize = 15,
  Map<String, BlockLayoutBuilder> extraLayouts = const {},
}) {
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
    blockSpacing: fontSize * 0.75,
    monospaceFamily: AppTheme.fontMono,
  );

  return LexicalTheme(
    baseTextStyle: theme.baseTextStyle,
    textFormatStyles: theme.textFormatStyles,
    blockStyles: {
      ...theme.blockStyles,
      // Callouts are hinata's own block, so the bundle has no style for them.
      // The flavour tint is drawn by the block layout (the style is resolved by
      // node type, and there are four kinds of one type), so this carries only
      // the metrics they share.
      'callout': BlockStyle(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        spacing: fontSize * 0.9,
      ),
      'horizontalrule': BlockStyle(spacing: fontSize * 1.2),
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
