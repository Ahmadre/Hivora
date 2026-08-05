import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/widgets/hive_loader.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/blocs/auth_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/repositories/auth_repository.dart';
import 'auth_shell.dart';

/// Outcome of every handoff code this process has tried: absent = untouched,
/// null = a redemption is in flight, true/false = it finished.
///
/// The same callback can arrive twice — app_links hands a cold-start link to
/// both `getInitialLink()` and `uriLinkStream`, and a router refresh can rebuild
/// this route — and the code is single-use, so a second POST is guaranteed to
/// fail. Without this ledger that second failure papers over the first
/// redemption's success and throws the signed-in user back to the login screen.
final Map<String, bool?> _handoffAttempts = <String, bool?>{};

/// How long the sign-in may take before we stop waiting. Covers the redeem POST
/// (10s connect + 20s receive) plus the `/me` check that follows it, with room
/// to spare — anything past this is a stall, not a slow network.
const _handoffTimeout = Duration(seconds: 45);

/// Landing screen for the SSO flow: after a successful identity-provider login
/// the server redirects to `<origin>/auth-callback?code=...` (web) or
/// `hinata://auth-callback?code=...` (native). The `code` is a single-use
/// handoff token; this screen redeems it for the real access/refresh pair via a
/// POST (so bearer tokens never travel in the URL) and hands them to
/// [AuthBloc], which routes the now-authenticated user to the dashboard.
///
/// This screen owns its own way out. The router deliberately allows
/// `/auth-callback` for an unauthenticated user (it has to — the user is
/// mid-sign-in), which means a failed handoff is NOT corrected by a redirect:
/// nothing else will ever move the user off this route. Every failure path here
/// must therefore navigate to `/login` itself, or the user is left staring at a
/// spinner forever with the app unusable.
class SsoCallbackScreen extends StatefulWidget {
  const SsoCallbackScreen({
    super.key,
    this.code,
    required this.accessToken,
    required this.refreshToken,
  });

  /// Single-use handoff code; redeemed for the token pair. Preferred path.
  final String? code;

  /// Legacy fallback: tokens directly in the URL (older server redirects).
  final String? accessToken;
  final String? refreshToken;

  @override
  State<SsoCallbackScreen> createState() => _SsoCallbackScreenState();
}

class _SsoCallbackScreenState extends State<SsoCallbackScreen> {
  // Captured up front so the sign-in never depends on this widget still being
  // mounted: a second delivery of the same link replaces this route while the
  // redeem POST is still in flight, and the tokens it comes back with must
  // still reach the bloc. They belong to the app, not to this screen.
  late final AuthBloc _auth;
  late final AuthRepository _repository;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    // Resolved eagerly, while the element is certainly alive — a lazy `late`
    // would run the lookup on whichever code path touches it first, which may
    // be after this screen was replaced.
    _auth = context.read<AuthBloc>();
    _repository = context.read<AuthRepository>();
    final code = widget.code;
    final access = widget.accessToken;
    final refresh = widget.refreshToken;
    // Nothing can hold this screen longer than the timeout, whatever goes wrong
    // below — a redeem that never settles, a bloc that never emits, a server
    // that accepts the connection and then goes quiet.
    _watchdog = Timer(_handoffTimeout, () => _bail('auth.ssoTimedOut'));
    if (code != null && code.isNotEmpty) {
      if (_handoffAttempts.containsKey(code)) {
        switch (_handoffAttempts[code]) {
          // Still in flight on the instance we replaced — it drives the bloc,
          // so just wait for it (the watchdog bounds the wait).
          case null:
            break;
          // Already redeemed: the tokens are stored, so re-check the session
          // instead of burning this screen on a POST that must fail.
          case true:
            _auth.add(const AuthChecked());
          // Already failed once; a single-use code will not start working.
          case false:
            _bail('auth.ssoExchangeFailed');
        }
      } else {
        _redeem(code);
      }
    } else if (access != null && refresh != null) {
      // Legacy redirect that still carried tokens in the URL.
      _auth.add(SsoTokensReceived(access, refresh));
    } else {
      // Nothing usable in the URL: back to login.
      _bail('auth.ssoNoCode');
    }
  }

  Future<void> _redeem(String code) async {
    _handoffAttempts[code] = null;
    try {
      final pair = await _repository.exchangeSso(code);
      _handoffAttempts[code] = true;
      // Deliberately not gated on `mounted`: if a duplicate delivery replaced
      // this screen mid-request, dropping the tokens here would waste the one
      // redemption the code has and strand the user.
      _auth.add(SsoTokensReceived(pair.access, pair.refresh));
    } catch (_) {
      // Invalid / expired / replayed code, or the exchange never reached the
      // server. Either way this sign-in is over — send the user back to the
      // login screen with a reason instead of spinning forever.
      _handoffAttempts[code] = false;
      _bail('auth.ssoExchangeFailed');
    }
  }

  /// Leaves the callback screen for `/login`, carrying [reasonKey] so the login
  /// screen can explain what happened. Nothing else navigates away from this
  /// route, so this is the only exit from a failed handoff.
  void _bail(String reasonKey) {
    _watchdog?.cancel();
    // Deferred: this is reachable straight from initState (no usable code in
    // the URL), and navigating while the route is still being built throws.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // A concurrent redemption may have signed the user in while this failure
      // was on its way; bouncing to /login would undo it.
      if (_auth.state.status == AuthStatus.authenticated) return;
      // Settle the auth state too: a half-finished handoff can leave the bloc in
      // `authenticating`, which renders the login screen with every control
      // disabled — a second dead end right behind this one.
      _auth.add(const AuthChecked());
      GoRouter.of(context).go('/login?ssoError=$reasonKey');
    });
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      maxContentWidth: 360,
      child: AuthGlassCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const HiveLoader(),
            const SizedBox(height: 16),
            Text(context.t('auth.signingIn'), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
