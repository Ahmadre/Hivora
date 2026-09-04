import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../models/work_models.dart';

/// Issue comments: threaded feed, replies, reactions, pinning, voice messages,
/// and the live comment event stream.
class CommentRepository {
  CommentRepository(this._api);

  final ApiClient _api;

  /// One page of an issue's TOP-LEVEL comments (replies excluded; each carries a
  /// `replyCount`), plus the backend total. [sort] is `'newest'` (default) or
  /// `'oldest'` — the server orders accordingly.
  Future<({List<IssueComment> items, int total})> comments(
    String issueId, {
    int page = 0,
    int size = 30,
    String sort = 'newest',
  }) async {
    final data =
        await _api.get(
              '/api/v1/issues/$issueId/comments',
              query: {'page': page, 'size': size, 'sort': sort},
            )
            as Map<String, dynamic>;
    return (
      items: ((data['content'] as List<dynamic>?) ?? [])
          .map((c) => IssueComment.fromJson(c as Map<String, dynamic>))
          .toList(),
      total: data['totalElements'] as int? ?? 0,
    );
  }

  /// One page of a root comment's replies, oldest-first, plus the backend total.
  /// Replies are lazily loaded — only fetched when a thread is expanded.
  Future<({List<IssueComment> items, int total})> commentReplies(
    String issueId,
    String rootId, {
    int page = 0,
    int size = 10,
  }) async {
    final data =
        await _api.get(
              '/api/v1/issues/$issueId/comments/$rootId/replies',
              query: {'page': page, 'size': size},
            )
            as Map<String, dynamic>;
    return (
      items: ((data['content'] as List<dynamic>?) ?? [])
          .map((c) => IssueComment.fromJson(c as Map<String, dynamic>))
          .toList(),
      total: data['totalElements'] as int? ?? 0,
    );
  }

  /// Posts a text comment, optionally as a reply to [replyToId].
  ///
  /// [doc] is the Lexical document, and is what the server stores when it is
  /// given: [text] is then only the plain reading of it, which the server
  /// derives for itself anyway. Sending text alone is the legacy path — the
  /// server parses it as markdown — and is what the single-line field still
  /// does, because a one-line remark has no formatting to lose.
  Future<IssueComment> addComment(
    String issueId,
    String text, {
    String? replyToId,
    String? doc,
  }) async => IssueComment.fromJson(
    await _api.post(
          '/api/v1/issues/$issueId/comments',
          body: {'text': text, 'textDoc': ?doc, 'replyToId': ?replyToId},
        )
        as Map<String, dynamic>,
  );

  /// Toggles the caller's emoji reaction on a comment (one per user — a new
  /// emoji replaces theirs, the same emoji removes it). Returns the updated
  /// comment.
  Future<IssueComment> reactToComment(
    String issueId,
    String commentId,
    String emoji,
  ) async => IssueComment.fromJson(
    await _api.put(
          '/api/v1/issues/$issueId/comments/$commentId/reactions',
          body: {'emoji': emoji},
        )
        as Map<String, dynamic>,
  );

  /// Pins/unpins a comment. Any project member may pin and unpin.
  Future<IssueComment> pinComment(
    String issueId,
    String commentId,
    bool pinned,
  ) async => IssueComment.fromJson(
    await _api.put(
          '/api/v1/issues/$issueId/comments/$commentId/pin',
          body: {'pinned': pinned},
        )
        as Map<String, dynamic>,
  );

  /// Pinned comments of a thread, in pin order (surfaced above the feed).
  Future<List<IssueComment>> pinnedComments(String issueId) async =>
      ((await _api.get('/api/v1/issues/$issueId/comments/pinned')
                  as List<dynamic>?) ??
              const [])
          .map((c) => IssueComment.fromJson(c as Map<String, dynamic>))
          .toList();

  /// Edits the text of one of the caller's own comments. Server returns the
  /// updated comment (with a fresh `updatedAt`).
  Future<IssueComment> editComment(
    String issueId,
    String commentId,
    String text,
  ) async => IssueComment.fromJson(
    await _api.patch(
          '/api/v1/issues/$issueId/comments/$commentId',
          body: {'text': text},
        )
        as Map<String, dynamic>,
  );

  /// Deletes one of the caller's own comments (admins may delete any).
  Future<void> deleteComment(String issueId, String commentId) =>
      _api.delete('/api/v1/issues/$issueId/comments/$commentId');

  /// Posts a recorded voice message as a comment. [durationMs] and [peaks]
  /// (normalised 0–100 waveform amplitudes) travel alongside the audio blob so
  /// the feed renders the bubble without decoding the audio. Returns the created
  /// [CommentType.voice] comment.
  Future<IssueComment> addVoiceComment(
    String issueId, {
    required List<int> bytes,
    required String mime,
    required int durationMs,
    required List<int> peaks,
    String? replyToId,
    CancelToken? cancelToken,
  }) async {
    final audio = MultipartFile.fromBytes(
      bytes,
      filename: 'voice${_voiceExt(mime)}',
      contentType: DioMediaType.parse(mime),
    );
    return IssueComment.fromJson(
      await _api.upload(
            '/api/v1/issues/$issueId/comments/voice',
            audio,
            cancelToken: cancelToken,
            fields: {
              'durationMs': durationMs,
              'peaks': peaks.join(','),
              'replyToId': ?replyToId,
            },
          )
          as Map<String, dynamic>,
    );
  }

  /// Raw SSE byte stream of comment-thread changes for an issue (parse with
  /// [parseSse]). Carries a payload-free `changed` ping; the client re-syncs the
  /// thread. Cancel via [cancelToken] when the view is disposed.
  Future<Stream<List<int>>> commentEventStream(
    String issueId, {
    CancelToken? cancelToken,
  }) => _api.openEventStream(
    '/api/v1/issues/$issueId/comments/stream',
    cancelToken: cancelToken,
  );

  static String _voiceExt(String mime) => switch (mime.toLowerCase()) {
    'audio/mpeg' => '.mp3',
    'audio/webm' => '.webm',
    'audio/ogg' => '.ogg',
    'audio/wav' || 'audio/x-wav' => '.wav',
    _ => '.m4a',
  };

  /// Fetches a voice comment's audio bytes through the authenticated proxy, for
  /// local playback (the object store isn't reachable directly). Returns the
  /// bytes + content type, or null when unavailable.
  Future<({List<int> bytes, String contentType})?> voiceCommentAudio(
    String issueId,
    String commentId,
  ) => _api.getBytes('/api/v1/issues/$issueId/comments/$commentId/voice');
}
