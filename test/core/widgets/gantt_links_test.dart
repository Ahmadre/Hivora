import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/widgets/gantt_links.dart';

/// The connector maths behind the timeline: slot geometry, schedule conflicts
/// and the critical path.
void main() {
  GanttRow row(String id, String from, String to) =>
      GanttRow(id: id, from: DateTime.parse(from), to: DateTime.parse(to));

  GanttLink blocks(String source, String target) => GanttLink(
    id: '$source>$target',
    type: 'BLOCKS',
    sourceId: source,
    targetId: target,
  );

  final chartStart = DateTime.parse('2026-01-01');

  GanttGraph build(List<GanttRow> rows, List<GanttLink> links) =>
      GanttGraph.build(
        rows: rows,
        links: links,
        chartStart: chartStart,
        pxPerDay: 10,
      );

  test('places a bar on the day grid and a milestone on its own day', () {
    final graph = build([
      row('a', '2026-01-01', '2026-01-03'),
      row('m', '2026-01-05', '2026-01-05'),
    ], const []);

    final bar = graph.slots['a']!;
    expect(bar.left, 0);
    expect(bar.right, 30); // three days at 10px
    expect(bar.isMilestone, isFalse);

    final milestone = graph.slots['m']!;
    expect(milestone.isMilestone, isTrue);
    expect((milestone.left + milestone.right) / 2, 45); // centred on day 5
  });

  test('drops links whose other end is not on the chart', () {
    final graph = build(
      [row('a', '2026-01-01', '2026-01-03')],
      [blocks('a', 'elsewhere')],
    );

    expect(graph.edges, isEmpty);
    expect(graph.isEmpty, isTrue);
  });

  test('flags a blocked issue that starts before its blocker finishes', () {
    final graph = build(
      [
        row('a', '2026-01-01', '2026-01-10'),
        row('b', '2026-01-05', '2026-01-12'),
      ],
      [blocks('a', 'b')],
    );

    expect(graph.conflictIds, {'b'});
    expect(graph.edges.single.conflict, isTrue);
  });

  test('a finish-to-start chain with a day in between is no conflict', () {
    final graph = build(
      [
        row('a', '2026-01-01', '2026-01-03'),
        row('b', '2026-01-04', '2026-01-06'),
      ],
      [blocks('a', 'b')],
    );

    expect(graph.conflictIds, isEmpty);
    expect(graph.edges.single.conflict, isFalse);
  });

  test('critical path is the longest dependency chain, not the widest fan', () {
    // a(2d) → b(10d) → d, and a → c(1d) → d. The chain through b is longer.
    final graph = build(
      [
        row('a', '2026-01-01', '2026-01-02'),
        row('b', '2026-01-03', '2026-01-12'),
        row('c', '2026-01-03', '2026-01-03'),
        row('d', '2026-01-13', '2026-01-14'),
      ],
      [blocks('a', 'b'), blocks('b', 'd'), blocks('a', 'c'), blocks('c', 'd')],
    );

    expect(graph.criticalIds, {'a', 'b', 'd'});
  });

  test('informational links never enter the critical path', () {
    final graph = build(
      [
        row('a', '2026-01-01', '2026-01-02'),
        row('b', '2026-01-05', '2026-01-06'),
      ],
      [const GanttLink(id: 'r', type: 'RELATES', sourceId: 'a', targetId: 'b')],
    );

    expect(graph.criticalIds, isEmpty);
    expect(graph.dependencyCount, 0);
    expect(graph.relatedCount, 1);
  });

  test('a dependency cycle terminates instead of hanging the layout', () {
    final graph = build(
      [
        row('a', '2026-01-01', '2026-01-02'),
        row('b', '2026-01-03', '2026-01-04'),
      ],
      [blocks('a', 'b'), blocks('b', 'a')],
    );

    expect(graph.edges, hasLength(2));
    expect(graph.criticalIds, isNotEmpty);
  });

  test('focus keeps an issue and its direct neighbours', () {
    final graph = build(
      [
        row('a', '2026-01-01', '2026-01-02'),
        row('b', '2026-01-03', '2026-01-04'),
        row('c', '2026-01-06', '2026-01-07'),
      ],
      [blocks('a', 'b')],
    );

    expect(graph.relatedTo('a'), {'a', 'b'});
    expect(graph.relatedTo('c'), {'c'});
  });
}
