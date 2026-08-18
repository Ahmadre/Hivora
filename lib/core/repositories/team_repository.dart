import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../models/deletion_models.dart';
import '../models/team_models.dart';
import '../models/work_models.dart';

/// Teams: CRUD, membership + per-project access, attached projects, the
/// activity feed, and cascading deletion.
class TeamRepository {
  TeamRepository(this._api);

  final ApiClient _api;

  Future<List<Team>> teams() async =>
      ((await _api.get('/api/v1/teams')) as List<dynamic>)
          .map((t) => Team.fromJson(t as Map<String, dynamic>))
          .toList();

  Future<Team> team(String id) async => Team.fromJson(
    await _api.get('/api/v1/teams/$id') as Map<String, dynamic>,
  );

  Future<Team> createTeam({
    required String name,
    required String key,
    String? description,
    required int colorHue,
    required String icon,
  }) async => Team.fromJson(
    await _api.post(
          '/api/v1/teams',
          body: {
            'name': name,
            'key': key,
            'description': ?description,
            'colorHue': colorHue,
            'icon': icon,
          },
        )
        as Map<String, dynamic>,
  );

  Future<Team> updateTeam(String id, Map<String, dynamic> patch) async =>
      Team.fromJson(
        await _api.patch('/api/v1/teams/$id', body: patch)
            as Map<String, dynamic>,
      );

  Future<void> deleteTeam(String id) => _api.delete('/api/v1/teams/$id');

  /// Uploads a new team picture and returns its fresh URL.
  ///
  /// The server center-crops and re-encodes, then answers a URL carrying a new
  /// `?v=` token — storing that in state is what makes the picture swap without
  /// a restart, because the changed URL is a different avatar-cache key. The
  /// picture is *not* part of the team PATCH body; it is owned by these
  /// endpoints alone.
  Future<String> uploadTeamAvatar(
    String id,
    MultipartFile file, {
    void Function(double pct)? onProgress,
  }) async =>
      ((await _api.upload(
                '/api/v1/teams/$id/avatar',
                file,
                onSendProgress: onProgress == null
                    ? null
                    : (sent, total) => onProgress(total > 0 ? sent / total : 0),
              ))
              as Map<String, dynamic>)['avatarUrl']
          as String;

  /// Removes the team picture; the team falls back to its icon glyph.
  Future<void> deleteTeamAvatar(String id) =>
      _api.delete('/api/v1/teams/$id/avatar');

  /// Adds [userIds] to the team with a single [role] + [access] for the batch.
  Future<Team> addTeamMembers(
    String teamId,
    List<String> userIds, {
    required TeamRole role,
    required ProjectAccess access,
  }) async => Team.fromJson(
    await _api.post(
          '/api/v1/teams/$teamId/members',
          body: {
            'userIds': userIds,
            'role': role.wire,
            'access': access.toJson(),
          },
        )
        as Map<String, dynamic>,
  );

  Future<Team> updateTeamMembership(
    String teamId,
    String userId, {
    TeamRole? role,
    ProjectAccess? access,
  }) async => Team.fromJson(
    await _api.patch(
          '/api/v1/teams/$teamId/members/$userId',
          body: {
            if (role != null) 'role': role.wire,
            if (access != null) 'access': access.toJson(),
          },
        )
        as Map<String, dynamic>,
  );

  Future<Team> removeTeamMember(String teamId, String userId) async =>
      Team.fromJson(
        await _api.delete('/api/v1/teams/$teamId/members/$userId')
            as Map<String, dynamic>,
      );

  Future<Team> attachTeamProjects(
    String teamId,
    List<String> projectIds,
  ) async => Team.fromJson(
    await _api.post(
          '/api/v1/teams/$teamId/projects',
          body: {'projectIds': projectIds},
        )
        as Map<String, dynamic>,
  );

  Future<Project> createTeamProject(
    String teamId, {
    required String key,
    required String name,
    String? description,
    String? color,
    String? leadId,
  }) async => Project.fromJson(
    await _api.post(
          '/api/v1/teams/$teamId/projects/new',
          body: {
            'key': key,
            'name': name,
            'description': ?description,
            'color': ?color,
            'leadId': ?leadId,
          },
        )
        as Map<String, dynamic>,
  );

  Future<Team> detachTeamProject(String teamId, String projectId) async =>
      Team.fromJson(
        await _api.delete('/api/v1/teams/$teamId/projects/$projectId')
            as Map<String, dynamic>,
      );

  Future<List<TeamActivity>> teamActivity(String teamId, {int page = 0}) async {
    final data =
        await _api.get('/api/v1/teams/$teamId/activity', query: {'page': page})
            as Map<String, dynamic>;
    return ((data['content'] as List<dynamic>?) ?? const [])
        .map((a) => TeamActivity.fromJson(a as Map<String, dynamic>))
        .toList();
  }

  /// One newest-first page of a team's activity feed, plus the backend total.
  Future<({List<TeamActivity> items, int total})> teamActivityPage(
    String teamId, {
    int page = 0,
    int size = 20,
  }) async {
    final data =
        await _api.get(
              '/api/v1/teams/$teamId/activity',
              query: {'page': page, 'size': size},
            )
            as Map<String, dynamic>;
    return (
      items: ((data['content'] as List<dynamic>?) ?? const [])
          .map((a) => TeamActivity.fromJson(a as Map<String, dynamic>))
          .toList(),
      total: data['totalElements'] as int? ?? 0,
    );
  }

  /// The access (members/projects/boards/issues) members lose with the team.
  Future<TeamDeletionImpact> teamDeletionImpact(String teamId) async =>
      TeamDeletionImpact.fromJson(
        await _api.get('/api/v1/teams/$teamId/deletion-impact')
            as Map<String, dynamic>,
      );

  /// Raw SSE byte stream of a team deletion.
  Future<Stream<List<int>>> teamDeleteStream(
    String teamId, {
    CancelToken? cancelToken,
  }) => _api.openEventStream(
    '/api/v1/teams/$teamId/delete-stream',
    cancelToken: cancelToken,
  );
}
