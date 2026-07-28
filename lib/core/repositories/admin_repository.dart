import 'package:dio/dio.dart' show MultipartFile;

import '../api/api_client.dart';
import '../models/admin_user_models.dart';
import '../models/audit_models.dart';
import '../models/ingest_models.dart';

/// Administration: platform settings, user management, and the security audit
/// log.
class AdminRepository {
  AdminRepository(this._api);

  final ApiClient _api;

  Future<Map<String, dynamic>> adminSettings() async =>
      await _api.get('/api/v1/admin/settings') as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateAdminSettings(
    Map<String, dynamic> settings,
  ) async =>
      await _api.put('/api/v1/admin/settings', body: settings)
          as Map<String, dynamic>;

  /// Uploads an organization logo into the server's object storage and returns
  /// the internal, cache-busted logo URL to write back into
  /// `settings['general']['logoUrl']`. The server serves it same-origin via
  /// `/api/v1/meta/logo`, so it works on web without CORS.
  Future<String> uploadOrganizationLogo(MultipartFile file) async {
    final result =
        await _api.upload('/api/v1/admin/settings/logo', file)
            as Map<String, dynamic>;
    return result['logoUrl'] as String;
  }

  /// Removes an uploaded logo (deletes the stored object and clears the URL).
  Future<void> deleteOrganizationLogo() =>
      _api.delete('/api/v1/admin/settings/logo');

  // --- Hinata Connect (push + universal-link relay) ------------------------------

  /// Enrolment/verification state of this instance with Hinata Connect.
  Future<Map<String, dynamic>> connectStatus() async =>
      await _api.get('/api/v1/admin/connect') as Map<String, dynamic>;

  /// Exchanges a one-time enrolment token from the Connect portal for this
  /// instance's credentials (persisted server-side; the token is never stored).
  Future<Map<String, dynamic>> connectEnroll(String token) async =>
      await _api.post('/api/v1/admin/connect/enroll', body: {'token': token})
          as Map<String, dynamic>;

  /// Drops the local enrolment (the portal side is revoked by the operator).
  Future<Map<String, dynamic>> connectDisconnect() async =>
      await _api.delete('/api/v1/admin/connect') as Map<String, dynamic>;

  /// Starts the automated "Jetzt verbinden" handshake and returns
  /// `{portalUrl, expiresAt}` — the portal URL the admin opens to approve. The
  /// server then collects its credentials over the back channel; the app just
  /// watches [connectStatus] until `enrolled` flips.
  Future<Map<String, dynamic>> connectHandshakeStart() async =>
      await _api.post('/api/v1/admin/connect/handshake/start')
          as Map<String, dynamic>;

  /// Cancels an in-flight handshake and returns the refreshed connect status.
  Future<Map<String, dynamic>> connectHandshakeCancel() async =>
      await _api.delete('/api/v1/admin/connect/handshake')
          as Map<String, dynamic>;

  // --- E-mail-to-ticket connections ---------------------------------------------

