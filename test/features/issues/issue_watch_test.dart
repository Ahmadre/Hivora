/// Watching an issue: the model field, the optimistic toggle, and what happens
/// when the server says no.
///
/// The toggle flips before the round trip finishes — that is the whole point
/// of it — so the only thing standing between a refused call and a lie on
/// screen is the rollback. It is tested at both levels: the cubit's state
/// sequence, and the switch the user actually looks at.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/events/issue_events.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/core/widgets/hive_widgets.dart';
import 'package:hinata/features/issues/watch/issue_watch_card.dart';
import 'package:hinata/features/issues/watch/issue_watch_cubit.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  group('Issue.watcherIds', () {
    test('reads the server list', () {
      final issue = Issue.fromJson(const {
        'id': 'i1',
        'projectId': 'p1',
        'readableId': 'HIN-35',
        'title': 'Vorgänge beobachten',
        'state': 'OPEN',
        'watcherIds': ['u1', 'u2'],
      });
      expect(issue.watcherIds, ['u1', 'u2']);
      expect(issue.isWatchedBy('u2'), isTrue);
      expect(issue.isWatchedBy('u9'), isFalse);
      expect(issue.isWatchedBy(null), isFalse);
    });

    test('defaults to nobody when a server omits the field', () {
      final absent = Issue.fromJson(const {
        'id': 'i1',
        'projectId': 'p1',
        'readableId': 'HIN-1',
        'title': 'x',
        'state': 'OPEN',
      });
      expect(absent.watcherIds, isEmpty);
      expect(absent.isWatchedBy('u1'), isFalse);
    });

    test('survives copyWith and counts towards equality', () {
      final issue = _issue(watcherIds: const ['u1']);
      expect(issue.copyWith().watcherIds, ['u1']);

      final joined = issue.copyWith(watcherIds: const ['u1', 'u2']);
      expect(joined.watcherIds, ['u1', 'u2']);
      // Without this the optimistic rebuild would be swallowed as "no change".
      expect(joined, isNot(issue));
      expect(issue.copyWith(watcherIds: const ['u1']), issue);
    });
  });

  group('IssueWatchCubit', () {
    test('subscribes optimistically, then keeps it', () async {
      final repo = _FakeIssueRepository();
      final cubit = _cubit(repo);
      addTearDown(cubit.close);

      final states = expectLater(
        cubit.stream,
        emitsInOrder([
          isA<IssueWatchState>()
              .having((s) => s.watcherIds, 'watcherIds', ['u2', 'u1'])
              .having((s) => s.busy, 'busy', isTrue),
          isA<IssueWatchState>()
              .having((s) => s.watcherIds, 'watcherIds', ['u2', 'u1'])
              .having((s) => s.busy, 'busy', isFalse)
              .having((s) => s.errorKey, 'errorKey', isNull),
        ]),
      );

      await cubit.toggle();
      await states;
      expect(repo.watched, ['i1']);
      expect(cubit.watching, isTrue);
    });

    test('unsubscribes the other way round', () async {
      final repo = _FakeIssueRepository();
      final cubit = _cubit(repo, watcherIds: const ['u2', 'u1']);
      addTearDown(cubit.close);

      await cubit.toggle();

      expect(repo.unwatched, ['i1']);
      expect(cubit.state.watcherIds, ['u2']);
      expect(cubit.watching, isFalse);
    });

    test(
      'rolls the optimistic subscribe back when the server refuses',
      () async {
        final repo = _FakeIssueRepository(failure: ApiFailure('Kein Zugriff'));
        final cubit = _cubit(repo);
        addTearDown(cubit.close);

        final states = expectLater(
          cubit.stream,
          emitsInOrder([
            // Optimistic: the switch is already on.
            isA<IssueWatchState>().having((s) => s.watcherIds, 'watcherIds', [
              'u2',
              'u1',
            ]),
            // …and back off, carrying the reason for the toast.
            isA<IssueWatchState>()
                .having((s) => s.watcherIds, 'watcherIds', ['u2'])
                .having((s) => s.busy, 'busy', isFalse)
                .having((s) => s.errorKey, 'errorKey', 'Kein Zugriff'),
          ]),
        );

        await cubit.toggle();
        await states;
        expect(cubit.watching, isFalse);
      },
    );

    test(
      'rolls an unsubscribe back too, with a translatable fallback',
      () async {
        final repo = _FakeIssueRepository(failure: StateError('socket'));
        final cubit = _cubit(repo, watcherIds: const ['u2', 'u1']);
        addTearDown(cubit.close);

        await cubit.toggle();

        expect(cubit.state.watcherIds, ['u2', 'u1']);
        expect(cubit.state.errorKey, 'errors.unexpected');
        expect(cubit.watching, isTrue);
      },
    );

    test('ignores a second tap while the first is still in flight', () async {
      final repo = _FakeIssueRepository();
      final cubit = _cubit(repo);
      addTearDown(cubit.close);

      final first = cubit.toggle();
      await cubit.toggle();
      await first;

      // One call, not a subscribe immediately undone by an unsubscribe.
      expect(repo.watched, ['i1']);
      expect(repo.unwatched, isEmpty);
    });

    test('stays inert while there is no signed-in user', () async {
      final repo = _FakeIssueRepository();
      final cubit = IssueWatchCubit(
        repository: repo,
        issueId: 'i1',
        userId: null,
        watcherIds: const ['u2'],
      );
      addTearDown(cubit.close);

      await cubit.toggle();

      expect(repo.watched, isEmpty);
      expect(cubit.state.watcherIds, ['u2']);
    });

    test('adopts a fresh server list, but never mid-flight', () async {
      final repo = _FakeIssueRepository();
      final cubit = _cubit(repo);
      addTearDown(cubit.close);

      cubit.sync(const ['u2', 'u3']);
      expect(cubit.state.watcherIds, ['u2', 'u3']);

      // A reload landing between the tap and the answer must not undo the tap.
      final inFlight = cubit.toggle();
      cubit.sync(const ['u2', 'u3']);
      expect(cubit.state.watcherIds, ['u2', 'u3', 'u1']);
      await inFlight;
    });

    test(
      'keeps a committed subscribe over a payload that predates it',
      () async {
        final repo = _FakeIssueRepository();
        final cubit = _cubit(repo);
        addTearDown(cubit.close);

        await cubit.toggle();
        expect(cubit.watching, isTrue);

        // The response to an edit that left before the toggle: it carries the
        // pre-watch roster, and landing after the toggle it would silently
        // unsubscribe the user on screen while the server has them subscribed.
        cubit.sync(const ['u2', 'u3']);

        expect(cubit.watching, isTrue);
        expect(cubit.state.watcherIds, ['u2', 'u3', 'u1']);
      },
    );

    test('keeps a committed unsubscribe the same way', () async {
      final repo = _FakeIssueRepository();
      final cubit = _cubit(repo, watcherIds: const ['u2', 'u1']);
      addTearDown(cubit.close);

      await cubit.toggle();
      cubit.sync(const ['u2', 'u1', 'u3']);

      expect(cubit.watching, isFalse);
      expect(cubit.state.watcherIds, ['u2', 'u3']);
    });

    test(
      'takes the rest of a stale roster, only pinning the own state',
      () async {
        final repo = _FakeIssueRepository();
        final cubit = _cubit(repo);
        addTearDown(cubit.close);

        await cubit.toggle();
        cubit.sync(const ['u3']);

        // u2 left, u3 joined — that part of the payload is adopted verbatim.
        expect(cubit.state.watcherIds, ['u3', 'u1']);
      },
    );
  });

  group('the watch broadcast', () {
    test('fires once the subscribe is committed', () async {
      final repo = _FakeIssueRepository();
      final cubit = _cubit(repo);
      addTearDown(cubit.close);

      final fired = <void>[];
      final sub = IssueWatchEvents.instance.changes.listen(fired.add);
      addTearDown(sub.cancel);

      await cubit.toggle();
      // The stream is async: give it a turn to deliver before asserting.
      await Future<void>.delayed(Duration.zero);

      expect(fired, hasLength(1));
    });

    test('stays quiet when the server refuses', () async {
      final repo = _FakeIssueRepository(failure: ApiFailure('Kein Zugriff'));
      final cubit = _cubit(repo);
      addTearDown(cubit.close);

      final fired = <void>[];
      final sub = IssueWatchEvents.instance.changes.listen(fired.add);
      addTearDown(sub.cancel);

      await cubit.toggle();
      await Future<void>.delayed(Duration.zero);

      // A rolled-back subscribe changed nothing, so no other screen refetches.
      expect(fired, isEmpty);
    });
  });

  group('the watch card', () {
    testWidgets('flips the switch on tap and shows the watcher count', (
      tester,
    ) async {
      final gate = Completer<void>();
      final repo = _FakeIssueRepository(gate: gate);
      await tester.pumpWidget(_host(repo, _issue(watcherIds: const ['u2'])));

      expect(find.byIcon(LucideIcons.eyeOff), findsOneWidget);
      expect(find.text('issues.watch.watcherCount'), findsOneWidget);

      await tester.tap(find.byType(HiveSwitch));
      await tester.pump();

      // Optimistic: on while the call is still out.
      expect(find.byIcon(LucideIcons.eye), findsOneWidget);

      gate.complete();
      await tester.pump();
      expect(repo.watched, ['i1']);
      expect(find.byIcon(LucideIcons.eye), findsOneWidget);
    });

    testWidgets('puts the switch back when the server refuses', (tester) async {
      final gate = Completer<void>();
      final repo = _FakeIssueRepository(
        failure: ApiFailure('Kein Zugriff'),
        gate: gate,
      );
      await tester.pumpWidget(_host(repo, _issue(watcherIds: const ['u2'])));

      await tester.tap(find.byType(HiveSwitch));
      await tester.pump();
      expect(find.byIcon(LucideIcons.eye), findsOneWidget);

      // Let the refusal land: the switch returns to off and stays there.
      gate.complete();
      await tester.pump();
      expect(find.byIcon(LucideIcons.eyeOff), findsOneWidget);
      expect(find.byIcon(LucideIcons.eye), findsNothing);
      // …and the reason is shown. Widget tests render i18n keys, and a backend
      // message passes through `t` untouched — either way it is the raw string.
      expect(find.text('Kein Zugriff'), findsOneWidget);

      // Sit out the toast's own lifetime so its timer doesn't outlive the test.
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });

    testWidgets('explains that an assignee is already covered', (tester) async {
      final repo = _FakeIssueRepository();
      await tester.pumpWidget(_host(repo, _issue(assigneeIds: const ['u1'])));

      // Widget tests render i18n keys, so assert on the key, not on prose.
      expect(find.text('issues.watch.implicitAssignee'), findsOneWidget);
      expect(find.text('issues.watch.implicitReporter'), findsNothing);
    });

    testWidgets('says the same for the reporter, and nothing for a bystander', (
      tester,
    ) async {
      final repo = _FakeIssueRepository();
      await tester.pumpWidget(_host(repo, _issue(reporterId: 'u1')));
      expect(find.text('issues.watch.implicitReporter'), findsOneWidget);

      await tester.pumpWidget(_host(repo, _issue(reporterId: 'u9')));
      expect(find.text('issues.watch.implicitReporter'), findsNothing);
      expect(find.text('issues.watch.implicitAssignee'), findsNothing);
    });

    testWidgets('reports the committed roster back to its host', (
      tester,
    ) async {
      final repo = _FakeIssueRepository();
      final reported = <List<String>>[];
      await tester.pumpWidget(
        _host(
          repo,
          _issue(watcherIds: const ['u2']),
          onWatchersChanged: reported.add,
        ),
      );

      await tester.tap(find.byType(HiveSwitch));
      await tester.pump();

      expect(reported.last, ['u2', 'u1']);
    });
  });
}

