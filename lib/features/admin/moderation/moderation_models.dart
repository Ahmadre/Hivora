import 'package:flutter/foundation.dart';

import '../../../core/util/dates.dart';

/// Domain models for the admin **Moderation** panel: the flagged-content queue
/// (`ModerationRecord`) and the user-report queue (`ContentReport`) behind
/// `/api/v1/admin/moderation`, plus the server enums they are described with.
///
/// They live inside the admin feature rather than `core/models` because nothing
/// outside the moderation panel consumes them — a queue row is a moderator's
/// work item, not something a normal screen ever renders.
///
/// A record never carries the content itself, only a reference to it (see the
/// server's `ModerationRecorder`): the moderator opens the item to judge it.
/// That is why every row here is a handful of identifiers plus a verdict.

/// The server serialises these enums by their Java constant name, which is the
/// SCREAMING_SNAKE form of the Dart name. Deriving it beats a hand-written
/// lookup table, which would silently start answering `unknown` the day a
/// surface is added on the server and nobody remembers this file exists.
String _wireOf(String name) =>
    name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]}').toUpperCase();

/// Resolves a wire constant back to its enum value, falling back to [fallback]
/// for anything this build does not know — a newer server must never blank a
/// queue row it could still render most of.
T _fromWire<T extends Enum>(List<T> values, T fallback, String? value) {
  if (value == null || value.isEmpty) return fallback;
  for (final candidate in values) {
    if (candidate != fallback && _wireOf(candidate.name) == value) {
      return candidate;
    }
  }
  return fallback;
}

/// Where a piece of content entered the system (server `ModerationSurface`).
enum ModerationSurfaceKind {
  issueTitle,
  issueDescription,
  comment,
  articleTitle,
  articleContent,
  worklog,
  entityName,
  entityDescription,
  profile,
  inviteMessage,
  attachment,
  inlineImage,
  avatar,
  organisationLogo,
  voice,
  externalImage,
  emailIngest,
  emailAttachment,
  emailReply,
  gitCommit,
  mcp,
  unknown;

  String get wire => _wireOf(name);

  /// The value to send as a query filter — `null` for [unknown], which is a
  /// local fallback the server has never heard of and would match nothing.
  String? get filterValue =>
      this == ModerationSurfaceKind.unknown ? null : wire;

  String get labelKey => 'moderation.surface.$name';

  static ModerationSurfaceKind fromWire(String? value) =>
      _fromWire(values, ModerationSurfaceKind.unknown, value);
}

/// The policy category content was scored against (server `ModerationCategory`).
enum ModerationCategoryKind {
  sexual,
  sexualMinors,
  violence,
  violentThreat,
  hate,
  harassment,
  selfHarm,
  extremism,
  illegal,
  malware,
  unknown;

  String get wire => _wireOf(name);

  String? get filterValue =>
      this == ModerationCategoryKind.unknown ? null : wire;

  String get labelKey => 'moderation.category.$name';

  /// Whether an admin setting may weaken or switch this category off. Mirrors
  /// the server's `ModerationPolicy.isOverridable`: child sexual content and
  /// malware are fixed, so no tenant setting can turn its own instance into a
  /// safe place to put either. The panel surfaces this read-only rather than
  /// hiding it, because an admin who cannot find the switch assumes it is
  /// missing, not that it is deliberate.
  bool get overridable =>
      this != ModerationCategoryKind.sexualMinors &&
      this != ModerationCategoryKind.malware;

  /// The real categories in the order a refusal names them — most severe
  /// first, the order the server's enum declares — without the local [unknown]
  /// fallback, which is never something a filter or a policy list should offer.
  static const List<ModerationCategoryKind> all = [
    sexual,
    sexualMinors,
    violence,
    violentThreat,
    hate,
    harassment,
    selfHarm,
    extremism,
    illegal,
    malware,
  ];

  static ModerationCategoryKind fromWire(String? value) =>
      _fromWire(values, ModerationCategoryKind.unknown, value);
}

/// What the pipeline concluded (server `ModerationDecision`).
enum ModerationDecisionKind {
  allow,
  flag,
  block,
  unknown;

  String get labelKey => 'moderation.decision.$name';

  static ModerationDecisionKind fromWire(String? value) =>
      _fromWire(values, ModerationDecisionKind.unknown, value);
}

/// Which stage produced the verdict (server `ModerationVerdict.ModerationTier`).
enum ModerationTier {
  disabled,
  gate,
  localModel,
  external,
  human,
  unknown;

  String get labelKey => 'moderation.tier.$name';

  static ModerationTier fromWire(String? value) =>
      _fromWire(values, ModerationTier.unknown, value);
}

/// Where a flagged record stands with the moderators.
enum ModerationReviewState {
  /// Waiting for a human — the default queue.
  open,

  /// A moderator agreed with the machine.
  confirmed,

  /// A false positive.
  dismissed;

  String get wire => name.toUpperCase();

  String get labelKey => 'moderation.state.$name';

  static ModerationReviewState fromWire(String? value) =>
      _fromWire(values, ModerationReviewState.open, value);
}

/// Where a user report stands.
enum ContentReportState {
  open,

  /// The report was upheld and the content or its author was acted on.
  actioned,

  dismissed;

  String get wire => name.toUpperCase();

  String get labelKey => 'moderation.state.$name';

  static ContentReportState fromWire(String? value) =>
      _fromWire(values, ContentReportState.open, value);
}

