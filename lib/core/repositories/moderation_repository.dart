import '../api/api_client.dart';
import '../models/moderation_models.dart';

/// The user-facing half of moderation: reporting content or a person, and the
/// personal block list.
///
/// Kept apart from [AdminRepository] on purpose. Everything here is available to
/// every signed-in member — Apple Guideline 1.2 and Google's UGC policy both
/// require reporting and blocking to be *user* capabilities, not something
/// reachable only from an admin area — whereas the moderation queue these
/// reports feed is admin-only and lives on the admin repository.
class ModerationRepository {
  ModerationRepository(this._api);

  final ApiClient _api;

  /// Files a report about a piece of content or a person.
  ///
  /// Fire-and-forget from the caller's point of view: the response body carries
  /// the queued report, but nothing in the app renders it. A reporter is told
  /// their report was received and nothing else — showing them its status would
  /// leak whether the reported person was actioned, which is the moderator's
  /// business and not the reporter's.
  ///
  /// `/reports/content` rather than `/reports`, which the analytics
  /// `ReportController` already owns on the server — same English word, an
  /// entirely different resource.
  Future<void> report(
    ReportTarget target, {
    required ReportReason reason,
    String? note,
  }) => _api.post(
    '/api/v1/reports/content',
    body: {
      ...target.toJson(),
      'reason': reason.wire,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    },
  );

  /// Blocks [userId] for the signed-in user only (a personal mute).
  ///
  /// The blocked id travels in the path, not in a body: a block is part of the
  /// signed-in user's own account (`/me/blocks/{userId}`), and the server treats
  /// a repeat call as a no-op — a boundary is not a transaction, so a client
  /// retrying after a dropped response must not be told anything different the
  /// second time. The response echoes the blocked account; nothing here needs it,
  /// because the block list reloads from the server after a mutation.
  Future<void> blockUser(String userId) =>
      _api.post('/api/v1/me/blocks/$userId');

  /// Lifts a block. Idempotent for the same reason [blockUser] is.
  Future<void> unblockUser(String userId) =>
      _api.delete('/api/v1/me/blocks/$userId');

  /// Everyone the signed-in user has blocked, newest first.
  ///
  /// One call and a flat list, because that is what the endpoint is: `/me/blocks`
  /// answers with every block the user holds, and there is no page behind it to
  /// ask for. Paging a list the server already sent in full would be theatre —
  /// and the list is bounded by how many colleagues one person has decided to
  /// mute, which is a handful, not a directory.
  Future<List<BlockedUser>> blockedUsers() async {
    final data = await _api.get('/api/v1/me/blocks') as List<dynamic>?;
    return (data ?? const [])
        .map((u) => BlockedUser.fromJson(u as Map<String, dynamic>))
        .toList();
  }
}
