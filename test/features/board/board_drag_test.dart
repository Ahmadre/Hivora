import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/board/board_drag.dart';

/// The drag choreography shared by the Kanban board and the Scrum surface:
/// a card lifts and sways while carried, leaves a socket behind, opens a slot
/// in the column it hovers and settles in once at its new home.
void main() {
  Issue issue(String id) => Issue(
    id: id,
    projectId: 'p1',
    readableId: 'HIN-$id',
    title: 'Issue $id',
    state: 'TODO',
  );

  Widget host(Widget child) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(child: SizedBox(width: 300, child: child)),
    ),
  );

  Widget card(String label) => SizedBox(
    height: 80,
    child: ColoredBox(color: const Color(0xFFFFFFFF), child: Text(label)),
  );

  /// The sway currently applied to the carried card, read off the transform
  /// that turns around the carry pivot (its sibling scale contributes no angle,
  /// and unrelated app-level transforms use other pivots).
  double tiltOf(WidgetTester tester) {
    var largest = 0.0;
    for (final transform in tester.widgetList<Transform>(
      find.byType(Transform),
    )) {
      if (transform.alignment != BoardDragMotion.carryPivot) continue;
      final storage = transform.transform.storage;
      final angle = math.atan2(storage[1], storage[0]);
      if (angle.abs() > largest.abs()) largest = angle;
    }
    return largest;
  }

  tearDown(boardDrag.end);

  group('BoardDragCard', () {
    testWidgets('carries the card and leaves a socket behind', (tester) async {
      await tester.pumpWidget(
        host(
          BoardDragCard(
            issue: issue('1'),
            ghost: card('ghost'),
            child: card('card'),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('card')),
      );
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();

      // The carried copy and the socket both render the ghost, and the drag has
      // published the card's own height for the target slot to open to.
      expect(find.text('ghost'), findsNWidgets(2));
      expect(find.text('card'), findsNothing);
      expect(boardDrag.isDragging, isTrue);
      expect(boardDrag.cardHeight, 80);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(boardDrag.isDragging, isFalse);
      expect(find.text('card'), findsOneWidget);
    });

    testWidgets('sways into the direction of travel and settles back', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          BoardDragCard(
            issue: issue('1'),
            ghost: card('ghost'),
            child: card('card'),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('card')),
      );

      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      // Brisk rightward travel leans the card right — never past the cap.
      final swung = tiltOf(tester);
      expect(swung, greaterThan(0.005));
      expect(swung, lessThanOrEqualTo(BoardDragMotion.maxTilt + 1e-6));

      // Parked, it swings back level instead of staying tilted.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tiltOf(tester).abs(), lessThan(0.005));

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('renders the card untouched when dragging is disabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          BoardDragCard(
            issue: issue('1'),
            enabled: false,
            ghost: card('ghost'),
            child: card('card'),
          ),
        ),
      );

      expect(find.byType(Draggable<Issue>), findsNothing);
      expect(find.text('card'), findsOneWidget);
    });
  });

  group('BoardDropSlot', () {
    testWidgets('opens to the dragged card height and closes again', (
      tester,
    ) async {
      boardDrag.start(const Size(276, 120), Offset.zero);
      await tester.pumpWidget(
        host(const BoardDropSlot(open: true, hasCards: false)),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(BoardDropSlot)).height, 120);

      await tester.pumpWidget(
        host(const BoardDropSlot(open: false, hasCards: false)),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(BoardDropSlot)).height, 0);
    });
  });

  group('BoardLandingCard', () {
    testWidgets('plays once for the dropped card, not for its neighbours', (
      tester,
    ) async {
      boardDrag.land('1');
      await tester.pumpWidget(
        host(
          Column(
            children: [
              BoardLandingCard(
                issueId: '1',
                accent: const Color(0xFFD9A032),
                child: card('landed'),
              ),
              BoardLandingCard(
                issueId: '2',
                accent: const Color(0xFFD9A032),
                child: card('other'),
              ),
            ],
          ),
        ),
      );

      Finder transformIn(String label) => find.descendant(
        of: find.ancestor(
          of: find.text(label),
          matching: find.byType(BoardLandingCard),
        ),
        matching: find.byType(Transform),
      );

      // Mid-flight the dropped card is scaled out of its slot; the untouched
      // neighbour adds no transform at all.
      await tester.pump(const Duration(milliseconds: 100));
      expect(transformIn('landed'), findsOneWidget);
      expect(transformIn('other'), findsNothing);

      // The landing is consumed, so a later rebuild doesn't replay it.
      expect(boardDrag.landedId, isNull);
      await tester.pumpAndSettle();
      expect(transformIn('landed'), findsNothing);
    });
  });
}
