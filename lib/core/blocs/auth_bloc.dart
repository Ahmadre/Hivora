import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../api/api_client.dart';
import '../models/core_models.dart';
import '../repositories/auth_repository.dart';
import '../storage/app_storage.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class AuthChecked extends AuthEvent {
  const AuthChecked();
}

class LoginSubmitted extends AuthEvent {
  const LoginSubmitted(this.identifier, this.password);

  final String identifier;
  final String password;

  @override
  List<Object?> get props => [identifier];
}

/// A 2FA code entered to complete a login challenge.
class TwoFactorSubmitted extends AuthEvent {
  const TwoFactorSubmitted(this.code);

  final String code;

  @override
  List<Object?> get props => [code];
}

/// Tokens arriving via the SSO deep link (hinata://auth-callback).
class SsoTokensReceived extends AuthEvent {
  const SsoTokensReceived(this.accessToken, this.refreshToken);

  final String accessToken;
  final String refreshToken;
}

class LogoutRequested extends AuthEvent {
  const LogoutRequested();
}

enum AuthStatus {
  unknown,
  unauthenticated,
  authenticating,
  twoFactorRequired,
  authenticated,
}

class AuthState extends Equatable {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.errorKey,
    this.mfaToken,
  });

  final AuthStatus status;
  final AuthUser? user;
  final String? errorKey;

  /// Short-lived challenge token while [status] is [AuthStatus.twoFactorRequired].
  final String? mfaToken;

  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    String? errorKey,
    String? mfaToken,
  }) => AuthState(
    status: status ?? this.status,
    user: user ?? this.user,
    errorKey: errorKey,
    mfaToken: mfaToken ?? this.mfaToken,
  );

  @override
  List<Object?> get props => [status, user, errorKey, mfaToken];
}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({required this.repository, required this.storage})
    : super(const AuthState()) {
    on<AuthChecked>(_onChecked, transformer: restartable());
    on<LoginSubmitted>(_onLogin, transformer: droppable());
    on<TwoFactorSubmitted>(_onTwoFactor, transformer: droppable());
    on<SsoTokensReceived>(_onSsoTokens, transformer: droppable());
    on<LogoutRequested>(_onLogout);
  }

  final AuthRepository repository;
  final AppStorage storage;

  Future<void> _onChecked(AuthChecked event, Emitter<AuthState> emit) async {
    if (storage.accessToken == null) {
      emit(const AuthState(status: AuthStatus.unauthenticated));
      return;
    }
    // This handler MUST always reach an emit. It is the step every sign-in ends
    // on (SSO handoff included), and the states it runs from — `unknown` at
    // boot, `authenticating` after tokens arrive — both render as a spinner or
    // a fully disabled login form. An error that escapes here emits nothing at
    // all, and the app is left on that spinner permanently. So the failure is
    // caught in full, not just the ApiFailure the happy path expects: an
    // unexpected response shape (a cast that throws) hangs the app exactly the
    // same way a 401 would, and neither may end the turn without a state.
    AuthUser? user;
    var rejected = false;
    try {
      user = await repository.me();
    } on ApiFailure {
      // The server refused this token — it is genuinely dead, so drop it.
      rejected = true;
    } catch (_) {
      // Anything else (malformed body, transport oddity): don't destroy the
      // session over it, just fall back to signed-out so the UI is usable and
      // the user can retry.
    }
    if (rejected) await storage.clearTokens();
    if (emit.isDone) return;
    emit(
      user == null
          ? const AuthState(status: AuthStatus.unauthenticated)
          : AuthState(status: AuthStatus.authenticated, user: user),
    );
  }

  Future<void> _onLogin(LoginSubmitted event, Emitter<AuthState> emit) async {
    emit(const AuthState(status: AuthStatus.authenticating));
    try {
      final result = await repository.login(event.identifier, event.password);
      if (result.mfaRequired) {
        emit(
          AuthState(
            status: AuthStatus.twoFactorRequired,
            mfaToken: result.mfaToken,
          ),
        );
        return;
      }
      await storage.setTokens(access: result.access!, refresh: result.refresh!);
      emit(AuthState(status: AuthStatus.authenticated, user: result.user));
    } on ApiFailure catch (failure) {
      emit(_loginFailure(failure));
    }
  }

  Future<void> _onTwoFactor(
    TwoFactorSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    final token = state.mfaToken;
    if (token == null) return;
    emit(state.copyWith(status: AuthStatus.authenticating));
    try {
      final result = await repository.verifyTwoFactor(token, event.code);
      await storage.setTokens(access: result.access, refresh: result.refresh);
      emit(AuthState(status: AuthStatus.authenticated, user: result.user));
    } on ApiFailure catch (failure) {
      // Stay on the challenge so the user can re-enter the code.
      emit(
        AuthState(
          status: AuthStatus.twoFactorRequired,
          mfaToken: token,
          errorKey: failure.statusCode == 401
              ? 'auth.invalidTwoFactorCode'
              : failure.message,
        ),
      );
    }
  }

  AuthState _loginFailure(ApiFailure failure) => AuthState(
    status: AuthStatus.unauthenticated,
    errorKey: failure.statusCode == 401
        ? 'auth.invalidCredentials'
        : failure.statusCode == 429
        ? 'auth.tooManyAttempts'
        : failure.message,
  );

  Future<void> _onSsoTokens(
    SsoTokensReceived event,
    Emitter<AuthState> emit,
  ) async {
    try {
      await storage.setTokens(
        access: event.accessToken,
        refresh: event.refreshToken,
      );
    } catch (_) {
      // The keychain refused the write. Rare, but it must not end the turn
      // without a state: this handler is the last step of an SSO sign-in, and
      // the callback screen sits on a spinner until the bloc answers.
      emit(const AuthState(status: AuthStatus.unauthenticated));
      return;
    }
    // Emit a transient "authenticating" BEFORE re-checking. _onChecked ends with
    // emit(AuthState(authenticated, user)); if that user equals a previous
    // attempt's, Equatable suppresses the emit, so auth.stream stays silent and
    // the router's refreshListenable never re-runs the redirect — the tokens are
    // stored yet the user is left on /login (only an app restart, which
    // re-evaluates the redirect fresh, then "fixes" it). This transient state
    // guarantees the following `authenticated` is always a distinct emit, so the
    // redirect always re-runs and navigates to the dashboard.
    emit(const AuthState(status: AuthStatus.authenticating));
    add(const AuthChecked());
  }

  Future<void> _onLogout(LogoutRequested event, Emitter<AuthState> emit) async {
    await storage.clearTokens();
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }
}