  Future<List<IngestConnection>> ingestConnections() async =>
      ((await _api.get('/api/v1/admin/ingest-connections')) as List<dynamic>)
          .map((e) => IngestConnection.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<IngestConnection> createIngestConnection(
    IngestConnection connection,
  ) async => IngestConnection.fromJson(
    await _api.post(
          '/api/v1/admin/ingest-connections',
          body: connection.toJson(),
        )
        as Map<String, dynamic>,
  );

  Future<IngestConnection> updateIngestConnection(
    IngestConnection connection,
  ) async => IngestConnection.fromJson(
    await _api.put(
          '/api/v1/admin/ingest-connections/${connection.id}',
          body: connection.toJson(),
        )
        as Map<String, dynamic>,
  );

  Future<void> deleteIngestConnection(String id) =>
      _api.delete('/api/v1/admin/ingest-connections/$id');

  /// Re-reads an existing connection's mailbox now and rebuilds the description
  /// of every ticket whose source e-mail is still present, using the current
  /// parser. Repairs tickets ingested while HTML handling was broken. Seen flags
  /// are untouched and manual edits are preserved. When [createMissing] is true
  /// the caller also opts into (re-)creating tickets for e-mails that currently
  /// have none — otherwise no new tickets are created. Returns how many messages
  /// were scanned, how many descriptions changed, and how many tickets were made.
  Future<({int scanned, int updated, int created})> reprocessIngestConnection(
    String id, {
    bool createMissing = false,
  }) async {
    final result =
        await _api.post(
              '/api/v1/admin/ingest-connections/$id/reprocess?createMissing=$createMissing',
            )
            as Map<String, dynamic>;
    return (
      scanned: (result['scanned'] as num?)?.toInt() ?? 0,
      updated: (result['updated'] as num?)?.toInt() ?? 0,
      created: (result['created'] as num?)?.toInt() ?? 0,
    );
  }

  /// Lists the mailbox's folders. Live-connects to the mail server, so only
  /// called after the admin explicitly consented to a scan. A blank password
  /// with a known [connectionId] reuses the stored one.
  Future<List<String>> probeIngestFolders({
    String? connectionId,
    required String host,
    required int port,
    required bool ssl,
    required String username,
    String? password,
  }) async {
    final result =
        await _api.post(
              '/api/v1/admin/ingest-connections/probe-folders',
              body: {
                'connectionId': ?connectionId,
                'host': host,
                'port': port,
                'ssl': ssl,
                'username': username,
                'password': ?(password == null || password.isEmpty
                    ? null
                    : password),
              },
            )
            as Map<String, dynamic>;
    return ((result['folders'] as List<dynamic>?) ?? const [])
        .map((e) => e.toString())
        .toList();
  }

  /// One page of project options for the connection editor's picker.
  Future<({List<IngestProjectOption> items, int total})> ingestProjectOptions({
    String query = '',
    int page = 0,
    int size = 25,
  }) async {
    final result =
        await _api.get(
              '/api/v1/admin/ingest-connections/projects',
              query: {
                'q': ?(query.trim().isEmpty ? null : query.trim()),
                'page': '$page',
                'size': '$size',
              },
            )
            as Map<String, dynamic>;
    return (
      items: ((result['items'] as List<dynamic>?) ?? const [])
          .map((e) => IngestProjectOption.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (result['total'] as num?)?.toInt() ?? 0,
    );
  }

  // --- User management --------------------------------------------------------

  /// One page of the platform user directory + global KPI counts. Filter/sort/
  /// paginate server-side; a blank [query] / null filters return everything.
  Future<AdminUserPage> adminUsersPage({
    String query = '',
    AdminRole? role,
    UserStatus? status,
    UserOrigin? origin,
    UserSortKey sort = UserSortKey.lastActive,
    bool desc = true,
    int page = 1,
    int perPage = 25,
  }) async => AdminUserPage.fromJson(
    await _api.get(
          '/api/v1/admin/users',
          query: {
            'q': ?(query.trim().isEmpty ? null : query.trim()),
            'role': ?role?.wire,
            'status': ?status?.wire,
            'origin': ?origin?.wire,
            'sort': sort.wire,
            'dir': desc ? 'desc' : 'asc',
            'page': '$page',
            'perPage': '$perPage',
          },
        )
        as Map<String, dynamic>,
  );

  Future<int> adminInvite({
    required List<String> emails,
    required AdminRole role,
    String? message,
  }) async {
    final result = await _api.post(
      '/api/v1/admin/users/invite',
      body: {
        'emails': emails,
        'admin': role == AdminRole.admin,
        if (message != null && message.trim().isNotEmpty)
          'message': message.trim(),
      },
    );
    return (result is Map && result['sent'] is num)
        ? (result['sent'] as num).toInt()
        : emails.length;
  }

  Future<void> adminResendInvites(List<String> ids) =>
      _api.post('/api/v1/admin/users/resend', body: {'ids': ids});

  Future<void> adminSetStatus(List<String> ids, UserStatus status) => _api.post(
    '/api/v1/admin/users/status',
    body: {'ids': ids, 'status': status.wire},
  );

  /// Approves verified self-registrations awaiting admin sign-off.
  Future<void> adminApproveUsers(List<String> ids) =>
      _api.post('/api/v1/admin/users/approve', body: {'ids': ids});

  /// Fetches a single user for the admin board (e.g. an approval deep-link that
  /// opens straight to the user's detail drawer).
  Future<AdminUser> adminUser(String id) async => AdminUser.fromJson(
    await _api.get('/api/v1/admin/users/$id') as Map<String, dynamic>,
  );

  Future<void> adminSetRole(List<String> ids, AdminRole role) => _api.post(
    '/api/v1/admin/users/role',
    body: {'ids': ids, 'role': role.wire},
  );

  Future<void> adminSendPasswordReset(List<String> ids) =>
      _api.post('/api/v1/admin/users/password-reset', body: {'ids': ids});

  Future<void> adminRevokeSessions(List<String> ids) =>
      _api.post('/api/v1/admin/users/revoke-sessions', body: {'ids': ids});

  Future<void> adminUpdateUserDetails(
    String id, {
    String? displayName,
    String? title,
    String? email,
  }) => _api.patch(
    '/api/v1/admin/users/$id',
    body: {'displayName': ?displayName, 'title': ?title, 'email': ?email},
  );

  Future<void> adminDeleteUsers(List<String> ids) =>
      _api.post('/api/v1/admin/users/delete', body: {'ids': ids});

  // --- Audit log ---------------------------------------------------------------

  /// One filtered, paginated page of the security audit log. Blank/null filters
  /// widen the query; results are newest-first.
  Future<AuditPage> auditLog({
    String query = '',
    AuditCategory? category,
    AuditSeverity? severity,
    String? action,
    String? outcome,
    String? actorId,
    int page = 1,
    int perPage = 30,
  }) async => AuditPage.fromJson(
    await _api.get(
          '/api/v1/admin/audit',
          query: {
            'query': ?(query.trim().isEmpty ? null : query.trim()),
            'category': ?(category == null || category == AuditCategory.unknown
                ? null
                : category.wire),
            'severity': ?(severity == null || severity == AuditSeverity.unknown
                ? null
                : severity.wire),
            'action': ?action,
            'outcome': ?outcome,
            'actorId': ?actorId,
            'page': '$page',
            'perPage': '$perPage',
          },
        )
        as Map<String, dynamic>,
  );

  /// The catalogue of audit event types — used to render the per-event toggles.
  Future<List<AuditEventType>> auditEventTypes() async =>
      ((await _api.get('/api/v1/admin/audit/event-types')) as List<dynamic>)
          .map((e) => AuditEventType.fromJson(e as Map<String, dynamic>))
          .toList();
}
