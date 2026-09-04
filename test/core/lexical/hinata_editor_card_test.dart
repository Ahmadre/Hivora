/// The card's pinned formatting strip.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/lexical/hinata_editor_card.dart';

void main() {
  const toolbar = Key('toolbar');

  /// A card in the middle of a page, with room to scroll on either side.
  ///
  /// Deliberately a sliver viewport, and a shrink-wrapping one at that: it is
  /// what the issue sheet builds, and it is the only kind that can be caught
  /// out here. A `SingleChildScrollView` derives its paint transform from
  /// `offset.pixels` on the spot, so it is never a frame behind and would
  /// quietly pass a card that reads the scroll position wrongly.
  Future<ScrollController> pumpCard(WidgetTester tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: controller,
            shrinkWrap: true,
            children: const [
              SizedBox(height: 400),
              HinataEditorCard(
                toolbar: SizedBox(
                  key: toolbar,
                  height: HinataEditorCard.toolbarHeight,
                ),
                child: SizedBox(height: 1200),
              ),
              SizedBox(height: 900),
            ],
          ),
        ),
      ),
    );
    return controller;
  }

  group('the pinned formatting strip', () {
    testWidgets('rests on the card while the card is fully in view', (
      tester,
    ) async {
      await pumpCard(tester);
      expect(
        tester.getTopLeft(find.byKey(toolbar)).dy,
        closeTo(tester.getTopLeft(find.byType(HinataEditorCard)).dy, 0.5),
      );
    });

    testWidgets('stays at the viewport edge once the card is scrolled past', (
      tester,
    ) async {
      final controller = await pumpCard(tester);
      controller.jumpTo(600);
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(toolbar)).dy, closeTo(0, 0.5));
    });

    // The regression this class exists for. `_follow` runs from the scroll
    // position's notification, which is sent before the frame that offset
    // produces is laid out — so anything read from the card's paint transform
    // there describes the *previous* scroll. That made the strip trail a whole
    // gesture behind and, worse, travel downwards while the reader scrolled
    // up, until it appeared to detach from the card entirely.
    testWidgets('comes back up with the card, not down', (tester) async {
      final controller = await pumpCard(tester);
      controller.jumpTo(600);
      await tester.pump();
      final pinned = tester.getTopLeft(find.byKey(toolbar)).dy;

      controller.jumpTo(300);
      await tester.pump();
      final raised = tester.getTopLeft(find.byKey(toolbar)).dy;

      expect(
        raised,
        greaterThan(pinned),
        reason: 'the strip moved the wrong way when the reader scrolled up',
      );
      // The card's top is back on screen, so the strip is simply sitting on it.
      expect(
        raised,
        closeTo(tester.getTopLeft(find.byType(HinataEditorCard)).dy, 0.5),
      );
    });

    // The card runs 400..1642 in the scroll, so 1600 leaves its last 42px on
    // screen and asks the strip to travel further than the card is tall.
    testWidgets('never travels past the card it belongs to', (tester) async {
      final controller = await pumpCard(tester);
      controller.jumpTo(1600);
      await tester.pump();
      final card = tester.getRect(find.byType(HinataEditorCard));
      final strip = tester.getRect(find.byKey(toolbar));
      expect(strip.top, greaterThanOrEqualTo(card.top - 0.5));
      expect(strip.bottom, lessThanOrEqualTo(card.bottom + 0.5));
    });
  });
}
