import '../api/api_client.dart';
import '../models/search_api.dart';

/// The unified global search endpoint.
class SearchRepository {
  SearchRepository(this._api);

  final ApiClient _api;

  /// Unified search across issues, projects, people, boards and knowledge.
  /// [scope] is `all` (default) or a single category (`issues`, `projects`,
  /// `people`, `boards`, `docs`). A blank [query] returns just category counts.
  /// [archived] searches the archive instead (archived issues + projects) —
  /// triggered by the palette's locale-aware "archived" keyword.
  Future<SearchApiResponse> search({
    String query = '',
    String? scope,
    bool archived = false,
  }) async => SearchApiResponse.fromJson(
    await _api.get(
          '/api/v1/search',
          query: {
            'q': ?(query.trim().isEmpty ? null : query.trim()),
            'scope': ?scope,
            if (archived) 'archived': true,
          },
        )
        as Map<String, dynamic>,
  );
}
