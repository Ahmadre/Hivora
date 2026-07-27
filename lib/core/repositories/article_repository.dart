import '../api/api_client.dart';
import '../models/content_models.dart';

/// Knowledge-base articles and spaces (the raw REST surface; the feature-level
/// cache in `features/knowledge/data` builds on top of this).
class ArticleRepository {
  ArticleRepository(this._api);

  final ApiClient _api;

  /// Lists articles. [all] fetches every article (the whole knowledge base
  /// across projects + org-wide); otherwise scoped by [projectId] (or org-wide
  /// when null).
  Future<List<Article>> articles({String? projectId, bool all = false}) async =>
      ((await _api.get(
                '/api/v1/articles',
                query: {'projectId': ?projectId, if (all) 'all': true},
              ))
              as List<dynamic>)
          .map((a) => Article.fromJson(a as Map<String, dynamic>))
          .toList();

  Future<Article> article(String id) async => Article.fromJson(
    await _api.get('/api/v1/articles/$id') as Map<String, dynamic>,
  );

  /// Articles that reference [issueReadableId] via a `{{issue:KEY}}` token,
  /// resolved server-side (ACL-scoped, capped) so the issue-detail "Documented
  /// in" panel never has to drain and regex-scan the whole KB corpus client-side.
  Future<List<Article>> articlesReferencingIssue(
    String issueReadableId,
  ) async =>
      ((await _api.get(
                '/api/v1/articles',
                query: {'referencesIssue': issueReadableId},
              ))
              as List<dynamic>)
          .map((a) => Article.fromJson(a as Map<String, dynamic>))
          .toList();

  Future<Article> saveArticle({
    String? id,
    required String title,
    /// Markdown. Accepted and converted server-side; [contentDoc] wins.
    String? content,
    /// The Lexical document — what the editor produces.
    String? contentDoc,
    String? projectId,
    String? teamId,
    String? parentId,
    String? space,
    String? icon,
    List<String>? tags,
  }) async {
    final body = {
      'title': title,
      'content': ?content,
      'contentDoc': ?contentDoc,
      'projectId': ?projectId,
      'teamId': ?teamId,
      'parentId': ?parentId,
      'space': ?space,
      'icon': ?icon,
      'tags': ?tags,
    };
    final data = id == null
        ? await _api.post('/api/v1/articles', body: body)
        : await _api.patch('/api/v1/articles/$id', body: body);
    return Article.fromJson(data as Map<String, dynamic>);
  }

  /// Moves an article under a new parent (or to the space root when [parentId]
  /// is null — sent explicitly, unlike [saveArticle] which omits nulls) and/or
  /// into a different [space]. Content/tags/icon are left untouched.
  Future<Article> moveArticle(
    String id, {
    required String title,
    String? parentId,
    String? space,
  }) async {
    final data = await _api.patch(
      '/api/v1/articles/$id',
      body: {'title': title, 'parentId': parentId, 'space': ?space},
    );
    return Article.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deleteArticle(String id) async =>
      _api.delete('/api/v1/articles/$id');

  /// Lists every knowledge-base space (organisation-wide, sorted).
  Future<List<Space>> spaces() async =>
      ((await _api.get('/api/v1/spaces')) as List<dynamic>)
          .map((s) => Space.fromJson(s as Map<String, dynamic>))
          .toList();

  Future<Space> createSpace({
    required String name,
    String? icon,
    int? hue,
    String? description,
  }) async {
    final data = await _api.post(
      '/api/v1/spaces',
      body: {
        'name': name,
        'icon': ?icon,
        'hue': ?hue,
        'description': ?description,
      },
    );
    return Space.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deleteSpace(String id) async =>
      _api.delete('/api/v1/spaces/$id');
}
