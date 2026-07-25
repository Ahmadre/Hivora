part of 'work_models.dart';

class GanttTask extends Equatable {
  const GanttTask({
    required this.id,
    required this.readableId,
    required this.title,
    required this.state,
    required this.resolved,
    required this.progressPercent,
    this.type = 'TASK',
    this.assigneeId,
    this.parentId,
    this.startDate,
    this.dueDate,
    this.dependsOnIds = const [],
  });

  final String id;
  final String readableId;
  final String title;
  final String state;
  final String type;
  final String? assigneeId;
  final String? parentId;
  final bool resolved;
  final int progressPercent;
  final DateTime? startDate;
  final DateTime? dueDate;
  final List<String> dependsOnIds;

  /// First day the bar covers. The server only returns dated issues, so at
  /// least one of the two dates is set — a due-only issue starts on its due
  /// date and reads as a milestone.
  DateTime get from => startDate ?? dueDate!;

  /// Last day the bar covers (inclusive).
  DateTime get to => dueDate ?? startDate!;

  /// A zero-length item — a deadline rather than a stretch of work. Drawn as a
  /// diamond, the way every Gantt chart marks a milestone.
  bool get isMilestone => !to.isAfter(from);

  factory GanttTask.fromJson(Map<String, dynamic> json) => GanttTask(
    id: json['id'] as String,
    readableId: json['readableId'] as String? ?? '',
    title: json['title'] as String? ?? '',
    state: json['state'] as String? ?? '',
    type: json['type'] as String? ?? 'TASK',
    assigneeId: json['assigneeId'] as String?,
    parentId: json['parentId'] as String?,
    resolved: json['resolved'] as bool? ?? false,
    progressPercent: json['progressPercent'] as int? ?? 0,
    startDate: _date(json['startDate']),
    dueDate: _date(json['dueDate']),
    dependsOnIds: _stringList(json['dependsOnIds']),
  );

  @override
  List<Object?> get props => [id, readableId, state, progressPercent];
}

/// One connector on the timeline, stated in the link's own direction: [sourceId]
/// is the outward side of the verb (the issue that "blocks"), [targetId] the
/// inward one (the issue that "is blocked by"). Mirrors the server's
/// `IssueLinkGraphService.LinkEdge`; legacy `dependsOnIds` arrive folded in as
/// `BLOCKS` edges.
class GanttLink extends Equatable {
  const GanttLink({
    required this.id,
    required this.type,
    required this.sourceId,
    required this.targetId,
  });

  final String id;

  /// Server enum name: `BLOCKS`, `RELATES`, `DUPLICATES`, …
  final String type;
  final String sourceId;
  final String targetId;

  /// Whether this link constrains the schedule. Only `BLOCKS` does — the rest
  /// are informational and are drawn as faint dashes.
  bool get isDependency => type == 'BLOCKS';

  factory GanttLink.fromJson(Map<String, dynamic> json) => GanttLink(
    id: json['id'] as String? ?? '',
    type: json['type'] as String? ?? 'RELATES',
    sourceId: json['sourceId'] as String? ?? '',
    targetId: json['targetId'] as String? ?? '',
  );

  @override
  List<Object?> get props => [id, type, sourceId, targetId];
}

/// The Gantt read model in one payload: the bars and the connectors between
/// them.
class GanttView extends Equatable {
  const GanttView({this.tasks = const [], this.links = const []});

  final List<GanttTask> tasks;
  final List<GanttLink> links;

  factory GanttView.fromJson(Map<String, dynamic> json) => GanttView(
    tasks: (json['tasks'] as List<dynamic>? ?? const [])
        .map((t) => GanttTask.fromJson(t as Map<String, dynamic>))
        .toList(),
    links: (json['links'] as List<dynamic>? ?? const [])
        .map((l) => GanttLink.fromJson(l as Map<String, dynamic>))
        .toList(),
  );

  @override
  List<Object?> get props => [tasks, links];
}

class TimesheetRow extends Equatable {
  const TimesheetRow({
    required this.userId,
    required this.projectId,
    required this.minutesPerDay,
    required this.totalMinutes,
  });

  final String userId;
  final String projectId;
  final Map<DateTime, int> minutesPerDay;
  final int totalMinutes;

  factory TimesheetRow.fromJson(Map<String, dynamic> json) => TimesheetRow(
    userId: json['userId'] as String? ?? '',
    projectId: json['projectId'] as String? ?? '',
    totalMinutes: json['totalMinutes'] as int? ?? 0,
    minutesPerDay: ((json['minutesPerDay'] as Map<String, dynamic>?) ?? {}).map(
      (k, v) => MapEntry(parseDate(k)!, v as int),
    ),
  );

  @override
  List<Object?> get props => [userId, projectId, totalMinutes];
}

// ─────────────────────────── Sprint insights report ───────────────────────

/// Server-computed insights for one sprint (`GET /api/v1/sprints/{id}/report`).
class SprintReport extends Equatable {
  const SprintReport({
    required this.summary,
    required this.burndown,
    required this.velocity,
    required this.scope,
    required this.breakdown,
  });

  final SprintSummary summary;
  final List<BurndownPoint> burndown;
  final List<VelocityPoint> velocity;
  final List<SprintScopeChange> scope;
  final List<AssigneeLoad> breakdown;

