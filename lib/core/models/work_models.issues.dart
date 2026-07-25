part of 'work_models.dart';

/// Minimal issue summary returned by the mention-search endpoint — just enough
/// to render an @-mention menu row (readable id, title) and pick its type glyph,
/// without paging the full issue objects into memory.
class IssueRef extends Equatable {
  const IssueRef({
    required this.id,
    required this.readableId,
    required this.title,
    this.type = 'TASK',
  });

  final String id;
  final String readableId;
  final String title;
  final String type;

  factory IssueRef.fromJson(Map<String, dynamic> json) => IssueRef(
    id: json['id'] as String? ?? '',
    readableId: json['readableId'] as String? ?? '',
    title: json['title'] as String? ?? '',
    type: json['type'] as String? ?? 'TASK',
  );

  @override
  List<Object?> get props => [id, readableId, title, type];
}

class Issue extends Equatable {
  const Issue({
    required this.id,
    required this.projectId,
    required this.readableId,
    required this.title,
    required this.state,
    this.description,
    this.type = 'TASK',
    this.priority = 'NORMAL',
    this.assigneeId,
    this.assigneeIds = const [],
    this.reporterId,
    this.reporterEmail,
    this.inboundSubject,
    this.tags = const [],
    this.parentId,
    this.dependsOnIds = const [],
    this.sprintId,
    this.startDate,
    this.dueDate,
    this.estimateMinutes,
    this.storyPoints,
    this.spentMinutes = 0,
    this.attachments = const [],
    this.rank = 0,
    this.resolvedAt,
    this.archived = false,
    this.createdAt,
    this.updatedAt,
    this.subtaskCount = 0,
    this.subtaskDoneCount = 0,
  });

  final String id;
  final String projectId;
  final String readableId;
  final String title;
  final String state;
  final String? description;
  final String type;
  final String priority;

  /// Primary assignee (first of [assigneeIds]); the single-assignee read sites
  /// (board swimlanes, avatars, filters) keep using this.
  final String? assigneeId;

  /// All assignees. In single-assignee mode this holds 0 or 1 entries.
  final List<String> assigneeIds;
  final String? reporterId;

  /// Set when the issue was created from an inbound e-mail; also marks the issue
  /// as email-sourced (drives the "Reply by email" action).
  final String? reporterEmail;

  /// Original subject line of the inbound e-mail; used to prefill "Re: …".
  final String? inboundSubject;
  final List<String> tags;

  /// Whether this issue was created via email-to-ticket (has a sender to reply to).
  bool get isEmailSourced => reporterEmail != null && reporterEmail!.isNotEmpty;
  final String? parentId;
  final List<String> dependsOnIds;
  final String? sprintId;
  final DateTime? startDate;
  final DateTime? dueDate;
  final int? estimateMinutes;

  /// Scrum effort estimate in story points (Fibonacci); null = unestimated.
  final int? storyPoints;
  final int spentMinutes;
  final List<IssueAttachment> attachments;
  final double rank;
  final DateTime? resolvedAt;

