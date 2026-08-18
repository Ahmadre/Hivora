import 'package:equatable/equatable.dart';
import '../util/dates.dart';

/// A member's role within a single team. `admin` == "Team-Admin": full control
/// of that team (members, projects, settings) but never platform-wide.
enum TeamRole {
  member,
  admin;

  static TeamRole fromJson(String? value) =>
      value?.toUpperCase() == 'ADMIN' ? TeamRole.admin : TeamRole.member;

  String get wire => this == TeamRole.admin ? 'ADMIN' : 'MEMBER';
}

/// What projects of a team a member may see.
enum AccessScope {
  all,
  some,
  none;

  static AccessScope fromJson(String? value) => switch (value?.toUpperCase()) {
    'ALL' => AccessScope.all,
    'SOME' => AccessScope.some,
    _ => AccessScope.none,
  };

  String get wire => switch (this) {
    AccessScope.all => 'ALL',
    AccessScope.some => 'SOME',
    AccessScope.none => 'NONE',
  };
}

/// A membership's project access (`scope` + the explicit `projectIds` when SOME).
class ProjectAccess extends Equatable {
  const ProjectAccess({
    this.scope = AccessScope.none,
    this.projectIds = const [],
  });

  final AccessScope scope;
  final List<String> projectIds;

  const ProjectAccess.all() : scope = AccessScope.all, projectIds = const [];
  const ProjectAccess.none() : scope = AccessScope.none, projectIds = const [];
  ProjectAccess.some(List<String> ids)
    : scope = AccessScope.some,
      projectIds = List.unmodifiable(ids);

  factory ProjectAccess.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ProjectAccess.none();
    return ProjectAccess(
      scope: AccessScope.fromJson(json['scope'] as String?),
      projectIds: ((json['projectIds'] as List<dynamic>?) ?? const [])
          .cast<String>(),
    );
  }

  Map<String, dynamic> toJson() => {
    'scope': scope.wire,
    if (scope == AccessScope.some) 'projectIds': projectIds,
  };

  @override
  List<Object?> get props => [scope, projectIds];
}

/// The join row embedded in a [Team]: a user's role + project access.
class TeamMembership extends Equatable {
  const TeamMembership({
    required this.userId,
    this.role = TeamRole.member,
    this.access = const ProjectAccess.none(),
  });

  final String userId;
  final TeamRole role;
  final ProjectAccess access;

  bool get isAdmin => role == TeamRole.admin;

  factory TeamMembership.fromJson(Map<String, dynamic> json) => TeamMembership(
    userId: json['userId'] as String,
    role: TeamRole.fromJson(json['role'] as String?),
    access: ProjectAccess.fromJson(json['access'] as Map<String, dynamic>?),
  );

  @override
  List<Object?> get props => [userId, role, access];
}

/// A Team groups users (with per-team roles) and grants them project access.
class Team extends Equatable {
  const Team({
    required this.id,
    required this.key,
    required this.name,
    this.description,
    this.colorHue = 70,
    this.icon = 'hexagon',
    this.createdBy,
    this.createdAt,
    this.projectIds = const [],
    this.members = const [],
    this.avatarUrl,
  });

  final String id;
  final String key;
  final String name;
  final String? description;
  final int colorHue;
  final String icon;
  final String? createdBy;
  final DateTime? createdAt;
  final List<String> projectIds;
  final List<TeamMembership> members;

  /// Server-owned URL of the team picture, or null while the team still shows
  /// its tinted icon glyph. Carries a `?v=` cache buster and the BlurHash as
  /// `bh=`, exactly like a person's avatar — never send it back in a PATCH.
  final String? avatarUrl;

  int get adminCount => members.where((m) => m.isAdmin).length;

  TeamMembership? membershipOf(String? userId) {
    if (userId == null) return null;
    for (final m in members) {
      if (m.userId == userId) return m;
    }
    return null;
  }

  factory Team.fromJson(Map<String, dynamic> json) => Team(
    id: json['id'] as String,
    key: json['key'] as String? ?? '',
    name: json['name'] as String? ?? '',
    description: json['description'] as String?,
    colorHue: (json['colorHue'] as num?)?.toInt() ?? 70,
    icon: json['icon'] as String? ?? 'hexagon',
    createdBy: json['createdBy'] as String?,
    createdAt: _instant(json['createdAt']),
    projectIds: ((json['projectIds'] as List<dynamic>?) ?? const [])
        .cast<String>(),
    members: ((json['members'] as List<dynamic>?) ?? const [])
        .map((m) => TeamMembership.fromJson(m as Map<String, dynamic>))
        .toList(),
    avatarUrl: json['avatarUrl'] as String?,
  );

  @override
  List<Object?> get props => [
    id,
    key,
    name,
    description,
    colorHue,
    icon,
    projectIds,
    members,
    avatarUrl,
  ];
}

/// One entry in a team's activity feed.
class TeamActivity extends Equatable {
  const TeamActivity({
    required this.id,
    required this.verb,
    this.actorId,
    this.objectLabel,
    this.extra,
    this.createdAt,
  });

  /// Server verb: CREATED, UPDATED, ADDED_MEMBER, PROMOTED, DEMOTED,
  /// REMOVED_MEMBER, ATTACHED_PROJECT, CREATED_PROJECT, DETACHED_PROJECT.
  final String verb;
  final String id;
  final String? actorId;
  final String? objectLabel;
  final String? extra;
  final DateTime? createdAt;

  factory TeamActivity.fromJson(Map<String, dynamic> json) => TeamActivity(
    id: json['id'] as String? ?? '',
    verb: json['verb'] as String? ?? 'UPDATED',
    actorId: json['actorId'] as String?,
    objectLabel: json['objectLabel'] as String?,
    extra: json['extra'] as String?,
    createdAt: _instant(json['createdAt']),
  );

  @override
  List<Object?> get props => [id, verb, objectLabel, createdAt];
}

DateTime? _instant(dynamic value) => parseInstant(value);
