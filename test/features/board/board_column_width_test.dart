import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/responsive/responsive.dart';
import 'package:hinata/features/board/board_drag.dart';

/// A board is meant to be taken in at once, so a wall with room to spare gives
/// up column width to show every column instead of hiding the last ones behind
/// a sideways scroll. Two ways that trade stops paying off, and both fall back
/// to the design width.
void main() {
  const design = BoardWall.columnWidth;
  const gap = BoardWall.columnGap;

  /// What [count] columns of [width] occupy, gaps included.
  double wall(double width, int count) => count * width + (count - 1) * gap;

  test('keeps the design width where the whole wall already fits', () {
    // Five columns in a 1618-wide body: nothing to gain from stretching them.
    expect(boardColumnWidth(1586, 5), design);
    expect(boardColumnWidth(4000, 3), design);
  });

  test('shrinks columns so a wall that nearly fits fits completely', () {
    // A 1728-wide laptop minus rail and gutters — five columns at the design
    // width overflow by ~110px, which is exactly the case worth rescuing.
    const available = 1452.0;
    final width = boardColumnWidth(available, 5);

    expect(width, lessThan(design));
    expect(width, greaterThanOrEqualTo(BoardWall.minColumnWidth));
    expect(wall(width, 5), closeTo(available, 0.01));
  });

  test('stops shrinking where the columns would get unreadable', () {
    // Seven columns in the same space would need ~194px each. Squeezing there
    // buys nothing: the cards get harder to read and the wall still scrolls.
    expect(boardColumnWidth(1452, 7), design);
  });

  test('leaves a phone exactly as it was', () {
    // One column plus a sliver — the fitted width is far below the floor, so
    // the wall keeps the design width and scrolls (and snaps, see
    // board_column_snap_test.dart).
    expect(boardColumnWidth(361, 5), design);
    expect(boardColumnWidth(361, 2), design);
  });

  test('survives a wall that has not been laid out yet', () {
    expect(boardColumnWidth(double.infinity, 4), design);
    expect(boardColumnWidth(800, 0), design);
  });

  test('breaks out of the reading width exactly when it has to', () {
    // A board only leaves the reading width once its wall stops fitting inside
    // it — the threshold is a plain number in the code, so pin it to the
    // geometry it was derived from. Change a column width or the reading width
    // and this is what says the number went stale.
    const fits = BoardWall.columnsPerReadingWidth;

    expect(wall(design, fits), lessThan(Breakpoints.readingWidth));
    expect(wall(design, fits + 1), greaterThan(Breakpoints.readingWidth));
  });

  test('carries a card narrower than the column it came from', () {
    // The carried copy reads as detached because it is inset on both sides —
    // which only holds while it follows a column that had to shrink.
    expect(BoardWall.carryInset, greaterThan(0));
    expect(BoardWall.minColumnWidth - BoardWall.carryInset, greaterThan(200));
  });
}
