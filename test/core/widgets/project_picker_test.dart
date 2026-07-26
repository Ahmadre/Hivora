import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/widgets/project_picker.dart';

/// The project picker replaced an inline list of every project: a one-line field
/// opens a searchable popover that asks the server for one page at a time. In
/// multi mode the pick is only handed back once it is confirmed, which is what
/// lets the board menu use the picker as its whole edit surface.
void main() {
  Project project(int i) =>
      Project(id: 'p$i', key: 'P$i', name: 'Project $i', color: '#AEC6F4');

  late _FakeProjectRepository repo;

  setUp(() => repo = _FakeProjectRepository(List.generate(60, project)));

  /// Hosts the field and records what the picker resolved to.
  Widget host({
    List<Project> initial = const [],
    bool multi = true,
    String? exclude,
    List<Project> seed = const [],
    List<List<Project>?>? results,
  }) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: RepositoryProvider<ProjectRepository>.value(
      value: repo,
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: 420,
            child: StatefulBuilder(
              builder: (context, setState) {
                var picked = initial;
                return ProjectPickerField(
                  projects: picked,
                  placeholderKey: 'projects.picker.choose',
                  onTap: (anchor) async {
                    final result = await showProjectPicker(
                      context,
                      anchorRect: anchor,
                      selected: {for (final p in picked) p.id},
                      titleKey: 'board.projectsField',
                      multi: multi,
                      excludeProjectId: exclude,
                      seed: seed,
                    );
                    results?.add(result);
                    if (result != null) setState(() => picked = result);
                  },
                );
              },
            ),
          ),
        ),
      ),
    ),
  );

  /// A row inside the picker's list — the field behind it shows the same names
  /// as chips, so an unscoped text finder could point at either.
  Finder row(String name) =>
      find.descendant(of: find.byType(ListView), matching: find.text(name));

  Future<void> openPicker(WidgetTester tester) async {
    await tester.tap(find.byType(ProjectPickerField));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the selection as chips instead of a list', (tester) async {
    await tester.pumpWidget(host(initial: [project(1), project(2)]));
    await tester.pumpAndSettle();

    expect(find.text('Project 1'), findsOneWidget);
    expect(find.text('Project 2'), findsOneWidget);
    // Nothing was fetched: the field is a trigger, not the picker.
    expect(repo.calls, isEmpty);
  });

  testWidgets('asks for one page instead of every project', (tester) async {
    await tester.pumpWidget(host());
    await openPicker(tester);

    expect(repo.calls.single.page, 0);
    expect(repo.calls.single.size, 25);
    expect(find.text('Project 0'), findsOneWidget);
    // Well beyond the first page — it must not have been fetched.
    expect(find.text('Project 40'), findsNothing);
  });

  testWidgets('searches the server after the keystrokes settle', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await openPicker(tester);
    repo.calls.clear();

    await tester.enterText(find.byType(TextField), 'inf');
    await tester.pump(const Duration(milliseconds: 100));
    // Still inside the debounce window: typing must not be a request per key.
    expect(repo.calls, isEmpty);

    await tester.pumpAndSettle();
    expect(repo.calls.single.query, 'inf');
    expect(repo.calls.single.page, 0);
  });

  testWidgets('keeps the current selection visible while a search hides it', (
    tester,
  ) async {
    await tester.pumpWidget(host(initial: [project(3)], seed: [project(3)]));
    await openPicker(tester);

    // A needle that matches nothing — the pinned row survives it, because
    // scrolling back to find what you already picked is exactly what the old
    // inline list forced.
    repo.matches = const [];
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();

    // Scoped to the picker's list — the field behind it shows the same name as
    // a chip, which would satisfy a loose finder without proving anything.
    expect(row('Project 3'), findsOneWidget);
  });

  testWidgets('labels a held id the caller could not seed', (tester) async {
    await tester.pumpWidget(host(initial: [project(7)]));
    await openPicker(tester);

    expect(repo.resolved, ['p7']);
  });

  testWidgets('hands multi picks back only once confirmed', (tester) async {
    final results = <List<Project>?>[];
    await tester.pumpWidget(host(results: results));
    await openPicker(tester);

    await tester.tap(row('Project 0'));
    await tester.pumpAndSettle();
    // Ticking a row keeps the picker open — several projects is the point.
    expect(results, isEmpty);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(row('Project 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('common.apply'));
    await tester.pumpAndSettle();

    expect(results.single!.map((p) => p.id), ['p0', 'p1']);
  });

  testWidgets('leaves the selection untouched when dismissed', (tester) async {
    final results = <List<Project>?>[];
    await tester.pumpWidget(
      host(initial: [project(1)], seed: [project(1)], results: results),
    );
    await openPicker(tester);

    await tester.tap(row('Project 0'));
    await tester.pumpAndSettle();
    // Tap the barrier: an abandoned edit must not reach the caller.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(results.single, isNull);
  });

  testWidgets('picks and closes immediately in single mode', (tester) async {
    final results = <List<Project>?>[];
    await tester.pumpWidget(host(multi: false, results: results));
    await openPicker(tester);

    await tester.tap(find.text('Project 1'));
    await tester.pumpAndSettle();

    expect(results.single!.single.id, 'p1');
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('never offers the excluded project', (tester) async {
    await tester.pumpWidget(host(multi: false, exclude: 'p2'));
    await openPicker(tester);

    expect(find.text('Project 1'), findsOneWidget);
    expect(find.text('Project 2'), findsNothing);
  });

  testWidgets('the phone sheet hugs a short catalogue', (tester) async {
    // Below the popover breakpoint the picker opens as a bottom sheet, which
    // used to be pinned to 460px — a workspace with a handful of projects got a
    // slab of empty glass under the confirm button. 700px keeps this on the
    // sheet path without squeezing the footer, which renders i18n keys here.
    tester.view.physicalSize = const Size(700 * 2, 800 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    repo = _FakeProjectRepository(List.generate(3, project));

    await tester.pumpWidget(host());
    await openPicker(tester);

    expect(find.byType(ListView), findsOneWidget); // the sheet, not the popover
    expect(tester.getSize(find.byType(AnimatedSize)).height, lessThan(400));
  });
}

/// Serves pages out of a fixed catalogue and records what was asked for.
class _FakeProjectRepository implements ProjectRepository {
  _FakeProjectRepository(this.catalogue) : matches = catalogue;

  final List<Project> catalogue;

  /// What a non-empty query resolves to — the fake does not really search.
  List<Project> matches;

  final List<({String? query, int page, int size})> calls = [];
  final List<String> resolved = [];

  @override
  Future<({List<Project> projects, int total})> searchProjects({
    String? query,
    int page = 0,
    int size = 25,
    bool archived = false,
  }) async {
    calls.add((query: query, page: page, size: size));
    final source = query == null || query.isEmpty ? catalogue : matches;
    final from = (page * size).clamp(0, source.length);
    final to = (from + size).clamp(0, source.length);
    return (projects: source.sublist(from, to), total: source.length);
  }

  @override
  Future<List<Project>> resolveProjects(List<String> ids) async {
    resolved.addAll(ids);
    return [
      for (final p in catalogue)
        if (ids.contains(p.id)) p,
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
