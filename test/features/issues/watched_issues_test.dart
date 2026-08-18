/// The "Watched" list pages like every other long list in the app.
///
/// It is backed by [PagedCubit] over `/me/watched`, so the interesting parts
/// are the seams a hand-rolled list gets wrong: appending a page instead of
/// replacing one, stopping once the backend total is reached, and surviving a
/// failed first load with something to retry from.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/core/widgets/hive_empty_state.dart';
import 'package:hinata/features/issues/issues_screen.dart' show IssueRow;
import 'package:hinata/features/issues/watched_issues_screen.dart';

void main() {
  group('IssueRepository.watchedIssues', () {
    test(
      'asks /me/watched for the requested page and unwraps the envelope',
      () async {
        final api = _FakeApi(total: 3, pageSize: 2);
        final repo = IssueRepository(api);

        final page = await repo.watchedIssues(page: 1, size: 2);

        expect(api.lastPath, '/api/v1/me/watched');
        expect(api.lastQuery, {'page': 1, 'size': 2});
        expect(page.total, 3);
        expect(page.items.single.readableId, 'HIN-3');
        expect(page.items.single.watcherIds, ['u1']);
      },
    );
  });

  group('the watched list cubit', () {
    PagedCubit<Issue> cubitFor(_FakeApi api) {
      final repo = IssueRepository(api);
      return PagedCubit<Issue>(
        (page, size) => repo.watchedIssues(page: page, size: size),
        pageSize: 2,
        keyOf: (issue) => issue.id,
      );
    }

    test('loads the first page', () async {
      final cubit = cubitFor(_FakeApi(total: 3, pageSize: 2));
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.items.map((i) => i.readableId), ['HIN-1', 'HIN-2']);
      expect(cubit.state.total, 3);
      expect(cubit.state.hasMore, isTrue);
      expect(cubit.state.errorKey, isNull);
    });

    test('appends the next page and then stops asking', () async {
      final api = _FakeApi(total: 3, pageSize: 2);
      final cubit = cubitFor(api);
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.loadMore();

      expect(cubit.state.items.map((i) => i.readableId), [
        'HIN-1',
        'HIN-2',
        'HIN-3',
      ]);
      expect(cubit.state.hasMore, isFalse);

      final calls = api.calls;
      await cubit.loadMore();
      expect(api.calls, calls);
    });

    test(
      'reports an empty subscription list as loaded, not as an error',
      () async {
        final cubit = cubitFor(_FakeApi(total: 0, pageSize: 2));
        addTearDown(cubit.close);

        await cubit.load();

        // hasData is what tells the view to render the empty state rather than
        // the spinner it would otherwise sit on forever.
        expect(cubit.state.items, isEmpty);
        expect(cubit.state.hasData, isTrue);
        expect(cubit.state.errorKey, isNull);
      },
    );

    test('surfaces a failed load as a retryable error', () async {
      final api = _FakeApi(
        total: 2,
        pageSize: 2,
        failure: ApiFailure('Offline'),
      );
      final cubit = cubitFor(api);
      addTearDown(cubit.close);

      await cubit.load();
      expect(cubit.state.errorKey, 'Offline');
      expect(cubit.state.hasData, isFalse);
      expect(cubit.state.isLoading, isFalse);

      api.failure = null;
      await cubit.load();
      expect(cubit.state.errorKey, isNull);
      expect(cubit.state.items, hasLength(2));
    });
  });

  group('the watched screen', () {
    Widget host(_FakeApi api) => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<IssueRepository>(
            create: (_) => IssueRepository(api),
          ),
          RepositoryProvider<UserRepository>(
            create: (_) => _FakeUserRepository(),
          ),
          RepositoryProvider<ProjectRepository>(
            create: (_) => _FakeProjectRepository(),
          ),
        ],
        child: const Scaffold(body: WatchedIssuesScreen()),
      ),
    );

    testWidgets('lists the first page of watched issues', (tester) async {
      tester.view
        ..physicalSize = const Size(1200, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(_FakeApi(total: 2, pageSize: 25)));
      await tester.pump();
      await tester.pump();

      expect(find.byType(IssueRow), findsNWidgets(2));
      expect(find.byType(HiveEmptyState), findsNothing);
    });

    testWidgets('offers the branded empty state when nothing is watched', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1200, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(_FakeApi(total: 0, pageSize: 25)));
      await tester.pump();
      await tester.pump();

      expect(find.byType(HiveEmptyState), findsOneWidget);
      // Widget tests render i18n keys, so assert on the key rather than prose.
      expect(find.text('watched.empty.title'), findsOneWidget);
      expect(find.byType(IssueRow), findsNothing);
    });
  });
}

class _FakeUserRepository implements UserRepository {
  @override
  Future<List<DirectoryUser>> users() async => const [
    DirectoryUser(id: 'u1', username: 'rebar', displayName: 'Rebar'),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeProjectRepository implements ProjectRepository {
  @override
  Future<List<Project>> projects({bool archived = false}) async => const [
    Project(id: 'p1', key: 'HIN', name: 'Hinata'),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// Serves `HIN-1…HIN-<total>` in pages, and can be made to fail.
class _FakeApi implements ApiClient {
  _FakeApi({required this.total, required this.pageSize, this.failure});

  final int total;
  final int pageSize;
  Object? failure;
  int calls = 0;
  String? lastPath;
  Map<String, dynamic>? lastQuery;

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    calls++;
    lastPath = path;
    lastQuery = query;
    if (failure != null) throw failure!;
    final page = query?['page'] as int? ?? 0;
    final size = query?['size'] as int? ?? pageSize;
    final from = page * size;
    return {
      'content': [
        for (var i = from; i < total && i < from + size; i++)
          {
            'id': 'i${i + 1}',
            'projectId': 'p1',
            'readableId': 'HIN-${i + 1}',
            'title': 'Watched $i',
            'state': 'OPEN',
            'watcherIds': ['u1'],
          },
      ],
      'totalElements': total,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
