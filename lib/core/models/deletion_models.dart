/// Models for the cascading-delete flow (boards, projects, teams).
///
/// The `*Impact` types mirror the server's `DeletionService` impact records and
/// drive the confirmation warnings; the delete itself runs over Server-Sent
/// Events and is decoded with [DeleteEvent].
library;

import 'dart:convert';

import 'work_models.dart' show BoardType;
import '../api/sse.dart';

/// Impact of deleting a board: how many sprints go and how many issues are
/// detached (issues are never deleted with a board).
class BoardDeletionImpact {
  const BoardDeletionImpact({
    required this.boardName,
    required this.type,
    required this.sprints,
    required this.affectedIssues,
  });

  final String boardName;
  final BoardType type;
  final int sprints;
  final int affectedIssues;

  factory BoardDeletionImpact.fromJson(Map<String, dynamic> json) =>
      BoardDeletionImpact(
        boardName: json['boardName'] as String? ?? '',
        type: (json['type'] as String?) == 'SCRUM'
            ? BoardType.scrum
            : BoardType.kanban,
        sprints: (json['sprints'] as num?)?.toInt() ?? 0,
        affectedIssues: (json['affectedIssues'] as num?)?.toInt() ?? 0,
      );
}

/// A project the caller can migrate a deleted project's issues into.
class MigrationTarget {
  const MigrationTarget({
    required this.id,
    required this.key,
    required this.name,
    required this.color,
  });

  final String id;
  final String key;
  final String name;
  final String color;

  factory MigrationTarget.fromJson(Map<String, dynamic> json) =>
      MigrationTarget(
        id: json['id'] as String,
        key: json['key'] as String? ?? '',
        name: json['name'] as String? ?? '',
        color: json['color'] as String? ?? '#AEC6F4',
      );
}

/// Impact of deleting a project: affected boards/sprints/issues/articles/teams,
/// plus the projects issues could be migrated into.
class ProjectDeletionImpact {
  const ProjectDeletionImpact({
    required this.projectName,
    required this.boards,
    required this.sharedBoards,
    required this.sprints,
    required this.issues,
    required this.attachments,
    required this.articles,
    required this.teams,
    required this.migrationTargets,
  });

  final String projectName;

  /// Boards owned solely by this project (deleted with it).
  final int boards;

  /// Boards shared with other projects (merely dereferenced, not deleted).
  final int sharedBoards;
  final int sprints;
  final int issues;
  final int attachments;
  final int articles;
  final int teams;
  final List<MigrationTarget> migrationTargets;

  bool get hasIssues => issues > 0;
  bool get hasBoards => boards > 0 || sharedBoards > 0;

  factory ProjectDeletionImpact.fromJson(Map<String, dynamic> json) =>
      ProjectDeletionImpact(
        projectName: json['projectName'] as String? ?? '',
        boards: (json['boards'] as num?)?.toInt() ?? 0,
        sharedBoards: (json['sharedBoards'] as num?)?.toInt() ?? 0,
        sprints: (json['sprints'] as num?)?.toInt() ?? 0,
        issues: (json['issues'] as num?)?.toInt() ?? 0,
        attachments: (json['attachments'] as num?)?.toInt() ?? 0,
        articles: (json['articles'] as num?)?.toInt() ?? 0,
        teams: (json['teams'] as num?)?.toInt() ?? 0,
        migrationTargets:
            ((json['migrationTargets'] as List<dynamic>?) ?? const [])
                .map((t) => MigrationTarget.fromJson(t as Map<String, dynamic>))
                .toList(),
      );
}

/// Impact of deleting a team: the access (members/projects/boards/issues) that
/// members lose. Nothing is actually deleted besides the team itself.
class TeamDeletionImpact {
  const TeamDeletionImpact({
    required this.teamName,
    required this.members,
    required this.projects,
    required this.boards,
    required this.issues,
  });

  final String teamName;
  final int members;
  final int projects;
  final int boards;
  final int issues;

  factory TeamDeletionImpact.fromJson(Map<String, dynamic> json) =>
      TeamDeletionImpact(
        teamName: json['teamName'] as String? ?? '',
        members: (json['members'] as num?)?.toInt() ?? 0,
        projects: (json['projects'] as num?)?.toInt() ?? 0,
        boards: (json['boards'] as num?)?.toInt() ?? 0,
        issues: (json['issues'] as num?)?.toInt() ?? 0,
      );
}

/// How issues should be handled when their project is deleted.
enum IssueStrategy {
  delete('delete'),
  migrate('migrate');

  const IssueStrategy(this.wire);

  /// Value sent to the server's `issueStrategy` query parameter.
  final String wire;
}

/// One frame of the delete SSE stream: a [progress] step, a terminal [done], or
/// an [error]. Decoded from an [SseEvent].
class DeleteEvent {
  const DeleteEvent._(
    this.kind, {
    this.phase,
    this.current,
    this.total,
    this.message,
  });

  final DeleteEventKind kind;

  /// Stable phase key (e.g. `deletingSprints`) — localized by the UI.
  final String? phase;
  final int? current;
  final int? total;

  /// Localized error message (for [DeleteEventKind.error]).
  final String? message;

  /// Fractional progress in [0, 1] when a total is known, else null.
  double? get fraction => (total != null && total! > 0 && current != null)
      ? current! / total!
      : null;

  static DeleteEvent? tryParse(SseEvent event) {
    final dynamic data = event.data.isEmpty ? null : jsonDecode(event.data);
    final map = data is Map<String, dynamic> ? data : const <String, dynamic>{};
    switch (event.event) {
      case 'progress':
        return DeleteEvent._(
          DeleteEventKind.progress,
          phase: map['phase'] as String?,
          current: (map['current'] as num?)?.toInt(),
          total: (map['total'] as num?)?.toInt(),
        );
      case 'done':
        return const DeleteEvent._(DeleteEventKind.done);
      case 'error':
        return DeleteEvent._(
          DeleteEventKind.error,
          message: map['message'] as String?,
        );
      default:
        return null; // connection comment / unknown frame
    }
  }
}

enum DeleteEventKind { progress, done, error }
