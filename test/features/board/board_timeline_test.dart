import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/widgets/gantt_links.dart';
import 'package:hinata/features/board/board_timeline.dart';

/// The board timeline draws the same connectors as the Gantt screen: the
/// project's issue links plus the issues' own legacy `dependsOnIds`.
void main() {
  Issue issue(
    String id, {
    DateTime? start,
    DateTime? due,
    List<String> dependsOn = const [],
  }) => Issue(
    id: id,
    projectId: 'p1',
    readableId: 'HIN-$id',
    title: 'Issue $id',
    state: 'TODO',
    startDate: start,
    dueDate: due,
    dependsOnIds: dependsOn,
  );

  Widget host(List<Issue> issues, List<GanttLink> links) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SizedBox(
        width: 1200,
        height: 600,
        child: BoardTimeline(issues: issues, links: links, onOpen: (_) {}),
      ),
    ),
  );

  GanttGraph graphOf(WidgetTester tester) {
    final layer = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(GanttLinksLayer),
        matching: find.byType(CustomPaint),
      ),
    );
    return (layer.painter! as GanttLinksPainter).graph;
  }

  final day = DateTime(2026, 7, 20);

  testWidgets('draws a connector for a server-side link', (tester) async {
    await tester.pumpWidget(
      host(
        [
          issue('1', start: day, due: day.add(const Duration(days: 3))),
          issue(
            '2',
            start: day.add(const Duration(days: 4)),
            due: day.add(const Duration(days: 6)),
          ),
        ],
        const [
          GanttLink(id: 'l1', type: 'BLOCKS', sourceId: '1', targetId: '2'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final graph = graphOf(tester);
    expect(graph.dependencyCount, 1);
    expect(graph.conflictIds, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('folds the legacy dependsOnIds field into the graph', (
    tester,
  ) async {
    await tester.pumpWidget(
      host([
        issue('1', start: day, due: day.add(const Duration(days: 3))),
        // Starts on its blocker's last day — a scheduling conflict.
        issue(
          '2',
          start: day.add(const Duration(days: 3)),
          due: day.add(const Duration(days: 6)),
          dependsOn: ['1'],
        ),
      ], const []),
    );
    await tester.pumpAndSettle();

    final graph = graphOf(tester);
    expect(graph.dependencyCount, 1);
    expect(graph.conflictIds, {'2'});
  });

  testWidgets('a due-date-only issue renders as a milestone', (tester) async {
    await tester.pumpWidget(
      host([
        issue('1', start: day, due: day.add(const Duration(days: 3))),
        issue('2', due: day.add(const Duration(days: 5))),
      ], const []),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GanttMilestone), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a link to an issue that is not on the chart is dropped', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        [issue('1', start: day, due: day.add(const Duration(days: 3)))],
        const [
          GanttLink(
            id: 'l1',
            type: 'BLOCKS',
            sourceId: '1',
            targetId: 'off-chart',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // Nothing to draw → the layer collapses instead of painting a stray line.
    expect(find.byType(GanttLinksLayer), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(GanttLinksLayer),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
  });
}