  /// Soft-deleted: hidden from all default listings, restorable by any member.
  final bool archived;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Number of direct children (an epic's child issues, or a standard issue's
  /// sub-tasks). Server-computed and present only on board and issue-list
  /// payloads; 0 everywhere it isn't enriched. Drives the sub-task indicator.
  final int subtaskCount;

  /// Of [subtaskCount], how many are in a resolved state — the "done" half of
  /// the indicator's done/total progress.
  final int subtaskDoneCount;

  /// Whether this issue has at least one direct child (per the enriched count).
  bool get hasSubtasks => subtaskCount > 0;

  bool get resolved => resolvedAt != null;

  /// The id to use when building a shareable URL / route for this issue. Prefers
  /// the human-readable key (`ASTA-42`) so links read cleanly; falls back to the
  /// Mongo id for any legacy issue that predates readable keys. The backend
  /// resolves either form, so both always work.
  String get linkId => readableId.isNotEmpty ? readableId : id;

  /// Top of the hierarchy — groups standard issues, never has a parent.
  bool get isEpic => type.toUpperCase() == 'EPIC';

  /// Leaf of the hierarchy — lives under a standard issue, holds no children.
  bool get isSubtask => type.toUpperCase() == 'SUBTASK';

  /// Story / Task / Bug / Feature — may sit under an epic and hold sub-tasks.
  bool get isStandard => !isEpic && !isSubtask;

  factory Issue.fromJson(Map<String, dynamic> json) => Issue(
    id: json['id'] as String,
    projectId: json['projectId'] as String,
    readableId: json['readableId'] as String? ?? '',
    title: json['title'] as String? ?? '',
    state: json['state'] as String? ?? '',
    description: json['description'] as String?,
    type: json['type'] as String? ?? 'TASK',
    priority: json['priority'] as String? ?? 'NORMAL',
    assigneeId: json['assigneeId'] as String?,
    assigneeIds: _assigneeIds(json),
    reporterId: json['reporterId'] as String?,
    reporterEmail: json['reporterEmail'] as String?,
    inboundSubject: json['inboundSubject'] as String?,
    tags: _stringList(json['tags']),
    parentId: json['parentId'] as String?,
    dependsOnIds: _stringList(json['dependsOnIds']),
    sprintId: json['sprintId'] as String?,
    startDate: _date(json['startDate']),
    dueDate: _date(json['dueDate']),
    estimateMinutes: json['estimateMinutes'] as int?,
    storyPoints: json['storyPoints'] as int?,
    spentMinutes: json['spentMinutes'] as int? ?? 0,
    attachments: ((json['attachments'] as List<dynamic>?) ?? [])
        .map((a) => IssueAttachment.fromJson(a as Map<String, dynamic>))
        .toList(),
    rank: (json['rank'] as num?)?.toDouble() ?? 0,
    resolvedAt: _instant(json['resolvedAt']),
    archived: json['archived'] as bool? ?? false,
    createdAt: _instant(json['createdAt']),
    updatedAt: _instant(json['updatedAt']),
    subtaskCount: json['subtaskCount'] as int? ?? 0,
    subtaskDoneCount: json['subtaskDoneCount'] as int? ?? 0,
  );

  /// Returns a copy with the given fields replaced — used for optimistic
  /// sprint/board mutations before the server response is reconciled.
  Issue copyWith({
    String? state,
    String? assigneeId,
    List<String>? assigneeIds,
    Object? sprintId = _noChange,
    Object? storyPoints = _noChange,
    Object? parentId = _noChange,
    double? rank,
  }) => Issue(
    id: id,
    projectId: projectId,
    readableId: readableId,
    title: title,
    state: state ?? this.state,
    description: description,
    type: type,
    priority: priority,
    assigneeId: assigneeId ?? this.assigneeId,
    assigneeIds: assigneeIds ?? this.assigneeIds,
    reporterId: reporterId,
    reporterEmail: reporterEmail,
    inboundSubject: inboundSubject,
    tags: tags,
    parentId: parentId == _noChange ? this.parentId : parentId as String?,
    dependsOnIds: dependsOnIds,
    sprintId: sprintId == _noChange ? this.sprintId : sprintId as String?,
    startDate: startDate,
    dueDate: dueDate,
    estimateMinutes: estimateMinutes,
    storyPoints: storyPoints == _noChange
        ? this.storyPoints
        : storyPoints as int?,
    spentMinutes: spentMinutes,
    attachments: attachments,
    rank: rank ?? this.rank,
    resolvedAt: resolvedAt,
    archived: archived,
    createdAt: createdAt,
    updatedAt: updatedAt,
    subtaskCount: subtaskCount,
    subtaskDoneCount: subtaskDoneCount,
  );

  @override
  List<Object?> get props => [
    id,
    readableId,
    title,
    state,
    assigneeId,
    assigneeIds,
    priority,
    sprintId,
    storyPoints,
    rank,
    archived,
    updatedAt,
    subtaskCount,
    subtaskDoneCount,
  ];
}

/// Sentinel so [Issue.copyWith] can distinguish "leave unchanged" from
/// "set to null" for nullable fields.
const Object _noChange = Object();

/// The hierarchy around one issue: its breadcrumb [ancestors] (root → immediate
/// parent) and its direct [children] (an epic's standard issues, or a standard
/// issue's sub-tasks). Backs the breadcrumb and the child / sub-task panels.
class IssueHierarchy extends Equatable {
  const IssueHierarchy({this.ancestors = const [], this.children = const []});

