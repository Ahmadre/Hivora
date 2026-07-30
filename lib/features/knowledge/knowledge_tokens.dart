import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/hue_colors.dart';

/// KB-specific design tokens, ported 1:1 from `knowledge.css` (§2 of the
/// integration spec). Geometry, type and colour. Colour helpers stay faithful
/// to the oklch values in light mode and degrade to translucent washes in dark
/// mode (a flat near-white fill would glow on a dark surface).
abstract final class KbTokens {
  // ── geometry ──
  static const double radiusCard = 14;
  static const double radiusControl = 10;
  static const double radiusChip = 6;
  static const double readerMaxWidth = 760;
  static const double treeWidth = 248;
  static const double asideWidth = 232;
  static const double asideGap = 36;

  // ── responsive breakpoints (rendered container width) ──
  static const double bpWide = 1080; // tree │ reader │ aside
  static const double bpMid = 720; //  tree │ reader (aside drops)
  static const double bpPhone = 610; // grids → 1 col, sheets full-bleed
  static const double editorSplit = 760; // split ⇄ Write/Preview tabs

  static bool get _dark => AppColors.brightness == Brightness.dark;

  // ── accent (article chip / link) ──
  static Color get accent => AppColors.accentStrong; // honey-amber

  // ── inline code: oklch(0.5 0.12 320) on surface-mut ──
  static Color get inlineCode =>
      _dark ? oklch(0.78, 0.10, 320) : oklch(0.5, 0.12, 320);
  static Color get inlineCodeBg => AppColors.surfaceMuted;

  // ── code block: bg #1E1C3A, ink #E7E5F5 ──
  static const Color codeBlockBg = Color(0xFF1E1C3A);
  static const Color codeBlockInk = Color(0xFFE7E5F5);
  static const Color codeBlockFaint = Color(0xFF9C99C4);

  // ── space chip: text oklch(0.5 0.1 H) on oklch(0.95 0.04 H) ──
  static Color spaceChipText(int hue) => _dark
      ? oklch(0.82, 0.08, hue.toDouble())
      : oklch(0.5, 0.10, hue.toDouble());
  static Color spaceChipBg(int hue) => _dark
      ? oklch(0.60, 0.14, hue.toDouble()).withValues(alpha: 0.20)
      : oklch(0.95, 0.04, hue.toDouble());

  // ── callouts ──
  static Color calloutBg(String kind) {
    if (_dark) return _calloutHue(kind).withValues(alpha: 0.13);
    switch (kind) {
      case 'warn':
        return oklch(0.96, 0.05, 65);
      case 'tip':
        return oklch(0.96, 0.04, 155);
      case 'note':
        return oklch(0.96, 0.02, 255);
      case 'info':
      default:
        return oklch(0.96, 0.03, 250);
    }
  }

  static Color calloutBorder(String kind) {
    if (_dark) return _calloutHue(kind).withValues(alpha: 0.40);
    switch (kind) {
      case 'warn':
        return oklch(0.85, 0.09, 65);
      case 'tip':
        return oklch(0.84, 0.07, 155);
      case 'note':
        return oklch(0.86, 0.04, 255);
      case 'info':
      default:
        return oklch(0.86, 0.06, 250);
    }
  }

  static Color calloutInk(String kind) => _dark
      ? oklch(0.84, 0.08, _calloutHueDeg(kind))
      : oklch(0.45, 0.10, _calloutHueDeg(kind));

  static Color _calloutHue(String kind) =>
      oklch(0.60, 0.13, _calloutHueDeg(kind));

  static double _calloutHueDeg(String kind) {
    switch (kind) {
      case 'warn':
        return 65;
      case 'tip':
        return 155;
      case 'note':
        return 255;
      case 'info':
      default:
        return 250;
    }
  }

  static String calloutIcon(String kind) {
    switch (kind) {
      case 'warn':
        return 'triangle-alert';
      case 'note':
        return 'pencil';
      case 'tip':
        return 'lightbulb';
      case 'info':
      default:
        return 'info';
    }
  }

  // ── issue / state tints ──
  static Color issueChipColor(int typeHue) =>
      oklch(0.55, 0.14, typeHue.toDouble());
  static Color stateInk(int hue) => oklch(0.5, 0.13, hue.toDouble());
  static Color stateDot(int hue) => oklch(0.55, 0.13, hue.toDouble());
}
