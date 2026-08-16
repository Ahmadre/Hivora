/// Two things the sprint meta row got wrong, both of which rendered as
/// confident nonsense rather than as an error:
///
///  * every row's avatar showed the same "6" — the assignee *id* was handed to
///    the avatar, and the initial of a Mongo ObjectId is whatever hex digit it
///    happens to start with;
///  * the capacity bar was always empty, whatever the numbers above it said,
///    because its segments were `ColoredBox`es in a `Row` whose default
///    cross-axis alignment collapsed them to zero height.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/widgets/hive_widgets.dart';
import 'package:hinata/features/sprint/widgets/plan_row.dart';
import 'package:hinata/features/sprint/widgets/sprint_widgets.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassProgressIndicator;

void main() {
  Issue issue({
    String id = 'i1',
    String state = 'TODO',
    DateTime? resolvedAt,
    int? points,
    String? assigneeId,
  }) => Issue(
    id: id,
    projectId: 'p1',
    readableId: 'HIN-1',
    title: 'Restore drag handles',
    state: state,
    resolvedAt: resolvedAt,
    storyPoints: points,
    assigneeId: assigneeId,
  );

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view
      ..physicalSize = const Size(900, 700)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox(width: 400, child: child)),
        ),
      ),
    );
  }

  group('assignee avatar', () {
    // The ids of accounts created in the same era share their leading digits,
    // so every row rendered the *same* letter — data that looks real and is not.
    const objectId = '68f2a1c4e9b70d3a5c81f206';

    test('an opaque id is recognised, a name is not', () {
      expect(looksLikeOpaqueId(objectId), isTrue);
      expect(looksLikeOpaqueId('550e8400-e29b-41d4-a716-446655440000'), isTrue);
      expect(looksLikeOpaqueId('Rebar Ahmad'), isFalse);
      expect(looksLikeOpaqueId('sso@server.test'), isFalse);
      // Short hex-ish words stay names: "beef", "faced", "decaf".
      expect(looksLikeOpaqueId('Adebayo'), isFalse);
    });

    testWidgets('an id renders a person glyph, never an initial', (
      tester,
    ) async {
      await pump(tester, const HiveAvatar(name: objectId, size: 24));

      expect(find.text('6'), findsNothing);
      expect(find.byType(Icon), findsOneWidget);
    });

    testWidgets('a resolved name still renders its initials', (tester) async {
      await pump(tester, const HiveAvatar(name: 'Rebar Ahmad', size: 24));

      expect(find.text('RA'), findsOneWidget);
    });

    testWidgets('the plan row draws the assignee, not their id', (
      tester,
    ) async {
      await pump(
        tester,
        PlanRow(
          issue: issue(assigneeId: objectId, points: 3),
          assigneeName: 'Rebar Ahmad',
          selected: false,
          onToggleSelect: () {},
          onOpen: () {},
          onEstimate: () {},
        ),
      );

      expect(find.text('RA'), findsOneWidget);
      expect(find.text('6'), findsNothing);
    });

    testWidgets('without a name the row shows no made-up initial', (
      tester,
    ) async {
      await pump(
        tester,
        PlanRow(
          issue: issue(assigneeId: objectId),
          selected: false,
          onToggleSelect: () {},
          onOpen: () {},
          onEstimate: () {},
        ),
      );

      expect(find.text('6'), findsNothing);
    });
  });

  group('capacity bar', () {
    /// The bar picks its own width, so it must be given loose constraints —
    /// exactly like the meta row it lives in.
    Future<void> pumpLoose(WidgetTester tester, Widget child) async {
      tester.view
        ..physicalSize = const Size(900, 700)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: child)),
          // Widget tests render raw i18n keys, which are wider than any real
          // label — enough to overflow a 150 px meta cell for test reasons
          // alone. Scale the type down so the layout, not the key, is measured.
          builder: (context, view) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(0.5)),
            child: view!,
          ),
        ),
      );
    }

    Finder bar() => find.byType(GlassProgressIndicator);

    double valueOf(WidgetTester tester) =>
        tester.widget<GlassProgressIndicator>(bar()).value!;

    testWidgets('fills in proportion to the committed points', (tester) async {
      await pumpLoose(
        tester,
        CapacityBar(
          issues: [
            issue(id: 'a', points: 10),
            issue(id: 'b', points: 10, state: 'IN_PROGRESS'),
          ],
          capacity: 40,
          width: 300,
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      // The label is one rich Text ("20" + " / 40 pts").
      expect(
        find.textContaining('/ 40 pts', findRichText: true),
        findsOneWidget,
      );
      expect(valueOf(tester), closeTo(0.5, 0.001));
    });

    testWidgets('an over-committed sprint fills the whole track', (
      tester,
    ) async {
      await pumpLoose(
        tester,
        CapacityBar(issues: [issue(points: 42)], capacity: 40, width: 300),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(valueOf(tester), 1.0);
      // The overflow is what the colour says; the number says by how much.
      expect(find.textContaining('42', findRichText: true), findsOneWidget);
    });

    testWidgets('an empty sprint shows an empty — but present — track', (
      tester,
    ) async {
      await pumpLoose(
        tester,
        const CapacityBar(issues: [], capacity: 40, width: 300),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(bar(), findsOneWidget);
      expect(valueOf(tester), 0.0);
    });

    testWidgets('without a configured capacity there is no bar to read', (
      tester,
    ) async {
      await pumpLoose(
        tester,
        CapacityBar(issues: [issue(points: 8)], capacity: null, width: 300),
      );

      expect(bar(), findsNothing);
      expect(find.textContaining('pts', findRichText: true), findsOneWidget);
    });

    testWidgets('the bar fits the width it is given', (tester) async {
      // The package's linear indicator defaults to a 200px minimum width; the
      // desktop meta row hands it 150.
      await pumpLoose(
        tester,
        CapacityBar(issues: [issue(points: 8)], capacity: 40, width: 150),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(tester.getSize(bar()).width, lessThanOrEqualTo(150));
      expect(tester.takeException(), isNull);
    });
  });
}
