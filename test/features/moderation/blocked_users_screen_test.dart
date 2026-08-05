import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/moderation_models.dart';
import 'package:hinata/core/repositories/moderation_repository.dart';
import 'package:hinata/core/widgets/hive_empty_state.dart';
import 'package:hinata/features/moderation/blocked_users_screen.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The block list is the only way back out of a block, so the states that
/// matter are the boring ones: nothing blocked, a handful blocked, and a failed
/// load. It reads a flat list — the server has no paged block endpoint — and the
/// screen has to hold together at every width without one.
///
/// Widget tests render i18n *keys*, which are longer than any real label, so
/// nothing here asserts on text: the probes are the unblock control on each row
/// and the branded empty state, plus `takeException` for overflow.
void main() {
  BlockedUser user(String id, String name) =>
      BlockedUser(userId: id, displayName: name, username: name.toLowerCase());

  Widget host(_FakeModerationRepository repository, {Size? size}) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: MediaQuery(
      data: MediaQueryData(size: size ?? const Size(390, 800)),
      child: RepositoryProvider<ModerationRepository>.value(
        value: repository,
        child: const Scaffold(body: BlockedUsersScreen()),
      ),
    ),
  );

  /// The unblock control — one per blocked person.
  final unblock = find.byIcon(LucideIcons.userCheck);

  testWidgets('lists one row per blocked person', (tester) async {
    final repository = _FakeModerationRepository([
      user('u1', 'Ada'),
      user('u2', 'Bob'),
    ]);

    await tester.pumpWidget(host(repository));
    await tester.pumpAndSettle();

    expect(unblock, findsNWidgets(2));
    expect(find.byType(HiveEmptyState), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the branded empty state when nothing is blocked', (
    tester,
  ) async {
    await tester.pumpWidget(host(_FakeModerationRepository(const [])));
    await tester.pumpAndSettle();

    expect(find.byType(HiveEmptyState), findsOneWidget);
    expect(unblock, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unblocking calls the server and drops the row', (tester) async {
    final repository = _FakeModerationRepository([
      user('u1', 'Ada'),
      user('u2', 'Bob'),
    ]);

    await tester.pumpWidget(host(repository));
    await tester.pumpAndSettle();
    await tester.tap(unblock.first);
    await tester.pumpAndSettle();

    expect(repository.unblocked, ['u1']);
    // Removed locally rather than refetched: the server holds the whole list,
    // so there is no paging to keep in step — and one round trip is exactly how
    // long a lifted block would keep looking like it was still in force.
    expect(repository.loads, 1);
    expect(unblock, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed load offers a retry instead of an empty list', (
    tester,
  ) async {
    final repository = _FakeModerationRepository(
      const [],
      failure: ApiFailure('errors.connection'),
    );

    await tester.pumpWidget(host(repository));
    await tester.pumpAndSettle();

    // Not the empty state: "nothing is blocked" and "we could not ask" are
    // different answers, and only one of them is safe to believe.
    expect(find.byType(HiveEmptyState), findsNothing);
    expect(find.byType(OutlinedButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in <double>[320, 390, 768, 1440]) {
    testWidgets('lays out without overflow at ${width}px', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(
          _FakeModerationRepository([
            user('u1', 'Ada Lovelace'),
            user('u2', 'Bartholomew Featherstonehaugh'),
          ]),
          size: Size(width, 900),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }
}

class _FakeModerationRepository implements ModerationRepository {
  _FakeModerationRepository(this._users, {this.failure});

  final List<BlockedUser> _users;
  final ApiFailure? failure;

  /// How many times the screen asked the server for the list.
  int loads = 0;
  final List<String> unblocked = [];

  @override
  Future<List<BlockedUser>> blockedUsers() async {
    loads++;
    if (failure != null) throw failure!;
    return _users;
  }

  @override
  Future<void> unblockUser(String userId) async => unblocked.add(userId);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
