import '../../../core/models/content_models.dart';
import '../../../core/models/core_models.dart';
import '../../../core/repositories/article_repository.dart';
import '../../../core/repositories/auth_repository.dart';
import '../../../core/repositories/user_repository.dart';
import 'knowledge_models.dart';

/// Backend-backed Knowledge Base store. Articles, spaces and people all come
/// from the real API (`/api/v1/articles`, `/users`) — there is **no** frontend
/// seed data. The bidirectional issue⇄article relationship is derived live by
/// scanning article bodies for `{{issue:KEY-N}}` tokens.
///
/// View models ([KbArticle] / [KbUser] / [KbSpace]) are kept so the KB UI is
/// unchanged; they are populated from the backend [Article] / [DirectoryUser].
/// "Spaces" are not a backend entity: they are the distinct `space` values on
/// articles, dressed with presentational metadata from [_spaceCatalog].
class KnowledgeRepository {
  KnowledgeRepository({
    required ArticleRepository articles,
    required UserRepository users,
    required AuthRepository auth,
  }) : _articleApi = articles,
       _userApi = users,
       _authApi = auth;

  final ArticleRepository _articleApi;
  final UserRepository _userApi;
  final AuthRepository _authApi;

  final Map<String, KbArticle> _articles = {};
  final Map<String, KbUser> _users = {};
  final List<KbSpace> _spaces = [];

  /// Persisted backend spaces, keyed by name (insertion-ordered by sortOrder).
  /// Source of truth for a space's icon/hue/description, and the reason an empty
  /// space (no articles yet) still shows on the home grid.
  final Map<String, Space> _backendSpaces = {};
  KbUser? _me;
  bool _loaded = false;

  /// Presentational metadata for known spaces (icon · hue · description). The
  /// space *names* are real (they live on the articles); only the chrome is
  /// configured here.
  KbUser get me =>
      _me ?? (_users.values.isNotEmpty ? _users.values.first : _fallbackUser);
  static const _fallbackUser = KbUser(id: '', name: 'You', title: '', hue: 248);

  // ── lifecycle ───────────────────────────────────────────────────────────

  /// Loads articles + people from the backend once. Safe to call repeatedly —
  /// subsequent calls are no-ops until [reload] forces a refresh.
  Future<void> init() async {
    if (_loaded) return;
    await reload();
  }

  Future<void> reload() async {
    final results = await Future.wait([
      _articleApi.articles(all: true),
      _userApi.users(),
    ]);
    final articles = results[0] as List<Article>;
    final dirUsers = results[1] as List<DirectoryUser>;

    _users
      ..clear()
      ..addEntries(dirUsers.map((u) => MapEntry(u.id, _toKbUser(u))));
    try {
      final me = await _authApi.me();
      _me = KbUser(
        id: me.id,
        name: me.displayName,
        title: me.title ?? '',
        hue: _hueFor(me.id),
        pronouns: me.pronouns,
      );
    } catch (_) {
      // Non-critical — `me` falls back to the first directory user.
    }

    _backendSpaces.clear();
    try {
      for (final s in await _articleApi.spaces()) {
        _backendSpaces[s.name] = s;
      }
    } catch (_) {
      // Older backend without /spaces — fall back to derived spaces only.
    }

    _articles
      ..clear()
      ..addEntries(articles.map((a) => MapEntry(a.id, _toKbArticle(a))));
    _rebuildSpaces();
    _loaded = true;
  }

  void _rebuildSpaces() {
    final articleNames = <String>{for (final a in _articles.values) a.spaceId}
      ..removeWhere((n) => n.isEmpty);
    // Persisted backend spaces first (already in sortOrder), then any space that
    // only exists as an article's `space` value (alphabetically). No hardcoded
    // placeholder spaces — an empty knowledge base shows the create-space action,
    // and every listed space is a real, deletable backend entity.
    final ordered = <String>[
      ..._backendSpaces.keys,
      ...(articleNames.where((n) => !_backendSpaces.containsKey(n)).toList()
        ..sort()),
    ];
    _spaces
      ..clear()
      ..addAll(ordered.map(_spaceFor));
  }

  // ── mappers ───────────────────────────────────────────────────────────────

  KbUser _toKbUser(DirectoryUser u) => KbUser(
    id: u.id,
    pronouns: u.pronouns,
    name: u.displayName,
    title: u.title ?? '',
    hue: _hueFor(u.id),
  );

  KbArticle _toKbArticle(Article a) {
    final author = a.authorId ?? '';
    return KbArticle(
      id: a.id,
      spaceId: a.space ?? 'Engineering',
      parentId: a.parentId,
      title: a.title,
      icon: a.icon ?? 'file-text',
      authorId: author,
      contributorIds: author.isEmpty ? const [] : [author],
      updated: _ago(a.updatedAt),
      created: _dateLabel(a.createdAt),
      reads: 0,
      labels: a.tags,
      status: 'published',
      body: a.content ?? '',
      doc: a.contentDoc,
    );
  }

  KbSpace _spaceFor(String name) {
    final backend = _backendSpaces[name];
    final key = name.length >= 3
        ? name.substring(0, 3).toUpperCase()
        : name.toUpperCase();
    return KbSpace(
      id: name,
      key: key,
      name: name,
      hue: backend?.hue ?? 250,
      icon: backend?.icon ?? 'file-text',
      desc: backend?.description ?? '',
    );
  }

  static int _hueFor(String id) => id.isEmpty ? 248 : (id.hashCode.abs() % 360);

