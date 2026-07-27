import 'package:equatable/equatable.dart';

import '../util/dates.dart';
import 'git_connection.dart';

part 'work_models.issues.dart';
part 'work_models.boards.dart';
part 'work_models.reports.dart';

/// A reusable, colored issue label ("Stichwort"). [name] is the canonical key
/// issues reference via their `tags`; [id] is a stable handle used as a UI list
/// key and to detect renames server-side. [hue] is an oklch hue (see
/// `core/theme/hue_colors.dart`).
class ProjectLabel extends Equatable {
  const ProjectLabel({required this.id, required this.name, required this.hue});

  final String id;
  final String name;
  final int hue;

  factory ProjectLabel.fromAny(dynamic value, int index) {
    if (value is String) {
      return ProjectLabel(
        id: value,
        name: value,
        hue: _labelHueFallback(index),
      );
    }
    final json = value as Map<String, dynamic>;
    return ProjectLabel(
      id: json['id'] as String? ?? json['name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      hue: (json['hue'] as num?)?.toInt() ?? 250,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'hue': hue};

  ProjectLabel copyWith({String? name, int? hue}) =>
      ProjectLabel(id: id, name: name ?? this.name, hue: hue ?? this.hue);

  @override
  List<Object?> get props => [id, name, hue];
}

/// One ordered workflow state. [name] is the canonical key (matches
/// `Issue.state`); [id] is a stable handle for reorder/rename. [hue] is an
/// oklch hue used to tint the state everywhere it renders.
class WorkflowState extends Equatable {
  const WorkflowState({
    required this.id,
    required this.name,
    required this.hue,
  });

  final String id;
  final String name;
  final int hue;

  factory WorkflowState.fromAny(dynamic value, int index) {
    if (value is String) {
      return WorkflowState(id: value, name: value, hue: 250);
    }
    final json = value as Map<String, dynamic>;
    return WorkflowState(
      id: json['id'] as String? ?? json['name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      hue: (json['hue'] as num?)?.toInt() ?? 250,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'hue': hue};

  WorkflowState copyWith({String? name, int? hue}) =>
      WorkflowState(id: id, name: name ?? this.name, hue: hue ?? this.hue);

  @override
  List<Object?> get props => [id, name, hue];
}

/// Label hue cycle mirrored from the backend palette, used only as a fallback
/// when an older server returns bare label strings.
const List<int> _kFallbackLabelHues = [70, 250, 300, 200, 155, 20, 330, 45];
int _labelHueFallback(int index) =>
    _kFallbackLabelHues[index % _kFallbackLabelHues.length];

class Project extends Equatable {
  const Project({
    required this.id,
    required this.key,
    required this.name,
    this.description,
    this.leadIds = const [],
    this.memberIds = const [],
    this.workflowStates = const [],
    this.resolvedStates = const [],
    this.labels = const [],
    this.color = '#AEC6F4',
    this.archived = false,
    this.git,
    this.extraRepos = const [],
  });

  final String id;
  final String key;
  final String name;
  final String? description;

  /// Project leads (>= 1); the first is the primary lead.
  final List<String> leadIds;
  final List<String> memberIds;
  final List<WorkflowState> workflowStates;

  /// Resolved states by *name* (subset of [workflowStates] names).
  final List<String> resolvedStates;

  /// Reusable, colored issue labels ("Stichworte") for this project.
  final List<ProjectLabel> labels;
  final String color;
  final bool archived;

  /// Per-project **primary** Git repository connection, or `null` when no repo
  /// is linked. Holds the project-wide automation + branch template.
  final GitConnection? git;

  /// Additional connected repositories beyond [git] (multi-repo).
  final List<GitConnection> extraRepos;

  /// Every connected repository, primary first (empty when none linked).
  List<GitConnection> get allRepos => [?git, ...extraRepos];

  /// Whether this project has at least one repository connected.
  bool get gitConnected => git != null;

  /// Primary lead (legacy single-lead accessor).
  String? get leadId => leadIds.isEmpty ? null : leadIds.first;

  /// Ordered workflow state names — what issues/boards key off of.
  List<String> get stateNames =>
      workflowStates.map((s) => s.name).toList(growable: false);

  /// Reusable label names.
  List<String> get labelNames =>
      labels.map((l) => l.name).toList(growable: false);

  /// Configured hue for a label name, or null when unknown.
  int? hueForLabel(String name) {
    for (final l in labels) {
      if (l.name == name) return l.hue;
    }
    return null;
  }

  /// Configured hue for a workflow-state name, or null when unknown.
  int? hueForState(String name) {
    for (final s in workflowStates) {
      if (s.name == name) return s.hue;
    }
    return null;
  }

  factory Project.fromJson(Map<String, dynamic> json) => Project(
    id: json['id'] as String,
    key: json['key'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    leadIds: _leadIds(json),
    memberIds: _stringList(json['memberIds']),
    workflowStates: _indexedList(json['workflowStates'], WorkflowState.fromAny),
    resolvedStates: _stringList(json['resolvedStates']),
    labels: _indexedList(json['labels'], ProjectLabel.fromAny),
    color: json['color'] as String? ?? '#AEC6F4',
    archived: json['archived'] as bool? ?? false,
    git: GitConnection.fromJson(json['git'] as Map<String, dynamic>?),
    extraRepos: _gitList(json['extraRepos']),
  );

  static List<GitConnection> _gitList(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(GitConnection.fromJson)
        .whereType<GitConnection>()
        .toList(growable: false);
  }

  Project copyWith({
    String? key,
    String? name,
    String? description,
    List<String>? leadIds,
    List<String>? memberIds,
    List<WorkflowState>? workflowStates,
    List<String>? resolvedStates,
    List<ProjectLabel>? labels,
    String? color,
    bool? archived,
    GitConnection? git,
    List<GitConnection>? extraRepos,
  }) => Project(
    id: id,
    key: key ?? this.key,
    name: name ?? this.name,
    description: description ?? this.description,
    leadIds: leadIds ?? this.leadIds,
    memberIds: memberIds ?? this.memberIds,
    workflowStates: workflowStates ?? this.workflowStates,
    resolvedStates: resolvedStates ?? this.resolvedStates,
    labels: labels ?? this.labels,
    color: color ?? this.color,
    archived: archived ?? this.archived,
    git: git ?? this.git,
    extraRepos: extraRepos ?? this.extraRepos,
  );

  /// Returns a copy with the Git repositories replaced — the primary [git]
  /// (including clearing it to `null` on disconnect) plus the full
  /// [extraRepos] list. Git mutations persist server-side immediately,
  /// independently of the settings draft/save flow, so this merges just the
  /// repo fields without disturbing any in-progress draft edits. When
  /// [extraRepos] is omitted the current additional repos are kept.
  Project withGit(GitConnection? git, {List<GitConnection>? extraRepos}) =>
      Project(
        id: id,
        key: key,
        name: name,
        description: description,
        leadIds: leadIds,
        memberIds: memberIds,
        workflowStates: workflowStates,
        resolvedStates: resolvedStates,
        labels: labels,
        color: color,
        archived: archived,
        git: git,
        extraRepos: extraRepos ?? this.extraRepos,
      );

  @override
  List<Object?> get props => [
    id,
    key,
    name,
    description,
    leadIds,
    memberIds,
    workflowStates,
    resolvedStates,
    labels,
    color,
    archived,
    git,
    extraRepos,
  ];
}

/// Resolves the primary lead id from either the new [leadIds] array or the
/// legacy single `leadId` field.
List<String> _leadIds(Map<String, dynamic> json) {
  final list = _stringList(json['leadIds']);
  if (list.isNotEmpty) return list;
  final single = json['leadId'] as String?;
  return single != null && single.isNotEmpty ? [single] : const [];
}

List<T> _indexedList<T>(dynamic value, T Function(dynamic, int) build) {
  final list = (value as List<dynamic>?) ?? const [];
  return [for (var i = 0; i < list.length; i++) build(list[i], i)];
}
