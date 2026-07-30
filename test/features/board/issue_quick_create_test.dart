import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/features/board/issue_quick_create.dart';

/// The inline composer is the board's shortcut past the create dialog, so what
/// it must get right is the payload: everything the spot it sits in implies
/// (project, workflow state, sprint, parent) has to reach the server even
/// though the composer shows none of it — and a draft must never be lost.
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

  late _FakeIssueRepository issues;
  late _FakeUserRepository users;

  IssueQuickCreateSeed seed({
    List<Project> projects = const [],
    String? Function(Project project)? stateFor,
    String? sprintId,
    String? parentId,
    String? forcedType,
  }) => IssueQuickCreateSeed(
    projects: projects,
    stateFor: stateFor,
    sprintId: sprintId,
    parentId: parentId,
    forcedType: forcedType,
  );

  final created = <Issue>[];

  Widget host(IssueQuickCreateSeed s) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: MultiRepositoryProvider(
      providers: [
        RepositoryProvider<IssueRepository>.value(value: issues),
        RepositoryProvider<UserRepository>.value(value: users),
      ],
      child: BlocProvider<AuthBloc>(
        create: (_) => _FakeAuthBloc(),
        // A board column is narrow; keep the host that narrow so the composer is
        // laid out the way it really is.
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: IssueQuickCreate(
                label: 'board.addIssue',
                seed: s,
                onCreated: created.add,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester tester, IssueQuickCreateSeed s) async {
    await tester.pumpWidget(host(s));
    await tester.tap(find.text('board.addIssue'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    issues = _FakeIssueRepository();
    users = _FakeUserRepository();
    created.clear();
  });

  testWidgets('starts as the dashed add button, not a composer', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        seed(
          projects: [
            project('A', ['Open']),
          ],
        ),
      ),
    );
    expect(find.text('board.addIssue'), findsOneWidget);
    expect(find.text('board.quickCreateHint'), findsNothing);
  });

  testWidgets('submits the seeded project, state, sprint and parent', (
    tester,
  ) async {
    await open(
      tester,
      seed(
        projects: [
          project('A', ['Open', 'Done']),
        ],
        stateFor: (_) => 'Open',
        sprintId: 's1',
        parentId: 'epic-1',
      ),
    );
    await tester.enterText(find.byType(TextField), 'Test Ticket');
    await tester.pump();
    await tester.tap(find.byIcon(LucideIcons.cornerDownLeft));
    await tester.pumpAndSettle();

    expect(issues.bodies, hasLength(1));
    expect(issues.bodies.single, {
      'projectId': 'A',
      'title': 'Test Ticket',
      'type': 'TASK',
      'priority': 'NORMAL',
      'state': 'Open',
      'sprintId': 's1',
      'parentId': 'epic-1',
    });
    expect(created, hasLength(1));
  });

  testWidgets('resolves the column state against the chosen project', (
    tester,
  ) async {
    // A merged column carries one state per spanned project; the ticket must
    // start in the one its own project actually defines.
    final a = project('A', ['Open', 'Done']);
    final b = project('B', ['Intake', 'Done']);
    await open(
      tester,
      seed(
        projects: [a, b],
        stateFor: (p) => [
          'Open',
          'Intake',
        ].firstWhere((s) => p.stateNames.contains(s), orElse: () => 'Open'),
      ),
    );
    // Two projects ⇒ the composer offers the choice rather than picking one.
    expect(find.text('A'), findsOneWidget);
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B – B'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Cross');
    await tester.pump();
    await tester.tap(find.byIcon(LucideIcons.cornerDownLeft));
    await tester.pumpAndSettle();

    expect(issues.bodies.single['projectId'], 'B');
    expect(issues.bodies.single['state'], 'Intake');
  });

  testWidgets('a single-project spot shows no project control', (tester) async {
    await open(
      tester,
      seed(
        projects: [
          project('A', ['Open']),
        ],
      ),
    );
    expect(find.text('A'), findsNothing);
  });

  testWidgets('empty title does not submit', (tester) async {
    await open(
      tester,
      seed(
        projects: [
          project('A', ['Open']),
        ],
      ),
    );
    await tester.tap(find.byIcon(LucideIcons.cornerDownLeft));
    await tester.pumpAndSettle();
    expect(issues.bodies, isEmpty);
    // Still open, ready for the title.
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('closes after a successful create', (tester) async {
    await open(
      tester,
      seed(
        projects: [
          project('A', ['Open']),
        ],
      ),
    );
    await tester.enterText(find.byType(TextField), 'One');
    await tester.pump();
    await tester.tap(find.byIcon(LucideIcons.cornerDownLeft));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('board.addIssue'), findsOneWidget);
  });

  testWidgets('a failed create keeps the draft', (tester) async {
    issues.fail = true;
    await open(
      tester,
      seed(
        projects: [
          project('A', ['Open']),
        ],
      ),
    );
    await tester.enterText(find.byType(TextField), 'Keep me');
    await tester.pump();
    await tester.tap(find.byIcon(LucideIcons.cornerDownLeft));
    await tester.pumpAndSettle();

    expect(created, isEmpty);
    expect(find.text('Keep me'), findsOneWidget);
  });

  testWidgets('Escape closes the composer', (tester) async {
    await open(
      tester,
      seed(
        projects: [
          project('A', ['Open']),
        ],
      ),
    );
    await tester.enterText(find.byType(TextField), 'Draft');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(issues.bodies, isEmpty);
  });

  testWidgets('Enter submits, Shift+Enter does not', (tester) async {
    await open(
      tester,
      seed(
        projects: [
          project('A', ['Open']),
        ],
      ),
    );
    await tester.enterText(find.byType(TextField), 'Line');
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(issues.bodies, isEmpty, reason: 'Shift+Enter breaks the line');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(issues.bodies, hasLength(1));
  });

  testWidgets('a forced type is submitted and cannot be changed', (
    tester,
  ) async {
    await open(
      tester,
      seed(
        projects: [
          project('A', ['Open']),
        ],
        parentId: 'story-1',
        forcedType: 'SUBTASK',
      ),
    );
    // No chevron next to the glyph ⇒ the type control does not open.
    expect(find.byIcon(LucideIcons.chevronDown), findsNothing);

    await tester.enterText(find.byType(TextField), 'Child');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(issues.bodies.single['type'], 'SUBTASK');
    expect(issues.bodies.single['parentId'], 'story-1');
  });

  testWidgets('the picked type replaces the default', (tester) async {
    await open(
      tester,
      seed(
        projects: [
          project('A', ['Open']),
        ],
      ),
    );
    await tester.tap(find.byIcon(LucideIcons.chevronDown));
    await tester.pumpAndSettle();
    await tester.tap(find.text('type.bug').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Broken');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(issues.bodies.single['type'], 'BUG');
  });

  testWidgets('the picked assignee travels as a date-free single assignee', (
    tester,
  ) async {
    await open(
      tester,
      seed(
        projects: [
          project('A', ['Open']),
        ],
      ),
    );
    await tester.tap(find.byIcon(LucideIcons.user).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ada Lovelace'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Assigned');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(issues.bodies.single['assigneeIds'], ['u1']);
    expect(issues.bodies.single.containsKey('dueDate'), isFalse);
  });

  /// Opens the calendar and picks today. The anchored popover commits on pick,
  /// so there is no OK to press.
  Future<void> pickToday(WidgetTester tester) async {
    await tester.tap(find.byIcon(LucideIcons.calendarDays));
    await tester.pumpAndSettle();
    await tester.tap(find.text('${DateTime.now().day}'));
    await tester.pumpAndSettle();
  }

  testWidgets('the title field opens two lines tall', (tester) async {
    await open(
      tester,
      seed(
        projects: [
          project('A', ['Open']),
        ],
      ),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.minLines, 2);
    expect(field.maxLines, greaterThan(2), reason: 'and grows from there');
  });

  testWidgets('a set due date stays an icon and never spells the date out', (
    tester,
  ) async {
    await open(
      tester,
      seed(
        projects: [
          project('A', ['Open']),
        ],
      ),
    );
    await pickToday(tester);

    // A column is narrow: the date written into the toolbar overflowed it. The
    // control carries the honey tint instead — and a RenderFlex overflow would
    // fail this test on its own.
    expect(find.byIcon(LucideIcons.calendarDays), findsOneWidget);
    expect(find.textContaining('${DateTime.now().year}'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Dated');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(issues.bodies.single['dueDate'], isNotNull);
  });

  testWidgets('the calendar clears a due date it already holds', (
    tester,
  ) async {
    await open(
      tester,
      seed(
        projects: [
          project('A', ['Open']),
        ],
      ),
    );
    await pickToday(tester);

    // Reopening offers the way back out; without it a mis-tap would be
    // unfixable, since there is no inline × any more.
    await tester.tap(find.byIcon(LucideIcons.calendarDays));
    await tester.pumpAndSettle();
    await tester.tap(find.text('common.clear'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Undated');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(issues.bodies.single.containsKey('dueDate'), isFalse);
  });

  testWidgets('phone width opens the calendar as a modal, not a popover', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await open(
      tester,
      seed(
        projects: [
          project('A', ['Open']),
        ],
      ),
    );
    await tester.tap(find.byIcon(LucideIcons.calendarDays));
    await tester.pumpAndSettle();

    // The modal confirms with OK; the popover has no such button.
    expect(find.text('OK'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'On a phone');
    await tester.pump();
    await tester.tap(find.byIcon(LucideIcons.cornerDownLeft));
    await tester.pumpAndSettle();
    expect(issues.bodies.single['dueDate'], isNotNull);
  });

  testWidgets('reopening starts from a clean draft', (tester) async {
    await open(
      tester,
      seed(
        projects: [
          project('A', ['Open']),
        ],
      ),
    );
    await tester.enterText(find.byType(TextField), 'Abandoned');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(find.text('board.addIssue'));
    await tester.pumpAndSettle();
    expect(find.text('Abandoned'), findsNothing);
    expect(find.text('board.quickCreateHint'), findsOneWidget);
  });
}

class _FakeIssueRepository implements IssueRepository {
  final List<Map<String, dynamic>> bodies = [];
  bool fail = false;

  @override
  Future<Issue> createIssue(Map<String, dynamic> body) async {
    if (fail) throw ApiFailure('errors.unexpected');
    bodies.add(body);
    return Issue(
      id: 'i${bodies.length}',
      readableId: 'A-${bodies.length}',
      projectId: body['projectId'] as String,
      title: body['title'] as String,
      type: body['type'] as String,
      state: (body['state'] as String?) ?? 'Open',
      priority: 'NORMAL',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeUserRepository implements UserRepository {
  static const _people = [
    DirectoryUser(id: 'u1', username: 'ada', displayName: 'Ada Lovelace'),
    DirectoryUser(id: 'u2', username: 'linus', displayName: 'Linus Pauling'),
  ];

  @override
  Future<({List<DirectoryUser> items, int total})> searchUsers(
    String query, {
    int page = 0,
    int size = 25,
  }) async {
    final hits = query.isEmpty
        ? _people
        : _people
              .where(
                (u) =>
                    u.displayName.toLowerCase().contains(query.toLowerCase()),
              )
              .toList();
    return (items: hits.toList(), total: hits.length);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// The composer only reads the signed-in user to mark "me" in the people
/// picker; its initial (no user) state is enough.
class _FakeAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  _FakeAuthBloc() : super(const AuthState());

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