  static String _ago(DateTime? t) {
    if (t == null) return 'just now';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 30) return '${d.inDays}d';
    if (d.inDays < 365) return '${(d.inDays / 30).floor()}mo';
    return '${(d.inDays / 365).floor()}y';
  }

  static String _dateLabel(DateTime? t) {
    if (t == null) return 'Today';
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return 'Today';
    }
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[t.month - 1]} ${t.day}, ${t.year}';
  }

  // ── lookups ─────────────────────────────────────────────────────────────

  KbUser? userById(String id) => _users[id];
  KbSpace? spaceById(String id) => _spaces.cast<KbSpace?>().firstWhere(
    (s) => s?.id == id,
    orElse: () => null,
  );
  KbArticle? articleById(String id) => _articles[id];

  List<KbUser> get users => _users.values.toList(growable: false);
  List<KbSpace> get spaces => List.unmodifiable(_spaces);
  List<KbArticle> get articles => _articles.values.toList(growable: false);

  List<KbArticle> articlesInSpace(String spaceId) =>
      articles.where((a) => a.spaceId == spaceId).toList();

  int articleCountInSpace(String spaceId) =>
      articles.where((a) => a.spaceId == spaceId).length;

  // ── derived bidirectional links ───────────────────────────────────────────

  /// Server-resolved backlinks: fetches the articles referencing
  /// [issueReadableId] via the dedicated endpoint, so the issue-detail
  /// "Documented in" panel never has to drain and regex-scan the whole KB corpus
  /// client-side (the old path called [init] + [articlesForIssue]).
  Future<List<KbArticle>> articlesReferencingIssue(
    String issueReadableId,
  ) async {
    final refs = await _articleApi.articlesReferencingIssue(issueReadableId);
    return refs.map(_toKbArticle).toList();
  }

  /// Related articles referenced via `{{doc:…}}` tokens in [body].
  List<KbArticle> relatedArticles(String body) {
    final re = RegExp(r'\{\{doc:(\w+)\}\}');
    final seen = <String>{};
    final out = <KbArticle>[];
    for (final m in re.allMatches(body)) {
      final id = m.group(1)!;
      if (seen.add(id)) {
        final a = _articles[id];
        if (a != null) out.add(a);
      }
    }
    return out;
  }

  // ── mutations (write through to the backend) ──────────────────────────────

  Future<KbArticle> saveEdit(
    String id, {
    required String title,
    required String doc,
    required String spaceId,
  }) async {
    final existing = _articles[id];
    final saved = await _articleApi.saveArticle(
      id: id,
      title: title,
      contentDoc: doc,
      space: spaceId,
      icon: existing?.icon,
      tags: existing?.labels,
    );
    final kb = _toKbArticle(saved);
    _articles[id] = kb;
    _rebuildSpaces();
    return kb;
  }

  Future<KbArticle> createArticle({
    required String title,
    required String doc,
    required String spaceId,
    String? parentId,
  }) async {
    final saved = await _articleApi.saveArticle(
      title: title,
      contentDoc: doc,
      space: spaceId,
      parentId: parentId,
      icon: 'file-text',
    );
    final kb = _toKbArticle(saved);
    _articles[kb.id] = kb;
    _rebuildSpaces();
    return kb;
  }

  /// Re-parents [id] under [parentId] (null = space root) and/or moves it into
  /// [spaceId]. Children keep their own parent links, so the subtree moves with
  /// it. Returns the moved article.
  Future<KbArticle> moveArticle(
    String id, {
    String? parentId,
    String? spaceId,
  }) async {
    final existing = _articles[id];
    if (existing == null) return Future.error('unknown article');
    final saved = await _articleApi.moveArticle(
      id,
      title: existing.title,
      parentId: parentId,
      space: spaceId ?? existing.spaceId,
    );
    final kb = _toKbArticle(saved);
    _articles[id] = kb;
    _rebuildSpaces();
    return kb;
  }

  Future<void> deleteArticle(String id) async {
    await _articleApi.deleteArticle(id);
    _articles.remove(id);
    _rebuildSpaces();
  }

  /// Creates a persisted space and returns its view model. The space shows up on
  /// the home grid immediately, even before it has any articles.
  Future<KbSpace> createSpace({
    required String name,
    required String icon,
    required int hue,
    String? description,
  }) async {
    final s = await _articleApi.createSpace(
      name: name,
      icon: icon,
      hue: hue,
      description: description,
    );
    _backendSpaces[s.name] = s;
    _rebuildSpaces();
    return _spaceFor(s.name);
  }

  /// Deletes the persisted space named [spaceId]. The backend rejects this while
  /// the space still has articles (surfaced as an [ApiFailure]).
  Future<void> deleteSpace(String spaceId) async {
    final backend = _backendSpaces[spaceId];
    if (backend == null) return Future.error('unknown space');
    await _articleApi.deleteSpace(backend.id);
    _backendSpaces.remove(spaceId);
    _rebuildSpaces();
  }

  /// Whether [spaceId] is a persisted backend space (vs. one merely derived from
  /// an article's `space` value) — only persisted spaces can be deleted.
  bool isPersistedSpace(String spaceId) => _backendSpaces.containsKey(spaceId);

  /// Whether [maybeAncestorId] is [id] itself or one of its ancestors — used to
  /// reject moves that would create a cycle.
  bool isSelfOrAncestor(String maybeAncestorId, String id) {
    var cursor = _articles[id];
    while (cursor != null) {
      if (cursor.id == maybeAncestorId) return true;
      final parent = cursor.parentId;
      cursor = parent == null ? null : _articles[parent];
    }
    return false;
  }
}
