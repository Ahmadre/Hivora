import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/board_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/features/board/board_columns_editor.dart';

/// The column editor is the escape hatch from the automatic merge, so the rules
/// it has to hold up are the ones the board itself depends on: every status
/// needs a column, and a column may serve each project only once.
void main() {
  Project project(String key, List<String> states) => Project(
    id: key,
    key: key,
    name: key,
    color: '#AEC6F4',
    workflowStates: [
      for (var i = 0; i < states.length; i++)
        WorkflowState(id: '$key$i', name: states[i], hue: 250),
    ],
  );

  const board = AgileBoard(
    id: 'b1',
    name: 'Wall',
    projectIds: ['A', 'B'],
    columnsCustomized: true,
  );

  BoardColumnView column(String name, List<String> states) =>
      BoardColumnView(name: name, states: states, issues: const []);

  late _FakeBoardRepository boards;
  late _FakeProjectRepository projects;

  Widget host() => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: MultiRepositoryProvider(
      providers: [
        RepositoryProvider<BoardRepository>.value(value: boards),
        RepositoryProvider<ProjectRepository>.value(value: projects),
      ],
      child: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showBoardColumnsEditor(context, board),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  /// The "+" inside a pool chip — scoped to the chip, since the "add column"
  /// button carries the same icon.
  Finder assignButton(String state) => find.descendant(
    of: find.ancestor(of: find.text(state), matching: find.byType(Row)).first,
    matching: find.byIcon(LucideIcons.plus),
  );

  Future<void> openEditor(WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    projects = _FakeProjectRepository([
      project('A', ['Open', 'Done']),
      project('B', ['Intake', 'Open', 'Done']),
    ]);
    boards = _FakeBoardRepository([
      column('Los', ['Open']),
      column('Fertig', ['Done']),
    ]);
  });

  testWidgets('will not save while a status has no column', (tester) async {
    await openEditor(tester);

    // "Intake" is in no column — saving would take its issues off the board.
    expect(find.text('Intake'), findsOneWidget);
    expect(find.text('board.columns.unassignedHint'), findsOneWidget);
    await tester.tap(find.text('common.save'));
    await tester.pumpAndSettle();
    expect(boards.saved, isNull);
  });

  testWidgets('saves once every status has a column', (tester) async {
    await openEditor(tester);

    // Both existing columns already serve B (their states exist in A and B), so
    // "Intake" needs one of its own — the same conclusion the automatic merge
    // reaches.
    await tester.tap(find.text('board.columns.addColumn'));
    await tester.pumpAndSettle();
    await tester.tap(assignButton('Intake'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('board.columns.newColumn').last);
    await tester.pumpAndSettle();

    expect(find.text('board.columns.unassignedHint'), findsNothing);
    await tester.tap(find.text('common.save'));
    await tester.pumpAndSettle();

    expect(boards.saved, isNotNull);
    expect(boards.saved!.map((c) => c.name), [
      'Los',
      'Fertig',
      'board.columns.newColumn',
    ]);
    expect(boards.saved!.last.states, ['Intake']);
  });

  testWidgets('offers no column that already serves the same project', (
    tester,
  ) async {
    // "Open" belongs to A *and* B, so the column holding it already serves both.
    // Putting "Intake" (B) there too would leave a drop no single target.
    boards = _FakeBoardRepository([
      column('Alles', ['Open', 'Done']),
    ]);
    await openEditor(tester);

    await tester.tap(assignButton('Intake'));
    await tester.pumpAndSettle();

    expect(find.text('board.columns.noColumnAvailable'), findsOneWidget);
    expect(find.text('board.columns.assignTo'), findsNothing);
  });

  testWidgets('resets a hand-made layout back to automatic', (tester) async {
    await openEditor(tester);

    await tester.tap(find.text('board.columns.automatic'));
    await tester.pumpAndSettle();

    expect(boards.didReset, isTrue);
  });

  testWidgets('keeps the reset action out of the footer row', (tester) async {
    // It used to sit in the footer's hint slot, sharing one row with Cancel and
    // Save; on a phone the leftover width broke "Zurück zu automatisch" into a
    // column of syllables. It now shares a wrapping row with "add column", which
    // can give each label a full line. Asserted structurally rather than in
    // pixels: these tests render i18n keys, and a key is not the label's width.
    await openEditor(tester);

    final actions = find.ancestor(
      of: find.text('board.columns.automatic'),
      matching: find.byType(Wrap),
    );
    expect(actions, findsWidgets);
    expect(
      find.descendant(
        of: actions.first,
        matching: find.text('board.columns.addColumn'),
      ),
      findsOneWidget,
    );
  });
}

class _FakeBoardRepository implements BoardRepository {
  _FakeBoardRepository(this.columns);

  final List<BoardColumnView> columns;
  List<BoardColumnLayout>? saved;
  bool didReset = false;

  @override
  Future<BoardView> boardView(String boardId, {String? sprintId}) async =>
      BoardView(
        board: const AgileBoard(
          id: 'b1',
          name: 'Wall',
          projectIds: ['A', 'B'],
          columnsCustomized: true,
        ),
        sprints: const [],
        columns: columns,
      );

  @override
  Future<AgileBoard> updateBoardColumns(
    String boardId,
    List<BoardColumnLayout> columns,
  ) async {
    saved = columns;
    return const AgileBoard(id: 'b1', name: 'Wall');
  }

  @override
  Future<AgileBoard> resetBoardColumns(String boardId) async {
    didReset = true;
    return const AgileBoard(id: 'b1', name: 'Wall');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeProjectRepository implements ProjectRepository {
  _FakeProjectRepository(this.catalogue);

  final List<Project> catalogue;

  @override
  Future<List<Project>> resolveProjects(List<String> ids) async => [
    for (final p in catalogue)
      if (ids.contains(p.id)) p,
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
