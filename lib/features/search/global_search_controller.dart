import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/repositories/search_repository.dart';
import '../../core/blocs/theme_cubit.dart';
import '../../core/models/search_api.dart';
import '../../core/storage/app_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_widgets.dart' show stateLabel;
import 'search_models.dart';

/// A category group of results, in [SearchCat] order.
class SearchGroup {
  const SearchGroup(this.cat, this.items);
  final SearchCat cat;
  final List<SearchEntry> items;
}

/// Drives the global search palette. Commands are matched client-side (pure UI
/// actions, instant/offline); everything else (issues, projects, people,
/// boards, docs) is searched server-side via `/api/v1/search` (debounced,
/// stale responses discarded). See [[project_global_search]].
class GlobalSearchController extends ChangeNotifier {
  GlobalSearchController({required this.repository, required this.storage}) {
    _recents = storage.recentSearches.toList();
  }

  final SearchRepository repository;
  final AppStorage storage;

  static const _debounce = Duration(milliseconds: 180);

  bool _disposed = false;
  Timer? _debounceTimer;
  int _reqSeq = 0;

  // ---- client-side commands ----
  List<SearchEntry> _commands = const [];

  /// Archive trigger words. Typing one (alone or as a prefix) switches the
  /// server search to archived issues + projects; the rest of the query keeps
  /// filtering within the archive. Every supported app language is always
  /// accepted (a German user may think in either word, and the set must not
  /// depend on i18n assets being loaded); [load] adds the locale's own word
  /// from i18n on top for future languages.
  final Set<String> _archivedKeywords = {'archived', 'archiviert'};

  // ---- server results (already mapped to SearchEntry) ----
  List<SearchGroup> _serverGroups = const [];
  final Map<SearchCat, int> _counts = {};
  Map<SearchCat, int> get counts => _counts;

  bool _loading = false;
  bool get loading => _loading;

  // ---- query state ----
  String _query = '';
  String get query => _query;
  SearchCat? _scope; // null = All
  SearchCat? get scope => _scope;
  int _selected = 0;
  int get selected => _selected;

  List<String> _recents = const [];
  List<String> get recents => _recents;

  // ---- derived (recomposed on every change) ----
  List<SearchGroup> _groups = const [];
  List<SearchGroup> get groups => _groups;
  List<SearchEntry> _flat = const [];

  bool get showRecents => _query.trim().isEmpty && _scope == null;
  int get flatLength => showRecents ? _recents.length : _flat.length;

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// Builds the client commands (localised via [t]) and fetches initial counts.
  Future<void> load({required String Function(String) t}) async {
    // i18next echoes the raw key when it can't resolve (e.g. assets not yet
    // reloaded) — a dot marks that case, so never treat it as a keyword.
    final localized = t('search.archivedKeyword').trim().toLowerCase();
    if (localized.isNotEmpty && !localized.contains('.')) {
      _archivedKeywords.add(localized);
    }
    _commands = _buildCommands(t);
    _recount();
    _recompose();
    _safeNotify();
    await _runSearch();
  }

  // ─────────────────────────── searching ────────────────────────────────

  /// Fires the server search for the current query/scope, discarding any
  /// response that is superseded by a newer request.
  Future<void> _runSearch() async {
    // Commands-only scope never needs the backend.
    if (_scope == SearchCat.commands) {
      _serverGroups = const [];
      _recompose();
      _safeNotify();
      return;
    }
    final seq = ++_reqSeq;
    _loading = true;
    try {
      final parsed = _parseArchiveKeyword(_query);
      final response = await repository.search(
        query: parsed.query,
        scope: _scope?.name,
        archived: parsed.archived,
      );
      if (_disposed || seq != _reqSeq) return; // stale
      _applyResponse(response);
      _loading = false;
      _recompose();
      _safeNotify();
    } on ApiFailure {
      if (_disposed || seq != _reqSeq) return;
      _loading = false;
      _safeNotify();
    }
  }

  void _applyResponse(SearchApiResponse response) {
    // counts (always present, query-independent)
    for (final entry in response.counts.entries) {
      final cat = _catFromName(entry.key);
      if (cat != null) _counts[cat] = entry.value;
    }
    // grouped results → SearchEntry
    final groups = <SearchGroup>[];
    for (final group in response.groups) {
      final cat = _catFromName(group.category);
      if (cat == null) continue;
      groups.add(SearchGroup(cat, group.items.map(_mapHit).toList()));
    }
    _serverGroups = groups;
  }

