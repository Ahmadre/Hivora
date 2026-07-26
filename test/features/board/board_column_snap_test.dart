import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/board/board_drag.dart';

/// A board column is a fixed 300 px, so on a phone the wall shows one column
/// and a sliver of the next. Left to scroll freely it comes to rest wherever
/// the finger happened to lift, and the user has to re-aim before they can read
/// a column — so on compact widths the wall snaps to its own column grid.
void main() {
  const columnWidth = 300.0;
  const gap = 16.0;
  const stride = columnWidth + gap;

  /// How far [offset] sits from the nearest column boundary.
  double offGrid(double offset) {
    final rest = offset % stride;
    return math.min(rest, stride - rest);
  }

  late ScrollController controller;

  /// The Kanban wall in miniature: same column width, gap and gutters, so the
  /// snap grid under test is the one the board actually lays out.
  Widget wall({double? snap}) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: BoardDragScroller(
        snapStride: snap,
        builder: (context, _, horizontal) {
          controller = horizontal;
          return ListView.separated(
            controller: horizontal,
            scrollDirection: Axis.horizontal,
            physics: BoardColumnSnapPhysics.maybe(snap),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 6,
            separatorBuilder: (_, _) => const SizedBox(width: gap),
            itemBuilder: (context, i) =>
                SizedBox(width: columnWidth, child: Text('Column $i')),
          );
        },
      ),
    ),
  );

  /// A phone: below the compact breakpoint, where no second column ever fits.
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(393 * 2, 852 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  tearDown(boardDrag.end);

  group('boardSnapStride', () {
    Future<double?> strideAt(WidgetTester tester, double width) async {
      double? stride;
      tester.view.physicalSize = Size(width * 2, 852 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              stride = boardSnapStride(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return stride;
    }

    testWidgets('grids the wall on a phone', (tester) async {
      expect(await strideAt(tester, 393), stride);
    });

    testWidgets('leaves a wall that shows several columns alone', (
      tester,
    ) async {
      // Resting between columns only reads as a mistake while barely one of
      // them fits; where four are side by side it is a fine place to be.
      expect(await strideAt(tester, 1280), isNull);
    });
  });

  group('BoardColumnSnapPhysics', () {
    testWidgets('a flick comes to rest on a column boundary', (tester) async {
      phone(tester);
      await tester.pumpWidget(wall(snap: stride));

      await tester.fling(find.byType(ListView), const Offset(-200, 0), 800);
      await tester.pumpAndSettle();

      expect(controller.offset, greaterThan(0));
      expect(offGrid(controller.offset), lessThan(0.5));
    });

    testWidgets('a short drag falls back to the column it came from', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(wall(snap: stride));

      // Released well short of half a column and without a flick — committing
      // to the neighbour here would move the board against the user's intent.
      await tester.drag(find.byType(ListView), const Offset(-100, 0));
      await tester.pumpAndSettle();

      expect(controller.offset, 0);
    });

    testWidgets('a wall without a grid keeps the offset it was left at', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(wall());

      await tester.drag(find.byType(ListView), const Offset(-100, 0));
      await tester.pumpAndSettle();

      expect(controller.offset, greaterThan(0));
      expect(offGrid(controller.offset), greaterThan(1));
    });
  });

  group('BoardDragScroller', () {
    testWidgets('settles back onto the grid after carrying a card past the '
        'edge', (tester) async {
      phone(tester);
      await tester.pumpWidget(wall(snap: stride));

      // Park a carried card inside the right edge margin — the auto-scroll
      // jumps the wall frame by frame, which no ballistic simulation sees.
      boardDrag.start(const Size(280, 100), Offset.zero);
      boardDrag.move(Offset.zero, const Offset(388, 400));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final carried = controller.offset;
      expect(carried, greaterThan(0));
      expect(offGrid(carried), greaterThan(1));

      boardDrag.end();
      await tester.pumpAndSettle();

      expect(offGrid(controller.offset), lessThan(0.5));
    });
  });
}
