import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/widgets/gantt_links.dart';
import 'package:hinata/core/widgets/glass_panel.dart';
import 'package:hinata/features/gantt/gantt_screen.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The timeline's floating switcher has to fit a phone: below the compact
/// breakpoint (~610px) its chips drop their labels and keep them as tooltips.
void main() {
  final day = DateTime(2026, 7, 20);

  GanttTask task(String id, {DateTime? start, DateTime? due}) => GanttTask(
    id: id,
    readableId: 'HIN-$id',
    title: 'Issue $id',
    state: 'TODO',
    resolved: false,
    progressPercent: 0,
    startDate: start,
    dueDate: due,
  );

  late _FakeProjectRepository repo;

  setUp(() {
    repo = _FakeProjectRepository(
      GanttView(
        tasks: [
          task('1', start: day, due: day.add(const Duration(days: 3))),
          task(
            '2',
            start: day.add(const Duration(days: 4)),
            due: day.add(const Duration(days: 7)),
          ),
        ],
        links: const [
          GanttLink(id: 'l1', type: 'BLOCKS', sourceId: '1', targetId: '2'),
        ],
      ),
    );
  });

  Widget host(Size size) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: RepositoryProvider<ProjectRepository>.value(
        value: repo,
        child: const Scaffold(body: GanttScreen()),
      ),
    ),
  );

  testWidgets('phone width shows the switcher as icons only', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const Size(402, 874)));
    await tester.pumpAndSettle();

    // Labels gone …
    expect(find.text('gantt.week'), findsNothing);
    expect(find.text('gantt.month'), findsNothing);
    expect(find.text('gantt.today'), findsNothing);
    // … but every action is still reachable through its icon.
    expect(find.byIcon(LucideIcons.calendarRange), findsOneWidget);
    expect(find.byIcon(LucideIcons.calendarDays), findsOneWidget);
    expect(find.byIcon(LucideIcons.locateFixed), findsOneWidget);
    expect(find.byIcon(LucideIcons.gitFork), findsOneWidget);
    // The labels survive as tooltips.
    expect(
      find.byWidgetPredicate((w) => w is Tooltip && w.message == 'gantt.week'),
      findsOneWidget,
    );
  });

  testWidgets('wide layout keeps the labelled chips', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const Size(1400, 900)));
    await tester.pumpAndSettle();

    expect(find.text('gantt.week'), findsOneWidget);
    expect(find.text('gantt.month'), findsOneWidget);
    expect(find.text('gantt.today'), findsOneWidget);
  });

  for (final size in const [Size(402, 874), Size(1400, 900)]) {
    testWidgets('the switcher rides on the glass surface at ${size.width}px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(size));
      await tester.pumpAndSettle();

      // Liquid glass on every screen size — never Material card chrome.
      expect(find.byType(GlassFloatingSurface), findsOneWidget);
    });
  }

  testWidgets('renders the dependency connectors it was given', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const Size(1400, 900)));
    await tester.pumpAndSettle();

    final painter =
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byType(GanttLinksLayer),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as GanttLinksPainter;
    expect(painter.graph.dependencyCount, 1);
    expect(painter.graph.conflictIds, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

class _FakeProjectRepository implements ProjectRepository {
  _FakeProjectRepository(this.view);

  final GanttView view;

  @override
  Future<List<Project>> projects({bool archived = false}) async => [
    const Project(id: 'p1', key: 'HIN', name: 'Hinata', color: '#AEC6F4'),
  ];

  @override
  Future<GanttView> gantt(String projectId) async => view;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
