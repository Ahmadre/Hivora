import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../models/deletion_models.dart';
import '../models/work_models.dart';

/// Projects: CRUD, workflow/label settings support, the Gantt aggregate, and
/// cascading deletion.
class ProjectRepository {
  ProjectRepository(this._api);

  final ApiClient _api;

  Future<List<Project>> projects({bool archived = false}) async =>
      ((await _api.get(
                '/api/v1/projects',
                query: archived ? {'archived': 'true'} : null,
              ))
              as List<dynamic>)
          .map((p) => Project.fromJson(p as Map<String, dynamic>))
          .toList();

  /// One page of the visible projects, optionally narrowed by [query] (matched
  /// against name and key on the server).
  ///
  /// This is what the project pickers read. [projects] returns the whole set in
  /// one array, which is fine for a filter dropdown but turns into a long, ever
  /// growing scroll in a picker — so anything the user searches through pages
  /// here instead.
  Future<({List<Project> projects, int total})> searchProjects({
    String? query,
    int page = 0,
    int size = 25,
    bool archived = false,
  }) async {
    final data =
        await _api.get(
              '/api/v1/projects/search',
              query: {
                if (query != null && query.isNotEmpty) 'q': query,
                if (archived) 'archived': true,
                'page': page,
                'size': size,
              },
            )
            as Map<String, dynamic>;
    return (
      projects: ((data['content'] as List<dynamic>?) ?? [])
          .map((p) => Project.fromJson(p as Map<String, dynamic>))
          .toList(),
      total: data['totalElements'] as int? ?? 0,
    );
  }

  /// The named projects, filtered server-side to the ones the caller may see.
  /// A picker uses this to label ids it already holds — a board's current span,
  /// say — without paging until those projects happen to come up.
  Future<List<Project>> resolveProjects(List<String> ids) async {
    if (ids.isEmpty) return const [];
    return ((await _api.get(
                  '/api/v1/projects/resolve',
                  query: {'ids': ids.join(',')},
                ))
                as List<dynamic>)
            .map((p) => Project.fromJson(p as Map<String, dynamic>))
            .toList();
  }

  Future<Project> project(String id) async => Project.fromJson(
    await _api.get('/api/v1/projects/$id') as Map<String, dynamic>,
  );

  /// Issue count per workflow-state name — used by the settings UI to warn
  /// before deleting a state that still has issues assigned.
  Future<Map<String, int>> projectStateUsage(String id) async {
    final json =
        await _api.get('/api/v1/projects/$id/state-usage')
            as Map<String, dynamic>;
    return json.map((k, v) => MapEntry(k, (v as num).toInt()));
  }

  Future<Project> createProject({
    required String key,
    required String name,
    String? description,
    String? color,
    String? leadId,
  }) async => Project.fromJson(
    await _api.post(
          '/api/v1/projects',
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

  /// Atomically commits the full edited project from the settings surface. Pass
  /// only the fields that changed; the server re-validates every invariant
  /// (>=1 lead, >=2 states, >=1 resolved) and cascades workflow/label renames.
  Future<Project> updateProject(String id, Map<String, dynamic> patch) async =>
      Project.fromJson(
        await _api.patch('/api/v1/projects/$id', body: patch)
            as Map<String, dynamic>,
      );

  /// Permanently removes a label from the project and every issue using it.
  Future<void> deleteProjectLabel(
    String projectId,
    String label,
  ) => _api.delete(
    '/api/v1/projects/$projectId/labels?label=${Uri.encodeQueryComponent(label)}',
  );

  Future<List<GanttTask>> gantt(String projectId) async =>
      ((await _api.get('/api/v1/projects/$projectId/gantt')) as List<dynamic>)
          .map((t) => GanttTask.fromJson(t as Map<String, dynamic>))
          .toList();

  /// Affected boards/issues/etc. + the projects issues could migrate into.
  Future<ProjectDeletionImpact> projectDeletionImpact(String projectId) async =>
      ProjectDeletionImpact.fromJson(
        await _api.get('/api/v1/projects/$projectId/deletion-impact')
            as Map<String, dynamic>,
      );

  /// Raw SSE byte stream of a project deletion. [strategy]/[migrateToProjectId]
  /// are required only when the project still has issues.
  Future<Stream<List<int>>> projectDeleteStream(
    String projectId, {
    IssueStrategy? strategy,
    String? migrateToProjectId,
    CancelToken? cancelToken,
  }) {
    final query = <String, String>{
      'issueStrategy': ?strategy?.wire,
      'migrateToProjectId': ?migrateToProjectId,
    };
    final suffix = query.isEmpty
        ? ''
        : '?${query.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
    return _api.openEventStream(
      '/api/v1/projects/$projectId/delete-stream$suffix',
      cancelToken: cancelToken,
    );
  }
}