  final List<Issue> ancestors;
  final List<Issue> children;

  factory IssueHierarchy.fromJson(Map<String, dynamic> json) => IssueHierarchy(
    ancestors: ((json['ancestors'] as List<dynamic>?) ?? [])
        .map((i) => Issue.fromJson(i as Map<String, dynamic>))
        .toList(),
    children: ((json['children'] as List<dynamic>?) ?? [])
        .map((i) => Issue.fromJson(i as Map<String, dynamic>))
        .toList(),
  );

  static const empty = IssueHierarchy();

  @override
  List<Object?> get props => [ancestors, children];
}

/// One Jira-style link between issues, oriented for the issue it was fetched
/// for: [verb] is the perspective-correct relationship ("blocks" vs "is blocked
/// by"), [outward] tells which way it points, and [issue] is the other end.
class IssueLink extends Equatable {
  const IssueLink({
    required this.id,
    required this.type,
    required this.outward,
    required this.verb,
    required this.issue,
  });

  /// Server enum name: `BLOCKS`, `CLONES`, `RELATES`, …
  final String type;
  final String id;
  final bool outward;

  /// The relationship verb to display, e.g. `blocks`, `is blocked by`.
  final String verb;

  /// The issue on the other end of the link.
  final Issue issue;

  factory IssueLink.fromJson(Map<String, dynamic> json) => IssueLink(
    id: json['id'] as String,
    type: json['type'] as String? ?? 'RELATES',
    outward: json['outward'] as bool? ?? true,
    verb: json['verb'] as String? ?? 'relates to',
    issue: Issue.fromJson(json['issue'] as Map<String, dynamic>),
  );

  @override
  List<Object?> get props => [id, type, outward, verb, issue];
}

/// A directional option in the "add link" dropdown — a (type, direction) pair
/// with the verb shown for it. The order mirrors Jira's link-type list and the
/// product spec; `outward` = this issue is the subject of the verb.
class IssueLinkOption {
  const IssueLinkOption(this.type, this.outward, this.verb);

  final String type;
  final bool outward;
  final String verb;
}

/// Every directional link verb offered when creating a link. "is blocked by"
/// leads (the default), matching the reference UI.
const List<IssueLinkOption> kIssueLinkOptions = [
  IssueLinkOption('BLOCKS', false, 'is blocked by'),
  IssueLinkOption('BLOCKS', true, 'blocks'),
  IssueLinkOption('CLONES', false, 'is cloned by'),
  IssueLinkOption('CLONES', true, 'clones'),
  IssueLinkOption('CREATES', false, 'created by'),
  IssueLinkOption('CREATES', true, 'created'),
  IssueLinkOption('DUPLICATES', false, 'is duplicated by'),
  IssueLinkOption('DUPLICATES', true, 'duplicates'),
  IssueLinkOption('RELATES', true, 'relates to'),
  IssueLinkOption('TESTS', false, 'is tested by'),
  IssueLinkOption('TESTS', true, 'tests'),
  IssueLinkOption('SPLITS', false, 'split from'),
  IssueLinkOption('SPLITS', true, 'split to'),
];

class IssueAttachment extends Equatable {
  const IssueAttachment({
    required this.id,
    required this.fileName,
    required this.size,
    this.contentType,
    this.uploaderId,
    this.uploadedAt,
  });

