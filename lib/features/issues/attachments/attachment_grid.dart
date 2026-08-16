import 'dart:math' as math;

import '../../../core/responsive/responsive.dart';

/// Geometry of the attachment grid, in one place because it is a *proportion*,
/// not a set of sizes: the tile is a golden rectangle stack — a preview of
/// height `w/φ` above a caption of `w/φ²`, which together make the tile as tall
/// as it is wide. In Fibonacci terms the whole grid is 233 = 144 + 89 and
/// 144 = 89 + 55, which is why the numbers below are Fibonacci numbers rather
/// than round ones.
abstract final class AttachmentGrid {
  /// Narrowest a tile may get before its file name stops being a file name.
  /// A phone reaches exactly two of these; three was the squeeze this replaces.
  static const double minTile = 144;

  /// Widest a tile may get before a wall of previews turns into billboards.
  /// One golden step above [minTile] (144 · φ ≈ 233).
  static const double maxTile = 233;

  /// Gap between tiles, the Fibonacci step below the tile's own caption inset.
  static const double gap = 13;

  /// Floor for the caption, so two lines of type still fit in the smallest
  /// tile — and, scaled by the reader's text size, in any tile.
  static const double minCaption = 55;

  /// Aspect ratio of a tile's preview: the golden rectangle.
  static double get previewRatio => Breakpoints.phi;

  /// The grid that fills [width], with captions scaled by [textScale] (pass
  /// the reader's text scale factor — a caption that clips at 200 % type is
  /// exactly as broken as one that clips at 100 %).
  static ({int columns, double tile, double extent}) metrics(
    double width, {
    double textScale = 1,
  }) {
    if (!width.isFinite) {
      return (
        columns: 1,
        tile: maxTile,
        extent: maxTile / previewRatio + minCaption * textScale,
      );
    }
    final columns = Breakpoints.goldenColumns(
      width,
      min: minTile,
      max: maxTile,
      gap: gap,
    );
    final tile = math.max(1.0, (width - (columns - 1) * gap) / columns);
    // Caption keeps its golden share of the tile unless the type needs more.
    final caption = math.max(
      tile / (Breakpoints.phi * Breakpoints.phi),
      minCaption * textScale,
    );
    return (
      columns: columns,
      tile: tile,
      extent: tile / previewRatio + caption,
    );
  }
}
