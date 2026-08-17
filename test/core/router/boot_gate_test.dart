/// A deep link survives the boot, whatever order the boot happens to take.
///
/// The report this comes from: tapping a link in a notification e-mail launched
/// the app and then nothing happened — it sat on the dashboard. With the app
/// already running the very same link worked, which is the tell: the link is
/// fine, the *boot* is where it gets lost. So these walk the orderings a cold
/// start can take (server still connecting, session still being re-checked, a
/// server switch the link itself triggers) and insist the destination comes back
/// out the other end.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/router/app_router.dart';

void main() {
  late BootGate gate;

  setUp(() => gate = BootGate());

  /// One redirect evaluation, with the defaults of a returning user: a saved
  /// server, onboarding behind them, a session on disk.
  String? at(
    String location, {
    String? uri,
    AppConfigStatus config = AppConfigStatus.ready,
    AuthStatus auth = AuthStatus.authenticated,
    bool hasServerUrl = true,
    bool onboardingDone = true,
  }) => gate.redirect(
    location: location,
    uri: uri ?? location,
    config: config,
    auth: auth,
    hasServerUrl: hasServerUrl,
    onboardingDone: onboardingDone,
  );

  const issue = '/issues/HIN-4?comment=c1';

  group('cold start', () {
    test('holds the link while the server is still being verified', () {
      // Boot: the router starts at /dashboard and is sent to the splash.
      expect(at('/dashboard', config: AppConfigStatus.initial), '/connecting');
      // The launch link arrives before the app is in any state to show it.
      expect(
        at('/issues/HIN-4', uri: issue, config: AppConfigStatus.connecting),
        '/connecting',
      );
      // Server verified, session restored — and there it is.
      expect(at('/connecting'), issue);
    });

    test('holds the link while the session is still being re-checked', () {
      expect(
        at('/issues/HIN-4', uri: issue, auth: AuthStatus.unknown),
        '/login',
      );
      expect(at('/login'), issue);
    });

    test('hands the link back to a screen that saw itself home', () {
      // Some gate screens don't wait to be redirected off themselves — they
      // navigate the moment their job is done: onboarding calls go('/dashboard')
      // from onDone, and the invite / reset-password / verify-email screens do
      // the same once they have signed the user in. By the time the app is
      // finally ready + authenticated the location is /dashboard, which is not a
      // gate — and a rule that only handed the link back *at a gate* left it
      // parked for the rest of the session. From the outside: the app opened,
      // and did nothing.
      expect(
        at('/issues/HIN-4', uri: issue, auth: AuthStatus.unknown),
        '/login',
      );
      expect(at('/dashboard'), issue);
    });

    test('holds the link across the update and setup gates', () {
      expect(
        at('/issues/HIN-4', uri: issue, config: AppConfigStatus.updateRequired),
        '/update',
      );
      expect(at('/update'), issue);

      expect(
        at('/issues/HIN-4', uri: issue, config: AppConfigStatus.needsSetup),
        '/setup',
      );
      expect(at('/setup'), issue);
    });

    test('holds the link across the connect + onboarding gates', () {
      expect(
        at(
          '/issues/HIN-4',
          uri: issue,
          config: AppConfigStatus.needsServerUrl,
          hasServerUrl: false,
        ),
        '/connect',
      );
      expect(at('/connect', onboardingDone: false), '/onboarding');
      expect(at('/onboarding'), issue);
    });

    test('survives the whole gauntlet in one go', () {
      // connecting → login → ready + authenticated, link arriving at the worst
      // possible moment in the middle of it.
      expect(
        at('/dashboard', config: AppConfigStatus.connecting),
        '/connecting',
      );
      expect(
        at('/issues/HIN-4', uri: issue, config: AppConfigStatus.connecting),
        '/connecting',
      );
      expect(at('/connecting', auth: AuthStatus.unknown), '/login');
      expect(at('/login', auth: AuthStatus.authenticating), null);
      expect(at('/login'), issue);
    });
  });

  group('once the app is up', () {
    test('lets a deep link render straight away', () {
      expect(at('/issues/HIN-4', uri: issue), null);
    });

    test('sends an idle gate visit home', () {
      expect(at('/connecting'), '/dashboard');
    });

    test('never bounces the dashboard through the parking slot', () {
      // /dashboard is where the router starts, not somewhere the user asked to
      // go — parking it would overwrite a real destination with the default.
      expect(
        at('/dashboard', config: AppConfigStatus.connecting),
        '/connecting',
      );
      expect(gate.pendingDeepLink, isNull);
      expect(at('/connecting'), '/dashboard');
    });

    test('does not redirect a parked link onto itself', () {
      expect(
        at('/issues/HIN-4', uri: issue, config: AppConfigStatus.connecting),
        '/connecting',
      );
      // Evaluated at the parked destination itself: returning it again would be
      // a redirect loop, so it is consumed and the page just renders.
      expect(at('/issues/HIN-4', uri: issue), null);
      expect(gate.pendingDeepLink, isNull);
    });

    test('follows a second deep link rather than the first one again', () {
      expect(
        at('/issues/HIN-4', uri: issue, config: AppConfigStatus.connecting),
        '/connecting',
      );
      expect(
        at('/knowledge/a1', config: AppConfigStatus.connecting),
        '/connecting',
      );
      expect(at('/connecting'), '/knowledge/a1');
    });
  });

  group('public flows are never gated', () {
    for (final route in ['/invite', '/reset-password', '/verify-email']) {
      test('$route renders on a cold, signed-out app', () {
        expect(
          at(
            route,
            uri: '$route?token=t1&server=https://s',
            config: AppConfigStatus.initial,
            auth: AuthStatus.unauthenticated,
            hasServerUrl: false,
            onboardingDone: false,
          ),
          null,
        );
      });
    }

    test(
      '/auth-callback holds its tokens until they have signed the user in',
      () {
        expect(
          at(
            '/auth-callback',
            uri: '/auth-callback?code=abc',
            config: AppConfigStatus.connecting,
            auth: AuthStatus.unknown,
          ),
          null,
        );
        // Signed in: the callback screen is done, so it goes home like any gate.
        expect(
          at('/auth-callback', uri: '/auth-callback?code=abc'),
          '/dashboard',
        );
      },
    );
  });
}