  SearchEntry _mapHit(SearchApiHit hit) {
    final cat = _catFromName(hit.category) ?? SearchCat.issues;
    void open(BuildContext context) => context.go(hit.route);
    switch (cat) {
      case SearchCat.issues:
        return SearchEntry(
          cat: cat,
          key: 'i-${hit.id}',
          title: hit.title,
          keys: hit.title.toLowerCase(),
          mono: hit.readableId,
          issueType: hit.type,
          statusColor: hit.state != null
              ? AppColors.stateColor(hit.state!)
              : null,
          statusName: hit.state != null ? stateLabel(hit.state!) : null,
          avatarName: hit.assigneeName,
          avatarUrl: hit.assigneeAvatarUrl,
          archived: hit.archived,
          onSelect: open,
        );
      case SearchCat.projects:
        final members = hit.memberNames.length;
        return SearchEntry(
          cat: cat,
          key: 'p-${hit.id}',
          title: hit.title,
          keys: hit.title.toLowerCase(),
          subtitle:
              '${hit.openCount ?? 0} open · ${hit.doneCount ?? 0} done · $members members',
          keyChipText: hit.projectKey,
          keyChipColor: hit.projectColor != null
              ? _parseHex(hit.projectColor!)
              : null,
          memberNames: hit.memberNames,
          archived: hit.archived,
          onSelect: open,
        );
      case SearchCat.people:
        return SearchEntry(
          cat: cat,
          key: 'u-${hit.id}',
          title: hit.title,
          keys: hit.title.toLowerCase(),
          subtitle: hit.subtitle,
          avatarName: hit.title,
          avatarUrl: hit.avatarUrl,
          onSelect: open,
        );
      case SearchCat.boards:
        return SearchEntry(
          cat: cat,
          key: 'b-${hit.id}',
          title: hit.title,
          keys: hit.title.toLowerCase(),
          subtitle: hit.subtitle,
          leadingIcon: LucideIcons.columns3,
          onSelect: open,
        );
      case SearchCat.docs:
        return SearchEntry(
          cat: cat,
          key: 'k-${hit.id}',
          title: hit.title,
          keys: hit.title.toLowerCase(),
          subtitle: '${hit.space ?? 'Knowledge'} · ${_relative(hit.updatedAt)}',
          leadingIcon: LucideIcons.fileText,
          onSelect: open,
        );
      case SearchCat.commands:
        return SearchEntry(
          cat: cat,
          key: 'x-${hit.id}',
          title: hit.title,
          keys: hit.title.toLowerCase(),
          onSelect: open,
        );
    }
  }

  /// Detects an archive keyword ("archiviert" / "archived", any supported
  /// language) at the start of the query and strips it:
  /// `archiviert login bug` → archived search for `login bug`.
  ({String query, bool archived}) _parseArchiveKeyword(String raw) {
    final trimmed = raw.trim();
    final lower = trimmed.toLowerCase();
    for (final keyword in _archivedKeywords) {
      if (lower == keyword) return (query: '', archived: true);
      if (lower.startsWith('$keyword ')) {
        return (
          query: trimmed.substring(keyword.length).trim(),
          archived: true,
        );
      }
    }
    return (query: trimmed, archived: false);
  }

  // ─────────────────────────── composition ──────────────────────────────

  /// Combines matched commands (client) with the server groups into the final
  /// ordered, capped group list + flat selectable list.
  void _recompose() {
    final out = <SearchGroup>[];

    final commands = _matchCommands();
    if (commands.isNotEmpty) out.add(SearchGroup(SearchCat.commands, commands));

    // Server groups already arrive in category order and pre-capped.
    out.addAll(_serverGroups);

    _groups = out;
    _flat = [for (final g in out) ...g.items];
    if (_selected >= flatLength) {
      _selected = flatLength == 0 ? 0 : flatLength - 1;
    }
    if (_selected < 0) _selected = 0;
  }

  /// Client-side fuzzy match over commands (every term a substring of `keys`).
  List<SearchEntry> _matchCommands() {
    if (_scope != null && _scope != SearchCat.commands) return const [];
    final terms = _query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final cap = _scope == SearchCat.commands ? 24 : 5;
    if (terms.isEmpty) {
      // Empty query only surfaces commands under the Commands scope.
      return _scope == SearchCat.commands
          ? _commands.take(cap).toList()
          : const [];
    }
    final scored = <({SearchEntry it, int s})>[];
    for (final it in _commands) {
      var ok = true;
      var score = 0;
      for (final term in terms) {
        final at = it.keys.indexOf(term);
        if (at == -1) {
          ok = false;
          break;
        }
        score += at;
        if (it.title.toLowerCase().startsWith(term)) score -= 40;
      }
      if (ok) scored.add((it: it, s: score));
    }
    scored.sort((a, b) => a.s - b.s);
    return [for (final e in scored.take(cap)) e.it];
  }

  void _recount() {
    _counts[SearchCat.commands] = _commands.length;
  }

