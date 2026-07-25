import 'package:equatable/equatable.dart';

import 'work_models.dart';

/// Why a move needs the user's attention — mirrors the backend
/// `IssueMoveService.WarningCode`. Unknown values decode to [unknown] so a
/// newer server can add a code without breaking an older client.
enum MoveWarningCode {
  /// The issue leaves its sprint: the sprint's board doesn't span the target.
  sprintDetached,

  /// The parent stays behind, so the issue arrives without its epic/parent link.
  parentDetached,

  /// An epic is moving but its child issues were not included.
  epicChildrenStay,

  /// An assignee is not a member of the target project.
  assigneeNotMember,
  unknown;

  static MoveWarningCode parse(String? raw) => switch (raw) {
    'SPRINT_DETACHED' => MoveWarningCode.sprintDetached,
    'PARENT_DETACHED' => MoveWarningCode.parentDetached,
    'EPIC_CHILDREN_STAY' => MoveWarningCode.epicChildrenStay,
    'ASSIGNEE_NOT_MEMBER' => MoveWarningCode.assigneeNotMember,
    _ => MoveWarningCode.unknown,
  };
}

/// One row of the status mapping: where issues currently in [fromState] land in
/// the target project's workflow. [existsInTarget] separates a free carry-over
/// (the same status exists over there) from a decision the user must make.
class MoveStateMapping extends Equatable {
  const MoveStateMapping({
    required this.fromState,
    required this.suggestedTo,
    required this.existsInTarget,
    required this.issueCount,
  });

  final String fromState;
  final String? suggestedTo;
  final bool existsInTarget;
  final int issueCount;

  factory MoveStateMapping.fromJson(Map<String, dynamic> json) =>
      MoveStateMapping(
        fromState: json['fromState'] as String? ?? '',
        suggestedTo: json['suggestedTo'] as String?,
        existsInTarget: json['existsInTarget'] as bool? ?? false,
        issueCount: (json['issueCount'] as num?)?.toInt() ?? 0,
      );

  @override
  List<Object?> get props => [
    fromState,
    suggestedTo,
    existsInTarget,
    issueCount,
  ];
}

/// One issue in the move, with a preview of the readable id it will carry
/// afterwards. [pulledIn] marks issues the user did not select but that travel
/// along (sub-tasks, and an epic's children when opted in).
class MovePreview extends Equatable {
  const MovePreview({
    required this.issueId,
    required this.readableId,
    required this.nextReadableId,
    required this.title,
    required this.state,
    this.type,
    this.pulledIn = false,
  });

  final String issueId;
  final String readableId;
  final String nextReadableId;
  final String title;
  final String state;
  final String? type;
  final bool pulledIn;

  factory MovePreview.fromJson(Map<String, dynamic> json) => MovePreview(
    issueId: json['issueId'] as String? ?? '',
    readableId: json['readableId'] as String? ?? '',
    nextReadableId: json['nextReadableId'] as String? ?? '',
    title: json['title'] as String? ?? '',
    state: json['state'] as String? ?? '',
    type: json['type'] as String?,
    pulledIn: json['pulledIn'] as bool? ?? false,
  );

  @override
  List<Object?> get props => [issueId, readableId, nextReadableId, pulledIn];
}

class MoveWarning extends Equatable {
  const MoveWarning({required this.code, this.readableId, this.detail});

  final MoveWarningCode code;
  final String? readableId;

  /// Code-dependent extra: the parent's id, the sprint name, the assignee id,
  /// or the number of children staying behind.
  final String? detail;

  factory MoveWarning.fromJson(Map<String, dynamic> json) => MoveWarning(
    code: MoveWarningCode.parse(json['code'] as String?),
    readableId: json['readableId'] as String?,
    detail: json['detail'] as String?,
  );

  @override
  List<Object?> get props => [code, readableId, detail];
}

/// What a move to another project would do — everything the wizard needs to
/// show before anything is written.
class MovePreflight extends Equatable {
  const MovePreflight({
    required this.targetProject,
    required this.targetStates,
    required this.stateMappings,
    required this.issues,
    required this.warnings,
  });

  final Project targetProject;

  /// The target project's workflow, in order — the options for every mapping.
  final List<String> targetStates;
  final List<MoveStateMapping> stateMappings;
  final List<MovePreview> issues;
  final List<MoveWarning> warnings;

  /// Issues pulled in implicitly (sub-tasks, opted-in epic children).
  List<MovePreview> get pulledIn =>
      issues.where((i) => i.pulledIn).toList(growable: false);

  /// Whether any status has no equivalent in the target and thus needs a real
  /// decision from the user.
  bool get needsDecision => stateMappings.any((m) => !m.existsInTarget);

  factory MovePreflight.fromJson(Map<String, dynamic> json) => MovePreflight(
    targetProject: Project.fromJson(
      json['targetProject'] as Map<String, dynamic>,
    ),
    targetStates: ((json['targetStates'] as List<dynamic>?) ?? const [])
        .map((s) => s as String)
        .toList(growable: false),
    stateMappings: ((json['stateMappings'] as List<dynamic>?) ?? const [])
        .map((m) => MoveStateMapping.fromJson(m as Map<String, dynamic>))
        .toList(growable: false),
    issues: ((json['issues'] as List<dynamic>?) ?? const [])
        .map((i) => MovePreview.fromJson(i as Map<String, dynamic>))
        .toList(growable: false),
    warnings: ((json['warnings'] as List<dynamic>?) ?? const [])
        .map((w) => MoveWarning.fromJson(w as Map<String, dynamic>))
        .toList(growable: false),
  );

  @override
  List<Object?> get props => [
    targetProject,
    targetStates,
    stateMappings,
    issues,
    warnings,
  ];
}