  final String id;
  final String fileName;
  final int size;
  final String? contentType;
  final String? uploaderId;
  final DateTime? uploadedAt;

  factory IssueAttachment.fromJson(Map<String, dynamic> json) =>
      IssueAttachment(
        id: json['id'] as String,
        fileName: json['fileName'] as String? ?? 'file',
        size: json['size'] as int? ?? 0,
        contentType: json['contentType'] as String?,
        uploaderId: json['uploaderId'] as String?,
        uploadedAt: _instant(json['uploadedAt']),
      );

  @override
  List<Object?> get props => [id, fileName, size];
}

/// A comment is either plain Markdown ([text]) or a recorded [voice] message.
enum CommentType { text, voice }

/// Voice-message payload attached to a [CommentType.voice] comment. The audio
/// bytes are streamed from the API (`.../comments/{id}/voice`); [peaks] and
/// [durationMs] carry the pre-computed waveform so the bubble renders without
/// decoding the audio.
class CommentVoice extends Equatable {
  const CommentVoice({
    required this.durationMs,
    required this.peaks,
    this.size = 0,
    this.contentType,
  });

  final int durationMs;
  final List<int> peaks;
  final int size;
  final String? contentType;

  Duration get duration => Duration(milliseconds: durationMs);

  factory CommentVoice.fromJson(Map<String, dynamic> json) => CommentVoice(
    durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    peaks: ((json['peaks'] as List?) ?? const [])
        .map((e) => (e as num).toInt())
        .toList(growable: false),
    size: (json['size'] as num?)?.toInt() ?? 0,
    contentType: json['contentType'] as String?,
  );

  @override
  List<Object?> get props => [durationMs, peaks, size, contentType];
}

/// A single emoji reaction on a comment. WhatsApp semantics: a user holds at
/// most one reaction per comment, so [userId] is unique within a comment's list.
class CommentReaction extends Equatable {
  const CommentReaction({required this.emoji, required this.userId});

  final String emoji;
  final String userId;

  factory CommentReaction.fromJson(Map<String, dynamic> json) =>
      CommentReaction(
        emoji: json['emoji'] as String? ?? '',
        userId: json['userId'] as String? ?? '',
      );

