import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/repositories/auth_repository.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/core/router/app_router.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Two routes exist because a store policy says they must, and nothing else in
/// the app links to them by name — so nothing else would notice if one were
/// dropped in a refactor. `/terms` is the non-skippable acceptance gate;
/// `/settings/blocked` is the only way back out of a block.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Walks the whole route tree (routes nest under the app's single ShellRoute)
  /// and collects every registered path.
  Set<String> pathsOf(List<RouteBase> routes) {
    final paths = <String>{};
    for (final route in routes) {
      if (route is GoRoute) paths.add(route.path);
      paths.addAll(pathsOf(route.routes));
    }
    return paths;
  }

  test('registers the terms gate and the block list', () async {
    SharedPreferences.setMockInitialValues({'server_url': 'https://a.test'});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = AppStorage(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
    // Neither bloc is started, so nothing here touches the network; the router
    // only needs them to exist for its redirect closure.
    final router = buildRouter(
      appConfig: AppConfigBloc(repository: _FakeMeta(), storage: storage),
      auth: AuthBloc(repository: _FakeAuth(), storage: storage),
      storage: storage,
    );

    final paths = pathsOf(router.configuration.routes);
    expect(paths, contains('/terms'));
    expect(paths, contains('/settings/blocked'));
  });
}

class _FakeMeta implements MetaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeAuth implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
