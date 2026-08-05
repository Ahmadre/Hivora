import 'package:equatable/equatable.dart';

import '../util/dates.dart';

/// Why a person is reporting something.
///
/// A closed vocabulary rather than a free-text box, because a report has to be
/// triageable: the moderator queue sorts and filters on the reason, and "this is
/// child sexual material" must be distinguishable from "this is spam" without a
/// human reading every note first. The optional note carries the specifics.
///
/// The wire names mirror the server's `ModerationCategory` one-for-one wherever
/// a category exists, so a report and an automated verdict about the same piece
/// of content land in the queue speaking the same language. [spam] and [other]
/// have no category counterpart — nothing is auto-detected for them — and the
/// coarser reporter vocabulary deliberately folds `VIOLENT_THREAT` into
/// [violence] and `EXTREMISM`/`MALWARE` into [illegal]: a reporter is describing
/// what they saw, not classifying it, and a picker with thirteen near-synonyms
/// gets the first row picked every time.
enum ReportReason {
  spam('SPAM', null),
  harassment('HARASSMENT', 'HARASSMENT'),
  hate('HATE', 'HATE'),
  sexual('SEXUAL', 'SEXUAL'),
  sexualMinors('SEXUAL_MINORS', 'SEXUAL_MINORS'),
  violence('VIOLENCE', 'VIOLENCE'),
  selfHarm('SELF_HARM', 'SELF_HARM'),
  illegal('ILLEGAL', 'ILLEGAL'),
  other('OTHER', null);

  const ReportReason(this.wire, this.category);

  /// The value sent to (and returned by) the server.
  final String wire;

  /// The server `ModerationCategory` this reason belongs to, or null when there
  /// is none.
  ///
  /// Never sent — the server derives the category from the reason it was given,
  /// and a client-supplied second copy could only ever disagree with it. It is
  /// declared here so the reporter's vocabulary can be *checked* against the
  /// pipeline's (see the contract test), which is what lets the queue file a
  /// report next to an automated verdict about the same kind of thing. Null for
  /// [spam] and [other]: no classifier scores those, and inventing a category
  /// for them would put rows in the queue under a heading no machine could ever
  /// have produced.
  final String? category;

  /// Parses a wire value, falling back to [other].
  ///
  /// Deliberately total: a server that adds a reason the app does not know yet
  /// must not make an otherwise valid report un-renderable. A report shown as
  /// "Other" is a small loss; a crash on an unknown enum is a broken screen.
  static ReportReason fromWire(String? value) => values.firstWhere(
    (r) => r.wire == value,
    orElse: () => ReportReason.other,
  );

  /// i18n key of the picker label, e.g. `moderation.reason.harassment.label`.
  ///
  /// The trailing `.label` is not decoration: i18next splits on dots, so a
  /// reason cannot be both a string and the parent of its own `.hint`.
  String get labelKey => 'moderation.reason.$name.label';

  /// i18n key of the one-line explanation shown under the label.
  String get hintKey => 'moderation.reason.$name.hint';
}

/// The kind of thing a report points at.
///
/// Sent alongside the id because ids are only unique within their collection —
/// and because the moderator needs to know what they are about to open before
/// they open it. The wire values match the `type` field of the server's
/// `ModerationRecorder.Target`, so a report and an automated flag about the same
/// entity are the same row shape in the queue.
enum ReportTargetType {
  issue('issue'),
  comment('comment'),
  article('article'),
  attachment('attachment'),
  user('user');

  const ReportTargetType(this.wire);

  final String wire;
}

/// What is being reported: a type, an id, and — for content nested inside
/// something else — the id of its container.
///
/// [parentId] exists because an attachment and a comment are not addressable on
/// their own in this product: both live under an issue, and a moderator opening
/// the report needs the issue to reach them. [label] is a short human handle
/// (an issue key, a file name) shown to the reporter so they can see what they
/// are about to report; the handle on the queue row is the one the server
/// derives from the entity it resolved, not this one.
class ReportTarget extends Equatable {
  const ReportTarget({
    required this.type,
    required this.id,
    this.parentId,
    this.label,
  });

  /// A comment, addressed through the issue that owns it.
  factory ReportTarget.comment({
    required String commentId,
    required String issueId,
  }) => ReportTarget(
    type: ReportTargetType.comment,
    id: commentId,
    parentId: issueId,
  );

  /// An attachment, addressed through the issue that owns it.
  factory ReportTarget.attachment({
    required String attachmentId,
    required String issueId,
    String? fileName,
  }) => ReportTarget(
    type: ReportTargetType.attachment,
    id: attachmentId,
    parentId: issueId,
    label: fileName,
  );

  final ReportTargetType type;
  final String id;
  final String? parentId;
  final String? label;

  /// The report request body, in the server's own vocabulary.
  ///
  /// Two things are not a rename away from the field names above. The type goes
  /// over as a Java enum constant (`COMMENT`), while [ReportTargetType.wire] is
  /// the lower-case entity kind the *queue* speaks (`ModerationRecorder.Target`)
  /// — one vocabulary, two casings, so it is upper-cased here at the request
  /// boundary rather than duplicated on the enum. And the container is
  /// `contextId`, which is what the report record calls the issue a comment or
  /// an attachment hangs under.
  ///
  /// [label] is deliberately absent: the server derives the queue row's handle
  /// from the entity it has just resolved and authorized, so a client-supplied
  /// one would be a second, unverified source for the text a moderator reads.
  Map<String, dynamic> toJson() => {
    'targetType': type.wire.toUpperCase(),
    'targetId': id,
    if (parentId != null) 'contextId': parentId,
  };

  @override
  List<Object?> get props => [type, id, parentId];
}

/// Someone the signed-in user has blocked.
///
/// Blocking here is a personal mute, not an org-level ban: it hides the blocked
/// person's comments behind a placeholder and stops their mentions notifying
/// you, and it changes nothing for anyone else. That is deliberate — between
/// colleagues, severing a working relationship is an admin decision, while
/// "I do not want to see this person's messages" is the user's own.
class BlockedUser extends Equatable {
  const BlockedUser({
    required this.userId,
    required this.displayName,
    this.username = '',
    this.avatarUrl,
    this.blockedAt,
  });

  final String userId;
  final String displayName;
  final String username;
  final String? avatarUrl;
  final DateTime? blockedAt;

  factory BlockedUser.fromJson(Map<String, dynamic> json) => BlockedUser(
    userId: json['userId'] as String? ?? json['id'] as String,
    displayName:
        json['displayName'] as String? ?? json['username'] as String? ?? '',
    username: json['username'] as String? ?? '',
    avatarUrl: json['avatarUrl'] as String?,
    blockedAt: parseInstant(json['blockedAt']),
  );

  @override
  List<Object?> get props => [userId];
}