// ── helpers ─────────────────────────────────────────────────────────────────

Issue _issue({
  List<String> watcherIds = const [],
  List<String> assigneeIds = const [],
  String? reporterId,
}) => Issue(
  id: 'i1',
  projectId: 'p1',
  readableId: 'HIN-35',
  title: 'Vorgänge beobachten',
  state: 'OPEN',
  watcherIds: watcherIds,
  assigneeIds: assigneeIds,
  assigneeId: assigneeIds.isEmpty ? null : assigneeIds.first,
  reporterId: reporterId,
);

IssueWatchCubit _cubit(
  IssueRepository repo, {
  List<String> watcherIds = const ['u2'],
}) => IssueWatchCubit(
  repository: repo,
  issueId: 'i1',
  userId: 'u1',
  watcherIds: watcherIds,
);

Widget _host(
  IssueRepository repo,
  Issue issue, {
  ValueChanged<List<String>>? onWatchersChanged,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: RepositoryProvider<IssueRepository>.value(
    value: repo,
    child: Scaffold(
      body: IssueWatchCard(
        issue: issue,
        currentUserId: 'u1',
        names: const {'u1': 'Rebar', 'u2': 'Mia'},
        onWatchersChanged: onWatchersChanged,
      ),
    ),
  ),
);

/// Records the calls the toggle makes and can be told to refuse them.
class _FakeIssueRepository implements IssueRepository {
  _FakeIssueRepository({this.failure, this.gate});

  /// Thrown by both calls when set — an [ApiFailure] for a server refusal, or
  /// anything else for the "unexpected" path.
  final Object? failure;

  /// Holds the call open so a widget test can look at the optimistic frame
  /// before the answer lands.
  final Completer<void>? gate;
  final List<String> watched = [];
  final List<String> unwatched = [];

  @override
  Future<void> watchIssue(String id) async {
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    watched.add(id);
  }

  @override
  Future<void> unwatchIssue(String id) async {
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    unwatched.add(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
