/// The attachment grid is a proportion, not a table of device sizes: whatever
/// space it is handed, a tile stays between two golden steps (144 → 233) and
/// keeps its preview-over-caption split. These pin that down at the widths the
/// app actually renders it in.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/responsive/responsive.dart';
import 'package:hinata/features/issues/attachments/attachment_grid.dart';

void main() {
  const min = AttachmentGrid.minTile;
  const max = AttachmentGrid.maxTile;
  const phi = Breakpoints.phi;

  test('a phone gets two readable tiles, never three slivers', () {
    // A 393pt phone's issue page, minus the page gutter and the card's padding.
    final grid = AttachmentGrid.metrics(345);

    expect(grid.columns, 2);
    expect(grid.tile, greaterThanOrEqualTo(min));
    // What this replaced: three columns in the same space left ~106pt per
    // tile — a file name reduced to "image_picke…".
    expect((345 - 2 * AttachmentGrid.gap) / 3, lessThan(min));
  });

  test('wider surfaces add columns instead of stretching tiles', () {
    final tablet = AttachmentGrid.metrics(610); // φ column
    final detail = AttachmentGrid.metrics(800); // desktop detail pane
    final wide = AttachmentGrid.metrics(Breakpoints.readingWidth);

    expect(tablet.columns, greaterThan(AttachmentGrid.metrics(345).columns));
    expect(detail.columns, greaterThanOrEqualTo(tablet.columns));
    expect(wide.columns, greaterThan(detail.columns));
    for (final grid in [tablet, detail, wide]) {
      expect(grid.tile, inInclusiveRange(min, max));
    }
  });

  test('every width keeps a tile inside its two golden steps', () {
    for (var width = 301.0; width <= 2000; width += 1) {
      final grid = AttachmentGrid.metrics(width);
      expect(
        grid.tile,
        inInclusiveRange(min - 0.01, max + 0.01),
        reason: 'tile ${grid.tile} at width $width',
      );
      // The row fills the space exactly — no dead strip on the right.
      expect(
        grid.columns * grid.tile + (grid.columns - 1) * AttachmentGrid.gap,
        closeTo(width, 0.01),
      );
    }
  });

  test('too narrow to split honours the floor and shows one tile', () {
    // Two tiles at the floor need 144 + 13 + 144 = 301. Below that, splitting
    // would produce exactly the squeeze the floor exists to prevent.
    expect(AttachmentGrid.metrics(300).columns, 1);
    expect(AttachmentGrid.metrics(301).columns, 2);
  });

  test('the smallest tile is a golden stack: preview 89 over caption 55', () {
    final grid = AttachmentGrid.metrics(min);

    expect(grid.columns, 1);
    expect(grid.tile, min);
    // w/φ + w/φ² == w — the tile is as tall as it is wide.
    expect(grid.extent, closeTo(min, 0.5));
    expect(min / phi, closeTo(89, 0.5));
    expect(min / (phi * phi), closeTo(55, 0.5));
  });

  test('a caption that has to hold larger type gets the room for it', () {
    final normal = AttachmentGrid.metrics(345);
    final large = AttachmentGrid.metrics(345, textScale: 2);

    expect(large.columns, normal.columns);
    expect(large.tile, normal.tile);
    expect(large.extent, greaterThan(normal.extent));
    // The caption keeps its two lines: the preview is unchanged, so the whole
    // growth went below it.
    expect(
      large.extent - normal.extent,
      closeTo(AttachmentGrid.minCaption * 2 - normal.tile / (phi * phi), 0.01),
    );
  });

  test('survives a grid that has not been laid out yet', () {
    final grid = AttachmentGrid.metrics(double.infinity);

    expect(grid.columns, 1);
    expect(grid.tile, max);
    expect(grid.extent.isFinite, isTrue);
  });

  group('golden columns', () {
    test('never returns less than one column', () {
      for (final width in [0.0, -50.0, 1.0, 143.0, double.nan]) {
        expect(
          Breakpoints.goldenColumns(width, min: min, max: max, gap: 13),
          1,
          reason: 'width $width',
        );
      }
    });

    test('is the same rule at any tile size', () {
      // Nothing about it is attachment-specific — a 320/520 card grid divides
      // the same way.
      expect(Breakpoints.goldenColumns(1100, min: 320, max: 520, gap: 16), 3);
      expect(Breakpoints.goldenColumns(700, min: 320, max: 520, gap: 16), 2);
      expect(Breakpoints.goldenColumns(500, min: 320, max: 520, gap: 16), 1);
    });
  });
}