  factory SprintReport.fromJson(Map<String, dynamic> json) => SprintReport(
    summary: SprintSummary.fromJson(
      (json['summary'] as Map<String, dynamic>?) ?? const {},
    ),
    burndown: ((json['burndown'] as List<dynamic>?) ?? const [])
        .map((e) => BurndownPoint.fromJson(e as Map<String, dynamic>))
        .toList(),
    velocity: ((json['velocity'] as List<dynamic>?) ?? const [])
        .map((e) => VelocityPoint.fromJson(e as Map<String, dynamic>))
        .toList(),
    scope: ((json['scope'] as List<dynamic>?) ?? const [])
        .map((e) => SprintScopeChange.fromJson(e as Map<String, dynamic>))
        .toList(),
    breakdown: ((json['breakdown'] as List<dynamic>?) ?? const [])
        .map((e) => AssigneeLoad.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  @override
  List<Object?> get props => [summary, burndown, velocity, scope, breakdown];
}

class SprintSummary extends Equatable {
  const SprintSummary({
    this.committed = 0,
    this.completed = 0,
    this.remaining = 0,
    this.issuesDone = 0,
    this.issuesTotal = 0,
    this.capacityPoints,
    this.avgVelocity = 0,
  });

  final int committed;
  final int completed;
  final int remaining;
  final int issuesDone;
  final int issuesTotal;
  final int? capacityPoints;
  final int avgVelocity;

  factory SprintSummary.fromJson(Map<String, dynamic> json) => SprintSummary(
    committed: json['committed'] as int? ?? 0,
    completed: json['completed'] as int? ?? 0,
    remaining: json['remaining'] as int? ?? 0,
    issuesDone: json['issuesDone'] as int? ?? 0,
    issuesTotal: json['issuesTotal'] as int? ?? 0,
    capacityPoints: json['capacityPoints'] as int?,
    avgVelocity: json['avgVelocity'] as int? ?? 0,
  );

  @override
  List<Object?> get props => [
    committed,
    completed,
    remaining,
    issuesDone,
    issuesTotal,
    capacityPoints,
    avgVelocity,
  ];
}

class BurndownPoint extends Equatable {
  const BurndownPoint({
    required this.day,
    required this.ideal,
    this.date,
    this.remaining,
  });

  final int day;
  final DateTime? date;

  /// Story points still open at end of [day]; null for days not yet elapsed.
  final double? remaining;
  final double ideal;

  factory BurndownPoint.fromJson(Map<String, dynamic> json) => BurndownPoint(
    day: json['day'] as int? ?? 0,
    date: _date(json['date']),
    remaining: (json['remaining'] as num?)?.toDouble(),
    ideal: (json['ideal'] as num?)?.toDouble() ?? 0,
  );

  @override
  List<Object?> get props => [day, remaining, ideal];
}

class VelocityPoint extends Equatable {
  const VelocityPoint({
    required this.sprintId,
    required this.name,
    required this.committed,
    required this.completed,
  });

  final String sprintId;
  final String name;
  final int committed;
  final int completed;

  factory VelocityPoint.fromJson(Map<String, dynamic> json) => VelocityPoint(
    sprintId: json['sprintId'] as String? ?? '',
    name: json['name'] as String? ?? '',
    committed: json['committed'] as int? ?? 0,
    completed: json['completed'] as int? ?? 0,
  );

  @override
  List<Object?> get props => [sprintId, committed, completed];
}

class SprintScopeChange extends Equatable {
  const SprintScopeChange({
    required this.delta,
    required this.label,
    this.date,
  });

  final DateTime? date;
  final int delta;
  final String label;

  factory SprintScopeChange.fromJson(Map<String, dynamic> json) =>
      SprintScopeChange(
        date: _date(json['date']),
        delta: json['delta'] as int? ?? 0,
        label: json['label'] as String? ?? '',
      );

  @override
  List<Object?> get props => [date, delta, label];
}

class AssigneeLoad extends Equatable {
  const AssigneeLoad({
    required this.userId,
    required this.done,
    required this.total,
  });

  final String userId;
  final int done;
  final int total;

  factory AssigneeLoad.fromJson(Map<String, dynamic> json) => AssigneeLoad(
    userId: json['userId'] as String? ?? '',
    done: json['done'] as int? ?? 0,
    total: json['total'] as int? ?? 0,
  );

  @override
  List<Object?> get props => [userId, done, total];
}

List<String> _stringList(dynamic value) =>
    ((value as List<dynamic>?) ?? const []).cast<String>();

/// Reads the assignee list, falling back to the legacy single [assigneeId] so
/// issues from an un-migrated server still surface their assignee.
List<String> _assigneeIds(Map<String, dynamic> json) {
  final list = _stringList(json['assigneeIds']);
  if (list.isNotEmpty) return list;
  final single = json['assigneeId'] as String?;
  return (single != null && single.isNotEmpty) ? [single] : const [];
}

// Calendar dates (dueDate/startDate/…) stay date-only; instants localize.
// See lib/core/util/dates.dart for the rationale.
DateTime? _date(dynamic value) => parseDate(value);

DateTime? _instant(dynamic value) => parseInstant(value);