/// Turns a target reference into the in-app route that opens it.
///
/// The server may send a ready-made [link] — the convention notifications
/// already use, and the only way a comment is reachable at all, since it needs
/// its issue and a record does not carry one. Everything else is derived, and a
/// target we cannot address yields `null` so the row hides its Open action
/// instead of navigating somewhere blank.
String? _routeFor(String? link, String? targetType, String? targetId) {
  if (link != null && link.startsWith('/')) return link;
  if (targetId == null || targetId.isEmpty) return null;
  return switch (targetType) {
    'issue' => '/issues/$targetId',
    'article' => '/knowledge/$targetId',
    _ => null,
  };
}

/// One verdict the pipeline recorded — a flag, or an allow that was produced
/// while a tier was down.
@immutable
class ModerationRecord {
  const ModerationRecord({
    required this.id,
    required this.createdAt,
    required this.surface,
    required this.category,
    required this.decision,
    required this.tier,
    required this.score,
    required this.degraded,
    required this.reviewState,
    this.targetType,
    this.targetId,
    this.label,
    this.link,
    this.projectId,
    this.projectName,
    this.authorId,
    this.authorName,
    this.evidence,
    this.note,
  });

  final String id;
  final DateTime createdAt;
  final ModerationSurfaceKind surface;
  final ModerationCategoryKind category;
  final ModerationDecisionKind decision;
  final ModerationTier tier;

  /// Confidence 0–100 behind [category].
  final int score;

  /// Whether a tier was unavailable when this was judged. A degraded verdict is
  /// still a real verdict — it is in the queue precisely so the bypass is a row
  /// someone can count rather than a log line nobody reads.
  final bool degraded;

  final ModerationReviewState reviewState;

  /// Entity kind (`issue`, `comment`, `article`, `attachment`, `user`).
  final String? targetType;
  final String? targetId;

  /// Short human handle for the row — an issue key, a file name. Never the
  /// content itself.
  final String? label;

  final String? link;
  final String? projectId;
  final String? projectName;
  final String? authorId;
  final String? authorName;

  /// The matched term or classifier detail, kept for the reviewing admin only.
  final String? evidence;

  /// A previous reviewer's note.
  final String? note;

  String? get route => _routeFor(link, targetType, targetId);

  static ModerationRecord fromJson(Map<String, dynamic> json) =>
      ModerationRecord(
        id: json['id'] as String,
        createdAt: parseInstant(json['createdAt']) ?? DateTime.now(),
        surface: ModerationSurfaceKind.fromWire(json['surface'] as String?),
        category: ModerationCategoryKind.fromWire(json['category'] as String?),
        decision: ModerationDecisionKind.fromWire(json['decision'] as String?),
        tier: ModerationTier.fromWire(json['tier'] as String?),
        score: (json['score'] as num?)?.toInt() ?? 0,
        degraded: json['degraded'] as bool? ?? false,
        reviewState: ModerationReviewState.fromWire(
          json['reviewState'] as String?,
        ),
        targetType: json['targetType'] as String?,
        targetId: json['targetId'] as String?,
        label: json['label'] as String?,
        link: json['link'] as String?,
        projectId: json['projectId'] as String?,
        projectName: json['projectName'] as String?,
        authorId: json['authorId'] as String?,
        authorName: json['authorName'] as String?,
        evidence: json['evidence'] as String?,
        note: json['note'] as String?,
      );
}

/// One piece of content a user reported.
@immutable
class ContentReport {
  const ContentReport({
    required this.id,
    required this.createdAt,
    required this.state,
    required this.category,
    required this.surface,
    this.reason,
    this.reporterId,
    this.reporterName,
    this.targetType,
    this.targetId,
    this.label,
    this.link,
    this.projectId,
    this.projectName,
    this.authorId,
    this.authorName,
    this.note,
  });

  final String id;
  final DateTime createdAt;
  final ContentReportState state;

  /// The policy category the reporter picked, in the same vocabulary the
  /// automated pipeline uses — so a queue can be read without translating
  /// between two taxonomies.
  final ModerationCategoryKind category;

  final ModerationSurfaceKind surface;

  /// What the reporter wrote, if the form allowed free text.
  final String? reason;

  final String? reporterId;
  final String? reporterName;
  final String? targetType;
  final String? targetId;
  final String? label;
  final String? link;
  final String? projectId;
  final String? projectName;

  /// Who wrote the reported content (not who reported it).
  final String? authorId;
  final String? authorName;

  /// A previous handler's note.
  final String? note;

  String? get route => _routeFor(link, targetType, targetId);

  static ContentReport fromJson(Map<String, dynamic> json) => ContentReport(
    id: json['id'] as String,
    createdAt: parseInstant(json['createdAt']) ?? DateTime.now(),
    state: ContentReportState.fromWire(json['state'] as String?),
    category: ModerationCategoryKind.fromWire(json['category'] as String?),
    surface: ModerationSurfaceKind.fromWire(json['surface'] as String?),
    reason: json['reason'] as String?,
    reporterId: json['reporterId'] as String?,
    reporterName: json['reporterName'] as String?,
    targetType: json['targetType'] as String?,
    targetId: json['targetId'] as String?,
    label: json['label'] as String?,
    link: json['link'] as String?,
    projectId: json['projectId'] as String?,
    projectName: json['projectName'] as String?,
    authorId: json['authorId'] as String?,
    authorName: json['authorName'] as String?,
    note: json['note'] as String?,
  );
}