  @override
  List<Object?> get props => [emoji, userId];
}

class IssueComment extends Equatable {
  const IssueComment({
    required this.id,
    required this.authorId,
    required this.text,
    this.type = CommentType.text,
    this.voice,
    this.reactions = const [],
    this.pinned = false,
    this.pinnedAt,
    this.replyToId,
    this.replyToAuthorId,
    this.replyToPreview,
    this.replyCount = 0,
    this.editedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String authorId;
  final String text;
  final CommentType type;
  final CommentVoice? voice;

  /// Emoji reactions; at most one per user (WhatsApp-style).
  final List<CommentReaction> reactions;

  /// Whether the comment is pinned to the top of the thread.
  final bool pinned;
  final DateTime? pinnedAt;

  /// Reply quote (WhatsApp): the comment this replies to + a denormalised
  /// snapshot so the quote renders without resolving the parent.
  final String? replyToId;
  final String? replyToAuthorId;
  final String? replyToPreview;

  /// Number of replies to this (top-level) comment, from the backend — lets the
  /// UI show "N replies" before the reply thread is loaded. 0 on replies.
  final int replyCount;

  /// When the text was last edited (null = never); drives the "edited" marker.
  final DateTime? editedAt;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isVoice => type == CommentType.voice && voice != null;

  bool get isReply => replyToId != null && replyToId!.isNotEmpty;

  /// A top-level comment (owns a flat reply thread); the inverse of [isReply].
  bool get isRoot => !isReply;

  /// Whether this top-level comment has replies to lazily load.
  bool get hasReplies => replyCount > 0;

  /// True once the comment's text has been edited after creation. Based on the
  /// explicit [editedAt] stamp (not [updatedAt], which also bumps on reactions/pins).
  bool get isEdited => editedAt != null;

  /// Reaction counts grouped by emoji, in first-seen order (for stable chips).
  Map<String, int> get reactionCounts {
    final counts = <String, int>{};
    for (final r in reactions) {
      counts[r.emoji] = (counts[r.emoji] ?? 0) + 1;
    }
    return counts;
  }

  /// The emoji the given user reacted with, or null.
  String? myReaction(String? meId) {
    if (meId == null) return null;
    for (final r in reactions) {
      if (r.userId == meId) return r.emoji;
    }
    return null;
  }

  IssueComment copyWith({
    List<CommentReaction>? reactions,
    bool? pinned,
    DateTime? pinnedAt,
    bool clearPinnedAt = false,
    String? text,
    DateTime? editedAt,
    int? replyCount,
  }) => IssueComment(
    id: id,
    authorId: authorId,
    text: text ?? this.text,
    type: type,
    voice: voice,
    reactions: reactions ?? this.reactions,
    pinned: pinned ?? this.pinned,
    pinnedAt: clearPinnedAt ? null : (pinnedAt ?? this.pinnedAt),
    replyToId: replyToId,
    replyToAuthorId: replyToAuthorId,
    replyToPreview: replyToPreview,
    replyCount: replyCount ?? this.replyCount,
    editedAt: editedAt ?? this.editedAt,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  factory IssueComment.fromJson(Map<String, dynamic> json) => IssueComment(
    id: json['id'] as String,
    authorId: json['authorId'] as String? ?? '',
    text: json['text'] as String? ?? '',
    // Legacy documents predate `type`; a missing value is plain text.
    type: (json['type'] as String?)?.toUpperCase() == 'VOICE'
        ? CommentType.voice
        : CommentType.text,
    voice: json['voice'] is Map<String, dynamic>
        ? CommentVoice.fromJson(json['voice'] as Map<String, dynamic>)
        : null,
    reactions: ((json['reactions'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CommentReaction.fromJson)
        .toList(growable: false),
    pinned: json['pinned'] as bool? ?? false,
    pinnedAt: _instant(json['pinnedAt']),
    replyToId: json['replyToId'] as String?,
    replyToAuthorId: json['replyToAuthorId'] as String?,
    replyToPreview: json['replyToPreview'] as String?,
    replyCount: (json['replyCount'] as num?)?.toInt() ?? 0,
    editedAt: _instant(json['editedAt']),
    createdAt: _instant(json['createdAt']),
    updatedAt: _instant(json['updatedAt']),
  );

  @override
  List<Object?> get props => [
    id,
    authorId,
    text,
    type,
    voice,
    reactions,
    pinned,
    pinnedAt,
    replyToId,
    replyCount,
    editedAt,
    updatedAt,
  ];
}

/// One entry in an issue's change history ("Verlauf").
class IssueActivity extends Equatable {
  const IssueActivity({
    required this.id,
    required this.field,
    this.actorId,
    this.fromValue,
    this.toValue,
    this.createdAt,
  });

  /// Backend IssueActivity.Field: CREATED, TITLE, DESCRIPTION, STATE,
  /// ASSIGNEE, PRIORITY, TYPE, SPRINT, START_DATE, DUE_DATE, ESTIMATE, TAGS.
  final String field;
  final String id;
  final String? actorId;
  final String? fromValue;
  final String? toValue;
  final DateTime? createdAt;

  factory IssueActivity.fromJson(Map<String, dynamic> json) => IssueActivity(
    id: json['id'] as String? ?? '',
    field: json['field'] as String? ?? 'CREATED',
    actorId: json['actorId'] as String?,
    fromValue: json['fromValue'] as String?,
    toValue: json['toValue'] as String?,
    createdAt: _instant(json['createdAt']),
  );

  @override
  List<Object?> get props => [id, field, fromValue, toValue, createdAt];
}
