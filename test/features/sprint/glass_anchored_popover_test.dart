/// The anchored glass dropdown — what it puts between its text and the page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/widgets/glass_panel.dart';
import 'package:hinata/features/search/search_tokens.dart';
import 'package:hinata/features/sprint/modals/glass_modal.dart';

void main() {
  Future<void> openPopover(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(900, 700)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showGlassAnchoredPopover<void>(
                  context,
                  anchorRect: const Rect.fromLTWH(40, 40, 200, 44),
                  builder: (_) => const SizedBox(
                    height: 180,
                    child: Center(child: Text('Ersti Woche')),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Every [ColoredBox] on screen painted in [color].
  Iterable<ColoredBox> boxesOf(WidgetTester tester, Color color) => tester
      .widgetList<ColoredBox>(find.byType(ColoredBox))
      .where((box) => box.color == color);

  testWidgets('carries its own base under the text it shows', (tester) async {
    // Without it the panel is a light wash over whatever the field sits on —
    // the dashboard's dark hero card, in the report this comes from — and the
    // ink lands on a mid-tone that fails AA. See the contrast test for the
    // numbers.
    await openPopover(tester);

    expect(find.text('Ersti Woche'), findsOneWidget);
    expect(boxesOf(tester, SearchTokens.light.tint), isNotEmpty);
  });

  testWidgets('settles the page behind it without dimming it like a modal', (
    tester,
  ) async {
    await openPopover(tester);

    final scrim = SearchTokens.light.popoverScrim;
    expect(boxesOf(tester, scrim), isNotEmpty);
    expect(boxesOf(tester, SearchTokens.light.scrim), isEmpty);
  });

  testWidgets('draws the rim that separates it from the page', (tester) async {
    await openPopover(tester);

    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .where((paint) => paint.painter is GlassRimPainter);
    expect(painters, isNotEmpty);
  });

  testWidgets('a real picker body fits the panel it is given', (tester) async {
    // The shape the dashboard's Hero-Board picker has: a modal header and a
    // flexible list, in a 300-wide dropdown. The base and the rim are painted
    // as stack layers over that content, and a stack that mis-sized would
    // show up here as an overflow rather than on someone's screen.
    tester.view
      ..physicalSize = const Size(900, 700)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showGlassAnchoredPopover<void>(
                  context,
                  anchorRect: const Rect.fromLTWH(40, 40, 300, 44),
                  width: 300,
                  builder: (_) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const GlassModalHeader(
                        icon: Icons.dashboard,
                        title: 'Hero-Board',
                        subtitle:
                            'Wähle dein Hero-Board, blende Kacheln ein/aus '
                            'und grenze die Daten ein.',
                        subtitleMaxLines: 3,
                      ),
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          children: [
                            for (var i = 0; i < 12; i++)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Text('Board $i'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Hero-Board'), findsOneWidget);
    // The whole hint, not a sentence that stops mid-word.
    expect(find.textContaining('grenze die Daten ein'), findsOneWidget);
    expect(boxesOf(tester, SearchTokens.light.tint), isNotEmpty);
  });

  testWidgets('a tap outside still closes it', (tester) async {
    // The scrim sits under the dismiss layer, not over it.
    await openPopover(tester);
    expect(find.text('Ersti Woche'), findsOneWidget);

    await tester.tapAt(const Offset(700, 600));
    await tester.pumpAndSettle();
    expect(find.text('Ersti Woche'), findsNothing);
  });
}
