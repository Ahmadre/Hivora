import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../models/account_models.dart';
import '../models/personal_access_token.dart';

/// The signed-in user's self-service account surface (`/me`): profile, avatar,
/// sessions, notification preferences, 2FA management, access overview, GDPR,
/// and personal access tokens.
class AccountRepository {
  AccountRepository(this._api);

  final ApiClient _api;

  Future<Me> meAccount() async =>
      Me.fromJson(await _api.get('/api/v1/me') as Map<String, dynamic>);

  Future<Me> updateMyProfile({
    String? displayName,
    String? title,
    String? pronouns,
    String? locale,
  }) async => Me.fromJson(
    await _api.patch(
          '/api/v1/me',
          body: {
            'displayName': ?displayName,
            'title': ?title,
            'pronouns': ?pronouns,
            'locale': ?locale,
          },
        )
        as Map<String, dynamic>,
  );

  /// Uploads a new profile picture; the server compresses + stores it and
  /// returns the (relative) avatar URL. [onProgress] reports 0–1 upload progress.
  Future<String> uploadAvatar(
    MultipartFile file, {
    void Function(double pct)? onProgress,
  }) async =>
      ((await _api.upload(
                '/api/v1/me/avatar',
                file,
                onSendProgress: onProgress == null
                    ? null
                    : (sent, total) => onProgress(total > 0 ? sent / total : 0),
              ))
              as Map<String, dynamic>)['avatarUrl']
          as String;

  /// Removes the current profile picture.
  Future<void> deleteAvatar() => _api.delete('/api/v1/me/avatar');

  /// Starts a double-opt-in change of the sign-in email (mails the new address).
  Future<void> requestEmailChange(String newEmail) =>
      _api.post('/api/v1/me/email-change', body: {'newEmail': newEmail});

  /// Emails a one-time password-reset link (LOCAL accounts only).
  Future<void> sendPasswordReset() => _api.post('/api/v1/me/password-reset');

  /// One page of device sessions, most recently active first.
  ///
  /// Paginated end to end: the list grows with every browser and every
  /// reinstall, and the settings screen shows only the first few until the
  /// reader asks for the rest.
  Future<({List<DeviceSession> items, int total})> sessionsPage({
    int page = 0,
    int size = 25,
  }) async {
    final data =
        await _api.get(
              '/api/v1/me/sessions',
              query: {'page': page, 'size': size},
            )
            as Map<String, dynamic>;
    return (
      items: ((data['content'] as List<dynamic>?) ?? [])
          .map((s) => DeviceSession.fromJson(s as Map<String, dynamic>))
          .toList(),
      total: data['totalElements'] as int? ?? 0,
    );
  }

  Future<void> revokeSession(String id) =>
      _api.delete('/api/v1/me/sessions/$id');

  Future<void> revokeOtherSessions() =>
      _api.post('/api/v1/me/sessions/revoke-others');

  Future<NotifPrefs> notificationPrefs() async => NotifPrefs.fromJson(
    await _api.get('/api/v1/me/notification-preferences')
        as Map<String, dynamic>,
  );

  Future<NotifPrefs> saveNotificationPrefs(NotifPrefs prefs) async =>
      NotifPrefs.fromJson(
        await _api.put(
              '/api/v1/me/notification-preferences',
              body: prefs.toJson(),
            )
            as Map<String, dynamic>,
      );

  // 2FA (TOTP) ----------------------------------------------------------------

  Future<TotpSetup> beginTotpSetup() async => TotpSetup.fromJson(
    await _api.post('/api/v1/me/2fa/totp/setup') as Map<String, dynamic>,
  );

  /// Verifies the first code, enabling 2FA. Returns the one-time recovery codes.
  Future<List<String>> verifyTotpSetup(String code) async =>
      (((await _api.post('/api/v1/me/2fa/totp/verify', body: {'code': code}))
                  as Map<String, dynamic>)['recoveryCodes']
              as List<dynamic>)
          .cast<String>();

  Future<List<String>> regenerateRecoveryCodes(String code) async =>
      (((await _api.post(
                    '/api/v1/me/2fa/recovery-codes/regenerate',
                    body: {'code': code},
                  ))
                  as Map<String, dynamic>)['recoveryCodes']
              as List<dynamic>)
          .cast<String>();

  Future<void> disableTotp(String code) =>
      _api.post('/api/v1/me/2fa/disable', body: {'code': code});

  // Access overview -----------------------------------------------------------

  Future<List<AccessTeam>> myTeams() async =>
      ((await _api.get('/api/v1/me/teams')) as List<dynamic>)
          .map((t) => AccessTeam.fromJson(t as Map<String, dynamic>))
          .toList();

  Future<List<AccessProject>> myProjects() async =>
      ((await _api.get('/api/v1/me/projects')) as List<dynamic>)
          .map((p) => AccessProject.fromJson(p as Map<String, dynamic>))
          .toList();

  // GDPR ----------------------------------------------------------------------

  /// Requests an async data report (Art. 15); the user is emailed when ready.
  Future<void> requestDataReport() => _api.post('/api/v1/me/data-report');

  /// Erases the account (Art. 17). The body must literally be `DELETE`.
  Future<void> deleteMyAccount() =>
      _api.delete('/api/v1/me', body: {'confirm': 'DELETE'});

  // Personal access tokens (MCP) ------------------------------------------------

  /// The caller's Personal Access Tokens (metadata only; secrets never returned).
  Future<List<PersonalAccessToken>> listPats() async =>
      ((await _api.get('/api/v1/me/pats')) as List<dynamic>)
          .map((p) => PersonalAccessToken.fromJson(p as Map<String, dynamic>))
          .toList();

  /// Mints a new PAT. [ttlDays] null → the server's default lifetime; a value
  /// ≤ 0 → never expires. Returns the one-time plaintext token plus its metadata;
  /// the plaintext is only ever available here.
  Future<CreatedPat> createPat({
    required String name,
    required List<String> scopes,
    int? ttlDays,
  }) async => CreatedPat.fromJson(
    await _api.post(
          '/api/v1/me/pats',
          body: {'name': name, 'scopes': scopes, 'ttlDays': ttlDays},
        )
        as Map<String, dynamic>,
  );

  /// Revokes a PAT by id (soft: the token is disabled but stays in the list).
  Future<void> revokePat(String id) => _api.delete('/api/v1/me/pats/$id');

  /// Permanently deletes a PAT by id, removing it from the caller's list.
  Future<void> deletePat(String id) =>
      _api.delete('/api/v1/me/pats/$id/permanent');

  /// Raw SSE byte stream of account-level events for the signed-in user (parse
  /// with [parseSse]). Currently carries the `logout` frame the server pushes
  /// when this device's session is revoked, for real-time sign-out. Cancel via
  /// [cancelToken] on logout / app teardown.
  Future<Stream<List<int>>> meEventStream({CancelToken? cancelToken}) =>
      _api.openEventStream('/api/v1/me/stream', cancelToken: cancelToken);
}