  // ---- mutations ----
  void setQuery(String value) {
    _query = value;
    _selected = 0;
    _recompose(); // instant command feedback; server results follow
    _safeNotify();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _runSearch);
  }

  void setScope(SearchCat? value) {
    _scope = value;
    _selected = 0;
    _recompose();
    _safeNotify();
    _debounceTimer?.cancel();
    _runSearch();
  }

  /// Tab / Shift+Tab through `[All, ...categories]`.
  void cycleScope(bool forward) {
    const chips = <SearchCat?>[null, ...SearchCat.values];
    final i = chips.indexOf(_scope);
    final next = (i + (forward ? 1 : chips.length - 1)) % chips.length;
    setScope(chips[next]);
  }

  void moveSelection(int delta) {
    final len = flatLength;
    if (len == 0) return;
    _selected = (_selected + delta).clamp(0, len - 1);
    notifyListeners();
  }

  void setSelected(int index) {
    if (index == _selected) return;
    _selected = index;
    notifyListeners();
  }

  /// The currently selected result entry (null in the recents state).
  SearchEntry? get selectedEntry {
    if (showRecents) return null;
    if (_selected < 0 || _selected >= _flat.length) return null;
    return _flat[_selected];
  }

  /// The currently selected recent query (null outside the recents state).
  String? get selectedRecent {
    if (!showRecents) return null;
    if (_selected < 0 || _selected >= _recents.length) return null;
    return _recents[_selected];
  }

  // ---- recents ----
  void pushRecent(String term) {
    final t = term.trim();
    if (t.isEmpty) return;
    final next = [
      t,
      for (final r in _recents)
        if (r.toLowerCase() != t.toLowerCase()) r,
    ].take(AppStorage.recentSearchMax).toList();
    _recents = next;
    storage.setRecentSearches(next);
    notifyListeners();
  }

  void clearRecents() {
    _recents = const [];
    storage.setRecentSearches(const []);
    _selected = 0;
    notifyListeners();
  }

  // ─────────────────────────── commands ─────────────────────────────────

  List<SearchEntry> _buildCommands(String Function(String) t) {
    const nav = <(String, String, IconData)>[
      ('/dashboard', 'search.cmd.dashboard', LucideIcons.layoutDashboard),
      ('/projects', 'search.cmd.projects', LucideIcons.squareKanban),
      ('/issues', 'search.cmd.issues', LucideIcons.circleCheck),
      ('/board', 'search.cmd.board', LucideIcons.columns3),
      ('/gantt', 'search.cmd.timeline', LucideIcons.chartColumnStacked),
      ('/reports', 'search.cmd.reports', LucideIcons.chartLine),
      ('/knowledge', 'search.cmd.knowledge', LucideIcons.bookOpen),
    ];
    return [
      for (final (route, labelKey, icon) in nav)
        SearchEntry(
          cat: SearchCat.commands,
          key: 'c-$route',
          title: t(labelKey),
          keys: '${t(labelKey)} navigate jump $route'.toLowerCase(),
          leadingIcon: icon,
          onSelect: (context) => context.go(route),
        ),
      SearchEntry(
        cat: SearchCat.commands,
        key: 'c-new',
        title: t('search.cmd.newIssue'),
        keys: '${t('search.cmd.newIssue')} new issue create add task bug'
            .toLowerCase(),
        leadingIcon: LucideIcons.plus,
        hint: 'C',
        onSelect: (context) => context.go('/board'),
      ),
      SearchEntry(
        cat: SearchCat.commands,
        key: 'c-theme',
        title: t('search.cmd.toggleTheme'),
        keys: '${t('search.cmd.toggleTheme')} theme dark light appearance mode'
            .toLowerCase(),
        leadingIcon: LucideIcons.sunMoon,
        closesOnSelect: false,
        onSelect: (context) {
          final cubit = context.read<ThemeCubit>();
          final isDark = Theme.of(context).brightness == Brightness.dark;
          cubit.setMode(isDark ? ThemeMode.light : ThemeMode.dark);
        },
      ),
    ];
  }

  // ─────────────────────────── helpers ──────────────────────────────────

  static SearchCat? _catFromName(String name) => switch (name.toUpperCase()) {
    'COMMANDS' => SearchCat.commands,
    'ISSUES' => SearchCat.issues,
    'PROJECTS' => SearchCat.projects,
    'PEOPLE' => SearchCat.people,
    'BOARDS' => SearchCat.boards,
    'DOCS' => SearchCat.docs,
    _ => null,
  };

  static Color _parseHex(String hex) {
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    final value = int.tryParse(h, radix: 16);
    return value == null ? const Color(0xFF7E81AE) : Color(value);
  }

  static String _relative(DateTime? date) {
    if (date == null) return 'recently';
    final diff = DateTime.now().difference(date);
    if (diff.inDays >= 1) return 'updated ${diff.inDays}d';
    if (diff.inHours >= 1) return 'updated ${diff.inHours}h';
    if (diff.inMinutes >= 1) return 'updated ${diff.inMinutes}m';
    return 'updated just now';
  }
}
