/// What the issue row owes an RTL reader.
///
/// Flutter mirrors a `Row` for free, so the parts of a screen that break in
/// Arabic are the ones that opted out of the text direction without meaning to:
/// a physical `EdgeInsets.only(left:)`, an `Alignment.centerLeft`, a chevron
/// glyph that has no mirrored twin in the icon font. None of those show up in a
/// green build — they show up in a screenshot, which is why they survived to
/// HIN-77.
///
/// These assert geometry and glyph choice rather than pixels of text: a widget
/// test renders i18n keys, not translations, so any assertion about how wide a
/// label came out would be measuring the wrong string.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/widgets/hive_widgets.dart'
    show backChevron, chevronTurn, forwardChevron;
import 'package:hinata/features/issues/issues_screen.dart' show IssueRow;
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  final issue = Issue(
    id: 'i1',
    projectId: 'p1',
    readableId: 'HIN-1',
    title: 'Agile board redesign',
    state: 'In Progress',
    priority: 'MAJOR',
    // 17 days late: the case that overflowed the old fixed-width due column in
    // every language that spells the unit out.
    dueDate: DateTime.now().subtract(const Duration(days: 17)),
  );

  Widget host(TextDirection direction) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Directionality(
      textDirection: direction,
      child: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: IssueRow(issue: issue, assignee: 'Theo Hahn'),
        ),
      ),
    ),
  );

  /// The row picks its layout off the window, not off its own box, so the
  /// window is what a width case has to move. 800 is already past the compact
  /// breakpoint, which is the layout under test.
  Future<void> pumpAt(
    WidgetTester tester,
    TextDirection direction, {
    double width = 800,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(direction));
  }

  double centerX(WidgetTester tester, Finder f) => tester.getCenter(f).dx;

  final idText = find.text('HIN-1');
  final chevron = find.byWidgetPredicate(
    (w) =>
        w is Icon &&
        (w.icon == LucideIcons.chevronRight ||
            w.icon == LucideIcons.chevronLeft),
  );

  group('the wide row', () {
    testWidgets('reads left to right in a Latin locale', (tester) async {
      await pumpAt(tester, TextDirection.ltr);

      // The id opens the row and the disclosure chevron closes it.
      expect(centerX(tester, idText), lessThan(centerX(tester, chevron)));
    });

    testWidgets('mirrors end to end in Arabic', (tester) async {
      await pumpAt(tester, TextDirection.rtl);

      expect(centerX(tester, idText), greaterThan(centerX(tester, chevron)));
    });

    testWidgets('turns the disclosure chevron around with it', (tester) async {
      await pumpAt(tester, TextDirection.ltr);
      expect(tester.widget<Icon>(chevron).icon, LucideIcons.chevronRight);

      await pumpAt(tester, TextDirection.rtl);
      // Lucide has no mirroring glyph — left as chevronRight it would point
      // back into the row it is supposed to lead out of.
      expect(tester.widget<Icon>(chevron).icon, LucideIcons.chevronLeft);
    });

    // The due column was a fixed 60px, which fits `17d overdue` and nothing
    // else. A wider fixed number would only move the problem, and the header
    // above the rows would have had to be widened by hand to match; sharing a
    // flex is what keeps the two in step.
    testWidgets('gives the due column room as the window grows', (
      tester,
    ) async {
      Future<double> dueWidth(double windowWidth) async {
        await pumpAt(tester, TextDirection.ltr, width: windowWidth);
        return tester.getSize(find.text('issues.due.overdue')).width;
      }

      final narrow = await dueWidth(800);
      final wide = await dueWidth(1600);

      expect(wide, greaterThan(narrow));
    });
  });

  group('the chevron helpers', () {
    testWidgets('point the way the text runs, and pair up', (tester) async {
      late BuildContext ltr;
      late BuildContext rtl;
      await tester.pumpWidget(
        Column(
          children: [
            for (final d in TextDirection.values)
              Directionality(
                textDirection: d,
                child: Builder(
                  builder: (context) {
                    if (d == TextDirection.ltr) {
                      ltr = context;
                    } else {
                      rtl = context;
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
          ],
        ),
      );

      expect(forwardChevron(ltr), LucideIcons.chevronRight);
      expect(forwardChevron(rtl), LucideIcons.chevronLeft);
      expect(backChevron(ltr), forwardChevron(rtl));
      expect(backChevron(rtl), forwardChevron(ltr));

      // A section that opens swings its chevron down — clockwise from the right,
      // counter-clockwise from the left. A fixed +0.25 points the Arabic one up.
      expect(chevronTurn(ltr), 0.25);
      expect(chevronTurn(rtl), -0.25);
    });
  });
}
