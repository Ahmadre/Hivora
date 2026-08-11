/// A board made on one screen has to show up on every other one.
///
/// The report this comes from: creating a board opened it on top of the
/// overview, and coming back showed the list from before it existed — until the
/// page was left and entered again. The list was never told.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/events/board_events.dart';
import 'package:hinata/core/models/team_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/board_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/team_repository.dart';
import 'package:hinata/features/board/board_screen.dart';

void main() {
  group('the repository', () {
    test('announces a board it created', () async {
      // On the repository rather than at the call site: a board is made from
      // two screens and managed from two more, and the screens that show
      // boards are none of them.
      final api = _FakeApi();
      final repository = BoardRepository(api);
      final heard = <void>[];
      final sub = BoardEvents.instance.changes.listen(heard.add);
      addTearDown(sub.cancel);

      await repository.createBoard('Ersti Woche', ['p1']);
      await pumpEventQueue();

      expect(heard, hasLength(1));
    });

    test('announces a rename and a re-scope', () async {
      final repository = BoardRepository(_FakeApi());
      final heard = <void>[];
      final sub = BoardEvents.instance.changes.listen(heard.add);
      addTearDown(sub.cancel);

      await repository.renameBoard('b1', 'Neuer Name');
      await repository.updateBoardProjects('b1', ['p1', 'p2']);
      await pumpEventQueue();

      expect(heard, hasLength(2));
    });

    test('says nothing about a column layout', () async {
      // Nothing a list of boards shows, and the editor that changes it lives
      // inside the one board it belongs to — which reloads itself.
      final repository = BoardRepository(_FakeApi());
      final heard = <void>[];
      final sub = BoardEvents.instance.changes.listen(heard.add);
      addTearDown(sub.cancel);

      await repository.updateBoardColumns('b1', const []);
      await repository.resetBoardColumns('b1');
      await pumpEventQueue();

      expect(heard, isEmpty);
    });

    test('says nothing about merely reading them', () async {
      // A reload that announced itself would reload again, forever.
      final repository = BoardRepository(_FakeApi());
      final heard = <void>[];
      final sub = BoardEvents.instance.changes.listen(heard.add);
      addTearDown(sub.cancel);

      await repository.boards();
      await pumpEventQueue();

      expect(heard, isEmpty);
    });
  });

  group('the board overview', () {
    late _CountingBoardRepository boards;

    Widget host() => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<BoardRepository>.value(value: boards),
          RepositoryProvider<ProjectRepository>.value(
            value: _FakeProjectRepository(),
          ),
          RepositoryProvider<TeamRepository>.value(
            value: _FakeTeamRepository(),
          ),
        ],
        child: BlocProvider<AuthBloc>(
          create: (_) => _FakeAuthBloc(),
          child: const Scaffold(body: BoardScreen()),
        ),
      ),
    );

    setUp(() => boards = _CountingBoardRepository());

    testWidgets('picks up a board created while it is still on the stack', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1200, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.text('Stupa Website'), findsOneWidget);
      expect(find.text('Ersti Woche'), findsNothing);

      // What creating a board from this very screen does: the board exists,
      // and the list is behind the page that opened on top of it.
      boards.catalogue = const [
        AgileBoard(id: 'b1', name: 'Stupa Website', projectIds: ['p1']),
        AgileBoard(id: 'b2', name: 'Ersti Woche', projectIds: ['p1']),
      ];
      BoardEvents.instance.notifyChanged();
      await tester.pumpAndSettle();

      expect(find.text('Ersti Woche'), findsOneWidget);
    });

    testWidgets('stops listening once it is gone', (tester) async {
      // A screen that kept its subscription would setState after dispose, and
      // the next board anyone creates would take the app down with it.
      tester.view
        ..physicalSize = const Size(1200, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      final before = boards.loads;

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();

      BoardEvents.instance.notifyChanged();
      await tester.pumpAndSettle();

      expect(boards.loads, before);
      expect(tester.takeException(), isNull);
    });
  });
}

const _boardJson = {
  'id': 'b1',
  'name': 'Ersti Woche',
  'projectIds': ['p1'],
};

class _FakeApi implements ApiClient {
  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async =>
      <dynamic>[];

  @override
  Future<dynamic> post(String path, {Object? body}) async => _boardJson;

  @override
  Future<dynamic> patch(String path, {Object? body}) async => _boardJson;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// Serves a catalogue that the test swaps, and counts the fetches.
class _CountingBoardRepository implements BoardRepository {
  List<AgileBoard> catalogue = const [
    AgileBoard(id: 'b1', name: 'Stupa Website', projectIds: ['p1']),
  ];
  int loads = 0;

  @override
  Future<List<AgileBoard>> boards({String? projectId}) async {
    loads++;
    return catalogue;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeProjectRepository implements ProjectRepository {
  @override
  Future<List<Project>> projects({bool archived = false}) async => const [
    Project(id: 'p1', key: 'STU', name: 'Stupa'),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeTeamRepository implements TeamRepository {
  @override
  Future<List<Team>> teams() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// The overview only reads the signed-in user to decide who may manage a
/// board; its initial (no user) state is enough.
class _FakeAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  _FakeAuthBloc() : super(const AuthState());

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
