part of 'issue_detail_sheet.dart';

/// Shared editable issue detail — used both inside the sheet and by the
/// `/issues/:id` route. When [header] is supplied (sheet mode) the readable id
/// lives in the wolt top bar and the internal top bar is hidden.
class IssueDetailBody extends StatefulWidget {
  const IssueDetailBody({
    super.key,
    required this.issueId,
    this.onChanged,
    this.header,
    this.sheetScroll,
    this.composerRev,
    this.floatingComposer = false,
    this.canMinimize = false,
    this.targetCommentId,
  });

  final String issueId;
  final VoidCallback? onChanged;
  final ValueNotifier<Issue?>? header;

  /// Deep-link target: scroll to + flash this comment once the thread loads.
  final String? targetCommentId;

  /// The host's scroll controller. Lets the body animate to the newest comment
  /// after posting (sheet: the wolt page scroll; route: the page scroll view).
  final ScrollController? sheetScroll;

  /// Bumped to force the host's floating composer (a separate subtree — the
  /// sheet's sticky bar or the route's Stack overlay) to rebuild when its
  /// appearance depends on body state (inline edit).
  final ValueNotifier<int>? composerRev;

  /// Whether the host renders the composer as a floating bar (via
  /// [buildFloatingComposer]) instead of inline in the activity card — true for
  /// both the modal sheet and the full-page route.
  final bool floatingComposer;

  /// Full-page (route) mode only: whether this view was promoted from the modal
  /// sheet and can therefore shrink back to it. Direct deep-links open the page
  /// with no modal underneath, so the "exit full screen" button is hidden.
  final bool canMinimize;

  @override
  State<IssueDetailBody> createState() => IssueDetailBodyState();
}

class IssueDetailBodyState extends State<IssueDetailBody>
    with WidgetsBindingObserver {
  final _comment = TextEditingController();
  final _commentFocus = FocusNode();
  late final MarkdownEditingActions _commentActions = MarkdownEditingActions(
    _comment,
    _commentFocus,
  );

  /// When non-null, the composer is editing this existing comment inline (its
  /// text is loaded into [_comment]); submitting saves the edit instead of
  /// posting a new comment.
  IssueComment? _editingComment;
  final _titleCtrl = TextEditingController();
  final _descCtrl = HinataEditorController();
  // Lets the composer's "+" → Anhang drive the attachments section's own
  // (optimistic, live-updating) upload flow instead of a blind background POST.
  final _attachmentsKey = GlobalKey<AttachmentsSectionState>();

  Issue? _issue;
  // Comments are paginated newest-first server-side and displayed newest-first
  // (feed style): the newest page shows at the top and older pages append below.
  // Activity is likewise newest-first; older pages append below.
  List<IssueComment> _comments = const [];
  // Pinned comments (any project member can pin) float above the chat feed in
  // pin order — fetched separately so a pinned comment on an unloaded page still
  // shows. They're de-duplicated out of the chronological list below.
  List<IssueComment> _pinned = const [];
  List<IssueActivity> _activity = const [];
  int _commentsTotal = 0;
  int _activityTotal = 0;
  int _activityPage = 0;
  bool _loadingMore = false;
  // Latch for comment auto-pagination: load exactly ONE page each time the load
  // sentinel (at the BOTTOM of the thread) becomes visible, and re-arm only once
  // it has scrolled off-screen again. Without the latch a level-trigger would
  // reload every frame the sentinel stayed visible → a burst of page loads.
  bool _loadArmed = true;

  /// Comments are paged in small batches — only the first [_commentPageSize] load
  /// with the issue, and each scroll to the BOTTOM of the thread pulls another
  /// (older) page.
  static const int _commentPageSize = 10;

  /// Anchors the bottom-of-thread load sentinel so [_onCommentScroll] can tell
  /// when it scrolls into view (the thread lives mid-page in the shared scroll
  /// view).
  final GlobalKey _commentsLoaderKey = GlobalKey();

  /// How top-level comments are ordered (newest-first by default). Reply threads
  /// are always oldest-first, independent of this.
  CommentSort _commentSort = CommentSort.newest;

  /// Lazily-loaded reply threads, keyed by root comment id.
  final Map<String, ReplyThread> _replyThreads = {};
  static const int _replyPageSize = 10;

  // Live comment sync (SSE): reactions/pins/edits/new comments from anyone in the
  // issue arrive as a payload-free `changed` ping → re-sync the loaded window.
  // The shared [SseConnection] adds heartbeat-driven liveness detection (a
  // half-open stream is cycled instead of silently going stale) and a resync on
  // every reconnect to catch up anything missed while it was down.
  late final SseConnection _commentSse = SseConnection(
    open: (cancelToken) => _commentApi.commentEventStream(
      widget.issueId,
      cancelToken: cancelToken,
    ),
    onEvent: (_) => _scheduleCommentResync(),
    onReconnect: _scheduleCommentResync,
  );
  bool _disposed = false;
  // The host (`header`/`composerRev`) can be disposed while this body is briefly
  // still mounted + registered as a WidgetsBindingObserver during a modal→route
  // transition (Wolt's page can outlive the sheet's `whenComplete`). The host
  // flips this via [detachHostChannels] right before disposing those notifiers,
  // so a late `didChangeMetrics`/focus/data callback stops writing to them (a
  // write would throw "ValueNotifier used after disposed"). `mounted` alone
  // can't catch it — the notifiers' lifetime is the host's, not this body's.
  bool _hostDetached = false;
  // Coalesce bursts of `changed` pings (rapid pinning, a batch delete, or the
  // actor's own broadcast echo) into at most one in-flight re-sync plus one
  // trailing one, instead of firing 2 GETs per ping. Without this a batch
  // delete of K comments would fan out into ~2K near-simultaneous GETs.
  Timer? _commentResyncDebounce;
  bool _commentResyncing = false;
  bool _commentResyncQueued = false;

  // Multi-select of own comments (batch delete).
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  // Reply-to (WhatsApp quoted composer bar); mutually exclusive with editing.
  IssueComment? _replyingTo;

  // Deep-link jump: the comment briefly flashing + per-comment scroll keys.
  String? _highlightedCommentId;
  Timer? _highlightTimer;
  final Map<String, GlobalKey> _commentKeys = {};
  List<WorkItem> _workItems = const [];
  Project? _project;
  // Cross-feature smart-links: project issues (keyed by readable id) feed the
  // comment composer's `@`-menu and resolve `{{issue:…}}` chips; KB articles
  // that mention this issue are its "Documented in" backlinks.
  Map<String, Issue> _projectIssues = const {};
  // Breadcrumb ancestors + direct children (epic→stories, story→sub-tasks).
  IssueHierarchy _hierarchy = IssueHierarchy.empty;
  List<KbArticle> _documentedIn = const [];
  KnowledgeRepository get _knowledge => context.read<KnowledgeRepository>();
  // Labels deleted this session — guards against the stale _project list
  // re-suggesting a label that was just removed from the project.
  final Set<String> _deletedLabels = {};
  List<DirectoryUser> _users = const [];
  List<Sprint> _sprints = const [];
  // Id → name / avatar over the whole directory. Cached, not computed on
  // access: a single build pass reads them from a dozen places (details card,
  // hierarchy rows, comment feed, activity), and they only change where
  // [_users] does — so [_setUsers] is the one place that refreshes them.
  Map<String, String> _names = const {};
  Map<String, String> _avatars = const {};
  Map<String, String> get _sprintNames => {
    for (final s in _sprints) s.id: s.name,
  };

  /// Sole entry point for [_users] so the derived lookups can never go stale.
  void _setUsers(List<DirectoryUser> users) {
    _users = users;
    _names = {for (final u in users) u.id: u.displayName};
    _avatars = {
      for (final u in users)
        if (u.avatarUrl != null && u.avatarUrl!.isNotEmpty) u.id: u.avatarUrl!,
    };
  }

  bool _loading = true;
  String? _error;
  bool _busy = false;

  // In-flight latch for posting a comment (text or voice) so an impatient
  // double-tap on send can't POST the same comment twice.
  bool _sendingComment = false;

  // Whether the current user may hard-delete this issue (platform admin,
  // project lead, or team admin of a team owning the project). Regular
  // members only get the archive action. Defaults to false until the
  // permission probe returns, so the UI can never over-promise a delete.
  bool _canDelete = false;

  /// Read by the wolt sheet's top bar (via `bodyKey.currentState`) to pick the
  /// trash vs. archive affordance.
  bool get canDelete => _canDelete;

  /// Who is watching this issue, plus the caller's own subscription. Owned here
  /// rather than by the "…" menu that renders it: three separate top bars host
  /// that menu (wolt sheet, wide route, compact route), each in its own subtree
  /// and each rebuilding on its own schedule, and they must all agree.
  late final IssueWatchCubit _watch;

  // Inline editing + activity filter state.
  bool _editingTitle = false;
  bool _editingDesc = false;
  // Default the activity panel to the Comments tab so the conversation shows
  // up front when an issue is opened.
  _ActivityFilter _activityFilter = _ActivityFilter.comments;

  // Domain repositories, read from the (re-provided) modal scope on each access
  // — kept as getters so a `context.read` never crosses an async gap in the
  // load/mutation flows below.
  IssueRepository get _issueApi => context.read<IssueRepository>();

  /// Opens the reply-by-email composer for the current issue, or null when the
  /// action isn't available (not email-sourced, or the admin flag is off).
  VoidCallback? _replyEmailAction(Issue issue) {
    final enabled =
        context.read<AppConfigBloc>().state.meta?.isFlagEnabled('emailReply') ??
        false;
    if (!issue.isEmailSourced || !enabled) return null;
    return () => showEmailReplySheet(context, issue: issue, repo: _issueApi);
  }

  CommentRepository get _commentApi => context.read<CommentRepository>();
  ProjectRepository get _projectApi => context.read<ProjectRepository>();
  UserRepository get _userApi => context.read<UserRepository>();
  MediaRepository get _mediaApi => context.read<MediaRepository>();

  @override
  void initState() {
    super.initState();
    _watch = IssueWatchCubit(
      repository: _issueApi,
      issueId: widget.issueId,
      userId: context.read<AuthBloc>().state.user?.id,
    );
    WidgetsBinding.instance.addObserver(this);
    _commentFocus.addListener(_onCommentFocusChanged);
    // Auto-load older comments as the user scrolls toward the top of the thread.
    widget.sheetScroll?.addListener(_onCommentScroll);
    _load();
    _commentSse.start();
  }

  // Rebuild the floating composer (a separate subtree) when the comment field
  // gains/loses focus, so it can hide itself while the keyboard is up for some
  // *other* field (e.g. the sub-task or linked-issue inputs) — see
  // [buildFloatingComposer]. Focus transitions that don't move the keyboard
  // (tapping the comment field while another field's keyboard is already open)
  // wouldn't otherwise trigger a MediaQuery rebuild of the sticky bar.
  void _onCommentFocusChanged() => _bumpComposer();

  // The keyboard opening/closing decides whether the floating composer is shown
  // (it hides while another field's keyboard is up). Inside Wolt's Scaffold the
  // sticky-bar subtree never sees the keyboard inset via MediaQuery
  // (resizeToAvoidBottomInset strips it), so a MediaQuery dependency alone won't
  // rebuild it on keyboard toggles — observe the raw window metrics and nudge
  // the composer whenever they change (keyboard rising from a *different* field
  // being focused, etc.). See [buildFloatingComposer].
  @override
  void didChangeMetrics() => _bumpComposer();

  @override
  void dispose() {
    _disposed = true;
    _commentSse.stop();
    _commentResyncDebounce?.cancel();
    _highlightTimer?.cancel();
    widget.sheetScroll?.removeListener(_onCommentScroll);
    WidgetsBinding.instance.removeObserver(this);
    _commentFocus.removeListener(_onCommentFocusChanged);
    _comment.dispose();
    _commentFocus.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _watch.close();
    super.dispose();
  }

  // ── live comment sync (SSE) ────────────────────────────────────────────────
  /// Debounces + single-flights live re-syncs: a burst of `changed` pings
  /// collapses into one in-flight re-sync (plus one trailing one for anything
  /// that landed while it was running), instead of 2 GETs per ping.
  void _scheduleCommentResync() {
    if (_disposed) return;
    _commentResyncDebounce?.cancel();
    _commentResyncDebounce = Timer(
      const Duration(milliseconds: 350),
      _runCommentResync,
    );
  }

  Future<void> _runCommentResync() async {
    if (_disposed) return;
    if (_commentResyncing) {
      // One is already running — remember to run exactly one more afterwards so
      // changes that arrived mid-flight aren't missed, without stacking requests.
      _commentResyncQueued = true;
      return;
    }
    _commentResyncing = true;
    try {
      await _resyncComments();
    } finally {
      _commentResyncing = false;
      if (_commentResyncQueued && !_disposed) {
        _commentResyncQueued = false;
        _scheduleCommentResync();
      }
    }
  }

  /// Re-fetches the currently-loaded comment window + pinned set after a live
  /// change, preserving how many pages the user has scrolled through.
  Future<void> _resyncComments() async {
    if (_disposed) return;
    try {
      final want = math.max(_comments.length, _commentPageSize);
      final results = await Future.wait([
        _commentApi.comments(
          widget.issueId,
          size: want,
          sort: _commentSort.api,
        ),
        _commentApi.pinnedComments(widget.issueId),
      ]);
      if (!mounted) return;
      final page = results[0] as ({List<IssueComment> items, int total});
      setState(() {
        _comments = page.items.toList();
        _commentsTotal = page.total;
        _pinned = results[1] as List<IssueComment>;
      });
      await _resyncExpandedThreads();
      unawaited(_syncReferencedIssues());
    } catch (_) {
      // Keep the current view; the next event or manual reload reconciles.
    }
  }

  /// Re-fetches the loaded window of every currently-expanded reply thread after
  /// a live change, so new replies / reacts reconcile without collapsing it.
  Future<void> _resyncExpandedThreads() async {
    final rootIds = [
      for (final e in _replyThreads.entries)
        if (e.value.expanded) e.key,
    ];
    for (final rootId in rootIds) {
      final t = _replyThreads[rootId];
      if (t == null || !mounted) continue;
      final want = math.max(t.replies.length, _replyPageSize);
      try {
        final p = await _commentApi.commentReplies(
          widget.issueId,
          rootId,
          size: want,
        );
        if (!mounted) return;
        setState(() {
          _replyThreads[rootId] = t.copyWith(
            replies: p.items.toList(),
            total: p.total,
          );
        });
      } catch (_) {
        // Keep the current view; the next event reconciles.
      }
    }
  }

  ReplyThread _threadOf(String rootId) =>
      _replyThreads[rootId] ?? const ReplyThread();

  /// Expands (loading the first page) or collapses a root's reply thread.
  Future<void> _toggleReplies(IssueComment root) async {
    final t = _threadOf(root.id);
    if (t.expanded) {
      setState(() => _replyThreads[root.id] = t.copyWith(expanded: false));
      return;
    }
    if (t.replies.isNotEmpty) {
      setState(() => _replyThreads[root.id] = t.copyWith(expanded: true));
      return;
    }
    setState(
      () => _replyThreads[root.id] = t.copyWith(expanded: true, loading: true),
    );
    await _fetchReplies(root.id, page: 0, replace: true);
  }

  /// Loads the next page of a root's replies (oldest→newest).
  Future<void> _loadMoreReplies(IssueComment root) async {
    final t = _threadOf(root.id);
    if (t.loading || !t.hasMore) return;
    setState(() => _replyThreads[root.id] = t.copyWith(loading: true));
    await _fetchReplies(
      root.id,
      page: t.replies.length ~/ _replyPageSize,
      replace: false,
    );
  }

  Future<void> _fetchReplies(
    String rootId, {
    required int page,
    required bool replace,
  }) async {
    try {
      final p = await _commentApi.commentReplies(
        widget.issueId,
        rootId,
        page: page,
        size: _replyPageSize,
      );
      if (!mounted) return;
      final base = replace ? const <IssueComment>[] : _threadOf(rootId).replies;
      final existing = {for (final c in base) c.id};
      final merged = [
        ...base,
        for (final c in p.items)
          if (!existing.contains(c.id)) c,
      ];
      setState(() {
        _replyThreads[rootId] = _threadOf(rootId).copyWith(
          expanded: true,
          loading: false,
          replies: merged,
          total: p.total,
        );
      });
      unawaited(_syncReferencedIssues());
    } catch (_) {
      if (mounted) {
        setState(
          () => _replyThreads[rootId] = _threadOf(
            rootId,
          ).copyWith(loading: false),
        );
      }
    }
  }

  /// Switches the top-level sort and reloads from the first page.
  void _setCommentSort(CommentSort sort) {
    if (sort == _commentSort) return;
    setState(() => _commentSort = sort);
    _reloadTopLevelComments();
  }

  Future<void> _reloadTopLevelComments() async {
    try {
      final p = await _commentApi.comments(
        widget.issueId,
        size: _commentPageSize,
        sort: _commentSort.api,
      );
      if (!mounted) return;
      setState(() {
        _comments = p.items.toList();
        _commentsTotal = p.total;
        _loadArmed = true;
      });
      unawaited(_syncReferencedIssues());
    } catch (_) {
      // Keep the current view.
    }
  }

  /// Auto-loads the next older page when the load sentinel (at the bottom of the
  /// thread, which sits mid-page inside the shared scroll view) scrolls into
  /// view. Geometry-based, since all children are built eagerly here so "built"
  /// wouldn't mean "visible".
  void _onCommentScroll() {
    if (_activityFilter == _ActivityFilter.history) return;
    if (!_hasMoreComments || _loadingMore) return;
    final ctx = _commentsLoaderKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final screenH = MediaQuery.of(context).size.height;
    const prefetch = 200.0;
    // The sentinel is (nearly) on-screen when its span overlaps the viewport,
    // grown by a prefetch margin so a page loads just before it is reached.
    final onScreen =
        top < screenH + prefetch && (top + box.size.height) > -prefetch;
    if (!onScreen) {
      // Scrolled away → re-arm so the NEXT time it appears exactly ONE page
      // loads. A plain level-trigger here would reload every frame it stays
      // visible → a burst of page loads.
      _loadArmed = true;
      return;
    }
    if (_loadArmed) {
      _loadArmed = false;
      _loadMoreComments();
    }
  }

  /// Called by the host immediately before it disposes the shared `header` /
  /// `composerRev` notifiers, so any late window-metric / focus / data callback
  /// arriving while this observer is briefly still registered stops writing to
  /// them. See [_hostDetached].
  void detachHostChannels() => _hostDetached = true;

  /// Whether it's safe to write to the host-owned `header` / `composerRev`.
  bool get _hostAlive => mounted && !_hostDetached;

  /// Nudges the sticky action bar (a subtree outside this body) to rebuild its
  /// floating composer — call after any state change the composer reflects.
  /// Guarded: `composerRev` is owned by the host and disposed when the sheet/
  /// route closes, so a late async caller must not touch it once detached.
  void _bumpComposer() {
    if (_hostAlive) widget.composerRev?.value++;
  }

  /// Adopts a fresh server copy of the issue. Every path that lands one goes
  /// through here so the watch roster can't be left behind on the one that
  /// forgets it — the cubit re-applies the caller's own committed subscription
  /// on top, so a payload that left the server *before* the last toggle (a
  /// title PATCH answered with a pre-watch roster, say) can't undo it.
  void _adoptIssue(Issue issue) {
    _issue = issue;
    _watch.sync(issue.watcherIds);
  }

  /// Publishes the latest issue to the host's top-bar `header` notifier, guarded
  /// against the host having disposed it (same lifetime caveat as [_bumpComposer]).
  void _publishHeader(Issue issue) {
    if (_hostAlive) widget.header?.value = issue;
  }

  /// Reveals the just-posted comment. In the newest-first feed it lands at the
  /// TOP of the thread, so scroll it into view. Scoped to the Comments tab (the
  /// "All" tab is a merged, mid-scroll feed where this wouldn't map). Uses an
  /// *animated* `ensureVisible` — it drives the scroll over later frames; a
  /// synchronous jump inside a post-frame callback would leave the sheet's
  /// SlideTransition wrapper `debugNeedsLayout` when the web mouse-tracker runs
  /// its post-frame hit-test, which asserts `!debugNeedsLayout` and froze the
  /// app. Runs after the next frame so the new row is laid out and keyed.
  void _revealNewestComment() {
    if (_activityFilter != _ActivityFilter.comments) return;
    if (_comments.isEmpty) return;
    // Newest-first → the new comment is at the top; oldest-first → at the bottom.
    final newest = _commentSort == CommentSort.newest
        ? _comments.first
        : _comments.last;
    _revealComment(newest.id, alignment: 0.15);
  }

  /// Animated scroll bringing [id]'s row into view. Animated (drives over later
  /// frames) so it never mutates layout inside the post-frame callback — a
  /// synchronous jump there trips the sheet's SlideTransition on web.
  void _revealComment(String id, {double alignment = 0.3}) {
    final controller = widget.sheetScroll;
    if (controller == null || !controller.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _commentKeys[id]?.currentContext;
      if (ctx == null || !controller.hasClients) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        alignment: alignment,
      );
    });
  }

  Future<void> _load() async {
    // Callers may await this after their own awaits (e.g. a sheet closing), so
    // the body could already be torn down — guard the first setState.
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // ONE aggregate round-trip for everything first paint needs, instead of
      // the old ~13-request fan-out (issue + 6-way batch + a serial tail of
      // sprints/hierarchy/canDelete/knowledge). On native (HTTP/1.1, no
      // multiplexing, WAN latency) that fan-out paid a TLS handshake per hop and
      // intermittently failed; collapsing it is the core issue-load speed-up.
      final detail = await _issueApi.issueDetail(
        widget.issueId,
        commentSize: _commentPageSize,
        commentSort: _commentSort.api,
      );
      // The sheet/route can close mid-load — the host then disposes `header` and
      // `composerRev`. Bail if we were unmounted during the await.
      if (!mounted) return;
      _adoptIssue(detail.issue);
      _comments = detail.comments.toList();
      _commentsTotal = detail.commentsTotal;
      _pinned = detail.pinnedComments;
      _workItems = detail.workItems;
      _project = detail.project;
      // The aggregate ships only the users this issue references; the full
      // directory (for pickers) is hydrated after first paint below.
      _setUsers(detail.users);
      _activity = detail.activity;
      _activityTotal = detail.activityTotal;
      _activityPage = 0;
      _sprints = detail.sprints;
      _hierarchy = detail.hierarchy;
      _canDelete = detail.canDelete;
      _projectIssues = const {};
      // PAINT NOW — the user sees the issue, comments, activity, hierarchy and
      // actions immediately. Everything below fills in without a spinner.
      _publishHeader(detail.issue);
      setState(() => _loading = false);
      // Reveal the host's floating composer now that the issue is loaded (the
      // route overlay reads `hasIssue`, and its subtree is outside this body).
      _bumpComposer();
      // Non-critical extras load in the background, each best-effort, so a slow
      // or failed secondary fetch never blocks or blanks the sheet.
      unawaited(_hydrateSecondary(detail.issue));
      // Deep link into a specific comment → scroll to it and flash it.
      final target = widget.targetCommentId;
      if (target != null && target.isNotEmpty) {
        _jumpToComment(target);
      }
    } on ApiFailure catch (failure) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = failure.message;
        });
      }
    } catch (_) {
      // Anything other than an ApiFailure (e.g. a payload-shape TypeError) must
      // still leave a visible error state, not an eternal HiveLoader.
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'errors.unexpected';
        });
      }
    }
  }

  /// Non-critical data loaded AFTER first paint so it never blocks the sheet:
  /// the full user directory (the aggregate ships only referenced users, but the
  /// pickers want everyone), `{{issue:KEY}}` chip resolution, and the KB
  /// "documented in" backlinks + `{{doc:…}}` mention corpus. Each step is
  /// best-effort — a slow or failed fetch just leaves that section empty.
  Future<void> _hydrateSecondary(Issue issue) async {
    try {
      final all = await _userApi.users();
      if (mounted && all.isNotEmpty) setState(() => _setUsers(all));
    } catch (_) {
      // Keep the referenced-user subset from the aggregate.
    }
    // Resolve `{{issue:…}}` chip previews for the description + loaded comments.
    try {
      await _syncReferencedIssues();
    } catch (_) {
      // Chips fall back to plain text.
    }
    try {
      // init() powers the composer's {{doc:…}} mention menu; the issue↔article
      // backlinks come from the dedicated server endpoint (ACL-correct,
      // O(matches)).
      await _knowledge.init();
      final docs = await _knowledge.articlesReferencingIssue(issue.readableId);
      if (mounted) setState(() => _documentedIn = docs);
    } catch (_) {
      if (mounted) setState(() => _documentedIn = const []);
    }
  }

  /// Light refresh after logging work: refetch just the work items (and the
  /// issue for its aggregated time totals) instead of a full [_load], so the
  /// comment window, loaded pages and scroll position are preserved.
  Future<void> _reloadWorkItems() async {
    try {
      final results = await Future.wait([
        _issueApi.workItems(widget.issueId),
        _issueApi.issue(widget.issueId),
      ]);
      if (!mounted) return;
      setState(() {
        _workItems = results[0] as List<WorkItem>;
        _adoptIssue(results[1] as Issue);
      });
    } catch (_) {
      // Non-critical; totals catch up on the next full load.
    }
  }

  Future<void> _patch(Map<String, dynamic> patch) async {
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await _issueApi.updateIssue(widget.issueId, patch);
      if (!mounted) return;
      // Commit now rather than riding along on the `finally` rebuild: the
      // activity refetch and the hierarchy reload below are two more round
      // trips, and until this lands the sheet still shows the pre-patch issue.
      setState(() => _adoptIssue(updated));
      _publishHeader(updated);
      _notifyChanged();
      // Refresh the change history so the new entry shows immediately (reset to
      // the newest page).
      try {
        final p = await _issueApi.issueActivity(widget.issueId);
        _activity = p.items;
        _activityTotal = p.total;
        _activityPage = 0;
      } catch (_) {
        // Non-critical; the next full load reflects server truth.
      }
      // A re-parent changes the breadcrumb ancestors — keep them in sync.
      await _reloadHierarchy();
    } on ApiFailure catch (failure) {
      _toast(failure.message);
    } catch (_) {
      _toast('errors.unexpected');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Tells the opener to refresh *and* broadcasts app-wide. The opener callback
  /// alone only reaches whoever showed this sheet; a change made here is just as
  /// visible on surfaces that hold their own copy of the issue — a board card's
  /// sub-task expander, the Scrum sprint containers, the dashboard — and those
  /// hold no handle to this sheet. Always use this instead of calling
  /// [IssueDetailBody.onChanged] directly.
  void _notifyChanged() {
    widget.onChanged?.call();
    IssueEvents.instance.notifyChanged();
  }

  /// Pulls the fresh ancestors + children so the breadcrumb and the child /
  /// sub-task panels reflect a re-parent, an inline add, or a state toggle.
  Future<void> _reloadHierarchy() async {
    try {
      final h = await _issueApi.issueHierarchy(widget.issueId);
      if (mounted) setState(() => _hierarchy = h);
    } catch (_) {
      // Non-critical; the next full load reflects server truth.
    }
  }

  /// A child was added, removed, re-parented or ticked off: refresh this sheet's
  /// own hierarchy panel *and* tell the rest of the app, since the parent's
  /// sub-task counters live on every surface that lists it (board cards, issue
  /// rows, backlog rows) and only the server can recompute them.
  Future<void> _hierarchyChanged() async {
    await _reloadHierarchy();
    _notifyChanged();
  }

  // ── git integration ───────────────────────────────────────────────────────
  bool get _gitConnected => _project?.git != null;

  /// Reflects a server-applied transition triggered by a PR/MR action (merge /
  /// ready) in the Development summary.
  void _applyGitIssue(Issue updated) {
    if (!mounted) return;
    setState(() => _adoptIssue(updated));
    _publishHeader(updated);
    _notifyChanged();
    _refreshActivity();
  }

  /// Reflects a branch-template change made from the Deployment panel.
  void _applyGitProject(Project updated) {
    if (mounted) setState(() => _project = updated);
  }

  Future<void> _refreshActivity() async {
    try {
      final page = await _issueApi.issueActivity(widget.issueId);
      if (mounted) {
        setState(() {
          _activity = page.items;
          _activityTotal = page.total;
          _activityPage = 0;
        });
      }
    } catch (_) {
      // Non-critical; the next full load reflects server truth.
    }
  }

  void _openProjectSettings(String projectId) {
    final router = GoRouter.of(context);
    Navigator.of(context).maybePop();
    router.push('/projects/$projectId/settings');
  }

  Widget _developmentBlock(Issue issue) {
    final project = _project;
    if (project == null || project.git == null) return const SizedBox.shrink();
    return DevelopmentSummary(
      issue: issue,
      project: project,
      names: _names,
      avatars: _avatars,
      onIssueChanged: _applyGitIssue,
    );
  }

  Widget _deploymentPanel(Issue issue) {
    final project = _project;
    if (project == null) return const SizedBox.shrink();
    return DeploymentPanel(
      issue: issue,
      project: project,
      onConnectInSettings: () => _openProjectSettings(project.id),
      onProjectChanged: _applyGitProject,
    );
  }

  Future<void> _submitComment() async {
    final text = _comment.text.trim();
    if (text.isEmpty || _sendingComment) return;
    // Editing an existing comment inline → save instead of posting a new one.
    final editing = _editingComment;
    if (editing != null) {
      final ok = await _editComment(editing, text);
      if (ok && mounted) {
        setState(() {
          _editingComment = null;
          _comment.clear();
        });
        _bumpComposer();
      }
      return;
    }
    _sendingComment = true;
    try {
      final replyTarget = _replyingTo;
      final created = await _commentApi.addComment(
        widget.issueId,
        text,
        replyToId: replyTarget?.id,
      );
      _comment.clear();
      if (!mounted) return;
      setState(() => _replyingTo = null);
      _bumpComposer();
      if (created.isReply) {
        _onReplyPosted(created);
      } else {
        await _refreshTopLevelAfterPost();
      }
    } on ApiFailure catch (failure) {
      _toast(failure.message);
    } catch (_) {
      _toast('errors.unexpected');
    } finally {
      _sendingComment = false;
    }
  }

  /// After a top-level comment: reload the newest window so it appears (top for
  /// newest-first, bottom for oldest-first) and reveal it.
  Future<void> _refreshTopLevelAfterPost() async {
    final p = await _commentApi.comments(
      widget.issueId,
      size: math.max(_comments.length + 1, _commentPageSize),
      sort: _commentSort.api,
    );
    if (!mounted) return;
    setState(() {
      _comments = p.items.toList();
      _commentsTotal = p.total;
    });
    _revealNewestComment();
    unawaited(_syncReferencedIssues());
  }

  /// After a reply: bump the root's reply count and splice the reply into its
  /// (now expanded) thread. A fully-loaded thread appends at the bottom (newest
  /// last); otherwise the thread is fetched fresh.
  void _onReplyPosted(IssueComment reply) {
    final rootId = reply.replyToId;
    if (rootId == null) return;
    setState(() {
      _comments = [
        for (final c in _comments)
          c.id == rootId ? c.copyWith(replyCount: c.replyCount + 1) : c,
      ];
      _pinned = [
        for (final c in _pinned)
          c.id == rootId ? c.copyWith(replyCount: c.replyCount + 1) : c,
      ];
    });
    final t = _threadOf(rootId);
    if (t.expanded && !t.hasMore) {
      final replies = [
        for (final r in t.replies)
          if (r.id != reply.id) r,
        reply,
      ];
      setState(() {
        _replyThreads[rootId] = t.copyWith(
          replies: replies,
          total: replies.length,
          loading: false,
        );
      });
      _revealComment(reply.id);
    } else {
      setState(
        () => _replyThreads[rootId] = t.copyWith(expanded: true, loading: true),
      );
      _fetchReplies(rootId, page: 0, replace: true).then((_) {
        if (mounted) _revealComment(reply.id);
      });
    }
  }

  /// Loads [comment] into the composer for inline editing (no separate dialog).
  void _promptEditComment(IssueComment comment) {
    setState(() {
      _editingComment = comment;
      _replyingTo = null; // edit and reply are mutually exclusive
      _comment.text = comment.text;
      _comment.selection = TextSelection.collapsed(
        offset: _comment.text.length,
      );
    });
    _bumpComposer();
    _commentFocus.requestFocus();
  }

  /// Abandons an in-progress inline edit and clears the composer.
  void _cancelEditComment() {
    setState(() {
      _editingComment = null;
      _comment.clear();
    });
    _bumpComposer();
  }

  /// Saves an inline edit of the user's own [comment]. Returns true on success
  /// so the tile can close its editor; a no-op (unchanged/empty) also succeeds.
  Future<bool> _editComment(IssueComment comment, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed == comment.text) return true;
    try {
      final updated = await _commentApi.editComment(
        widget.issueId,
        comment.id,
        trimmed,
      );
      if (mounted) {
        setState(() => _replaceComment(updated));
      }
      return true;
    } on ApiFailure catch (failure) {
      _toast(failure.message);
      return false;
    } catch (_) {
      _toast('errors.unexpected');
      return false;
    }
  }

  Future<void> _deleteComment(IssueComment comment) async {
    final confirmed = await showGlassModal<bool>(
      context,
      width: 420,
      builder: (_) => const _DeleteCommentConfirm(),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _commentApi.deleteComment(widget.issueId, comment.id);
      if (mounted) {
        setState(() => _removeComment(comment));
      }
    } on ApiFailure catch (failure) {
      _toast(failure.message);
    } catch (_) {
      _toast('errors.unexpected');
    }
  }

  // ── comment reactions / pin / reply / copy / select (focused menu) ──────────

  /// Splices [updated] in wherever it lives (feed, pinned, or a reply thread),
  /// keeping the existing `replyCount`. React/edit/pin responses don't carry it
  /// (it's a read-time transient → would deserialize as 0 and wipe the "N
  /// replies" count); those mutations never change the reply count anyway.
  void _replaceComment(IssueComment updated) => _mutateAll(
    updated.id,
    (old) => updated.copyWith(replyCount: old.replyCount),
  );

  /// Applies [fn] to the comment with [id] wherever it lives — the top-level
  /// feed, the pinned set, or any loaded reply thread.
  void _mutateAll(String id, IssueComment Function(IssueComment) fn) {
    _comments = [for (final c in _comments) c.id == id ? fn(c) : c];
    _pinned = [for (final c in _pinned) c.id == id ? fn(c) : c];
    for (final key in _replyThreads.keys.toList()) {
      final t = _replyThreads[key]!;
      if (t.replies.any((r) => r.id == id)) {
        _replyThreads[key] = t.copyWith(
          replies: [for (final r in t.replies) r.id == id ? fn(r) : r],
        );
      }
    }
  }

  /// Removes [comment] wherever it lives, keeping counts consistent: a reply is
  /// pulled from its root's thread (decrementing that root's replyCount); a root
  /// drops from the feed together with its whole thread.
  void _removeComment(IssueComment comment) {
    final id = comment.id;
    if (comment.isReply) {
      final rootId = comment.replyToId!;
      final t = _threadOf(rootId);
      _replyThreads[rootId] = t.copyWith(
        replies: [
          for (final r in t.replies)
            if (r.id != id) r,
        ],
        total: t.total > 0 ? t.total - 1 : 0,
      );
      IssueComment dec(IssueComment c) =>
          c.copyWith(replyCount: (c.replyCount - 1).clamp(0, 1 << 30));
      _comments = [for (final c in _comments) c.id == rootId ? dec(c) : c];
      _pinned = [for (final c in _pinned) c.id == rootId ? dec(c) : c];
      return;
    }
    _comments = [
      for (final c in _comments)
        if (c.id != id) c,
    ];
    _pinned = [
      for (final c in _pinned)
        if (c.id != id) c,
    ];
    _replyThreads.remove(id);
    if (_commentsTotal > 0) _commentsTotal--;
  }

  /// Finds a comment by id across the feed, pinned set and loaded reply threads.
  IssueComment? _findComment(String id) {
    for (final c in _comments) {
      if (c.id == id) return c;
    }
    for (final c in _pinned) {
      if (c.id == id) return c;
    }
    for (final t in _replyThreads.values) {
      for (final r in t.replies) {
        if (r.id == id) return r;
      }
    }
    return null;
  }

  /// Toggles the caller's emoji reaction (optimistic, WhatsApp one-per-user).
  Future<void> _reactToComment(IssueComment comment, String emoji) async {
    final meId = context.read<AuthBloc>().state.user?.id;
    if (meId == null) return;
    IssueComment toggle(IssueComment c) {
      if (c.id != comment.id) return c;
      final mine = c.myReaction(meId);
      final list = [
        for (final r in c.reactions)
          if (r.userId != meId) r,
      ];
      if (mine != emoji) list.add(CommentReaction(emoji: emoji, userId: meId));
      return c.copyWith(reactions: list);
    }

    setState(() => _mutateAll(comment.id, toggle));
    try {
      final updated = await _commentApi.reactToComment(
        widget.issueId,
        comment.id,
        emoji,
      );
      if (mounted) setState(() => _replaceComment(updated));
    } on ApiFailure catch (failure) {
      _toast(failure.message);
      _scheduleCommentResync();
    } catch (_) {
      // A non-ApiFailure error (payload shape, stale-socket) would otherwise
      // escape as a global 'errors.unexpected' and leave the optimistic
      // reaction stuck — surface it and let the resync reconcile.
      _toast('errors.unexpected');
      _scheduleCommentResync();
    }
  }

  /// Pins/unpins a comment (any project member); refreshes pin ordering.
  Future<void> _togglePin(IssueComment comment) async {
    try {
      final updated = await _commentApi.pinComment(
        widget.issueId,
        comment.id,
        !comment.pinned,
      );
      final pinned = await _commentApi.pinnedComments(widget.issueId);
      if (!mounted) return;
      setState(() {
        _pinned = pinned;
        _replaceComment(updated);
      });
    } on ApiFailure catch (failure) {
      _toast(failure.message);
    } catch (_) {
      _toast('errors.unexpected');
    }
  }

  /// Enters reply mode: the composer shows who you're replying to. Replying to a
  /// reply (Instagram-style) pre-fills an @mention of its author, then the user
  /// types; a reply to a root starts empty. The backend normalises every reply
  /// to the thread root, so the thread stays flat.
  void _startReply(IssueComment comment) {
    setState(() {
      _replyingTo = comment;
      _editingComment = null;
      if (comment.isReply) {
        _comment.text = '{{user:${comment.authorId}}} ';
        _comment.selection = TextSelection.collapsed(
          offset: _comment.text.length,
        );
      } else {
        _comment.clear();
      }
    });
    _bumpComposer();
    _commentFocus.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyingTo = null);
    _bumpComposer();
  }

  /// Copies a comment's text (or its inline image as real image data).
  Future<void> _copyComment(IssueComment comment) async {
    final kind = await copyComment(_mediaApi, comment);
    if (!mounted) return;
    _toast(
      kind == CommentCopyKind.image
          ? context.t('comments.imageCopied')
          : context.t('comments.copied'),
      kind: GlassToastKind.success,
    );
  }

  /// Copies a deep link straight to this comment (opens the issue + scrolls).
  Future<void> _copyCommentLink(IssueComment comment) async {
    final issue = _issue;
    if (issue == null) return;
    final link =
        '${issueWebLink(_issueApi.apiBaseUrl, issue.linkId)}?comment=${comment.id}';
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    _toast(context.t('comments.linkCopied'), kind: GlassToastKind.success);
  }

  void _enterSelection(IssueComment comment) {
    setState(() {
      _selectionMode = true;
      _selectedIds
        ..clear()
        ..add(comment.id);
    });
    _bumpComposer();
  }

  void _toggleSelected(IssueComment comment) {
    setState(() {
      if (!_selectedIds.remove(comment.id)) _selectedIds.add(comment.id);
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
    _bumpComposer();
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
    _bumpComposer();
  }

  /// Batch-deletes the selected own comments after a single confirmation.
  Future<void> _deleteSelected() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    final confirmed = await showGlassModal<bool>(
      context,
      width: 420,
      builder: (_) => _DeleteCommentConfirm(count: ids.length),
    );
    if (confirmed != true) return;
    // Track which deletes actually succeeded so we don't wipe a comment from the
    // UI that the server still has — that would make it "come back" on the next
    // SSE resync with no explanation.
    final deleted = <String>[];
    var failed = false;
    for (final id in ids) {
      try {
        await _commentApi.deleteComment(widget.issueId, id);
        deleted.add(id);
      } catch (_) {
        failed = true;
      }
    }
    if (!mounted) return;
    final remaining = ids.where((id) => !deleted.contains(id)).toSet();
    setState(() {
      for (final id in deleted) {
        final c = _findComment(id);
        if (c != null) _removeComment(c);
      }
      _selectedIds
        ..clear()
        ..addAll(remaining);
      // Stay in selection mode if some failed, so the user can retry them.
      _selectionMode = remaining.isNotEmpty;
    });
    if (failed) _toast('comments.deleteFailed');
    _bumpComposer();
  }

  /// Scrolls to [commentId] (loading older pages until found) and flashes it —
  /// used by a reply-quote tap and by a deep link into a specific comment.
  Future<void> _jumpToComment(String commentId) async {
    bool found() =>
        _comments.any((c) => c.id == commentId) ||
        _pinned.any((c) => c.id == commentId) ||
        _replyThreads.values.any(
          (t) => t.replies.any((r) => r.id == commentId),
        );
    var guard = 0;
    while (!found() && _hasMoreComments && guard++ < 20) {
      await _loadMoreComments();
    }
    if (!mounted) return;
    // Still not among roots/pinned → the target is likely a reply living in a
    // lazily-loaded, collapsed thread. Expand and fully page each root that
    // owns replies until the reply surfaces (bounded).
    if (!found()) {
      await _resolveReplyTarget(commentId, found);
      if (!mounted) return;
    }
    if (!found()) {
      // Genuinely unreachable (deleted, or in a thread we couldn't resolve) —
      // tell the user instead of silently doing nothing.
      _toast('comments.jumpNotFound');
      return;
    }
    if (_activityFilter == _ActivityFilter.history) {
      setState(() => _activityFilter = _ActivityFilter.comments);
    }
    _commentKeys.putIfAbsent(commentId, () => GlobalKey());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Two things break a naive single ensureVisible here (the deep-link
      // "jump to comment" bug):
      //  1. The feed is (re)built the frame AFTER `_loading` flips false and the
      //     comments filter is applied, so the target row's GlobalKey has no
      //     context on this first post-frame — wait for it to lay out.
      //  2. Right after the first scroll the feed keeps GROWING (reply-count
      //     previews resolve, an SSE resync reloads the window), which shifts the
      //     target out of view while the offset stays put. So re-assert the scroll
      //     a few times until it stops moving. ensureVisible is a no-op once the
      //     row is already visible, so the extra passes are cheap and smooth.
      BuildContext? ctx = _commentKeys[commentId]?.currentContext;
      for (var i = 0; ctx == null && i < 60; i++) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        ctx = _commentKeys[commentId]?.currentContext;
      }
      if (ctx == null || !ctx.mounted) return;
      double lastMax = -1;
      for (var pass = 0; pass < 10 && mounted; pass++) {
        final row = _commentKeys[commentId]?.currentContext;
        if (row != null && row.mounted) {
          await Scrollable.ensureVisible(
            row,
            duration: Duration(milliseconds: pass == 0 ? 420 : 160),
            curve: Curves.easeOutCubic,
            alignment: 0.3,
          );
        }
        if (!mounted) return;
        // Stop once the content height has settled for a beat.
        final sc = widget.sheetScroll;
        final max = sc?.hasClients == true
            ? sc!.position.maxScrollExtent
            : -1.0;
        if (pass > 0 && max == lastMax) break;
        lastMax = max;
        await Future.delayed(const Duration(milliseconds: 220));
      }
      if (!mounted) return;
      setState(() => _highlightedCommentId = commentId);
      _highlightTimer?.cancel();
      _highlightTimer = Timer(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() => _highlightedCommentId = null);
      });
    });
  }

  /// Surfaces a reply [commentId] hidden in a collapsed/lazy thread: walks the
  /// loaded roots that own replies, expands each and pages its thread until the
  /// reply appears or the thread is exhausted. Bounded so it can't spin.
  Future<void> _resolveReplyTarget(
    String commentId,
    bool Function() found,
  ) async {
    final roots = [
      for (final c in _comments)
        if (c.isRoot && c.hasReplies) c,
    ];
    for (final root in roots) {
      if (found()) return;
      // Load the first page (and expand) if the thread is untouched.
      if (_threadOf(root.id).replies.isEmpty) {
        await _fetchReplies(root.id, page: 0, replace: true);
      } else if (!_threadOf(root.id).expanded) {
        setState(
          () => _replyThreads[root.id] = _threadOf(
            root.id,
          ).copyWith(expanded: true),
        );
      }
      if (!mounted) return;
      // Page the rest of this thread until the reply shows or it runs out.
      var guard = 0;
      while (!found() && _threadOf(root.id).hasMore && guard++ < 50) {
        await _loadMoreReplies(root);
        if (!mounted) return;
      }
      if (found()) return;
    }
  }

  bool get _hasMoreComments => _comments.length < _commentsTotal;
  bool get _hasMoreActivity => _activity.length < _activityTotal;

  /// Loads the next (older) page of comments and appends it BELOW the thread,
  /// de-duplicating in case a row shifted across the page boundary.
  Future<void> _loadMoreComments() async {
    if (_loadingMore || !_hasMoreComments) return;
    setState(() => _loadingMore = true);
    try {
      // Derive the page from how many are loaded (survives an SSE resync that
      // reset the window), so each pull fetches the next older batch.
      final next = _comments.length ~/ _commentPageSize;
      final p = await _commentApi.comments(
        widget.issueId,
        page: next,
        size: _commentPageSize,
        sort: _commentSort.api,
      );
      if (!mounted) return;
      final existing = {for (final c in _comments) c.id};
      // Backend pages are newest-first; keep that order and append so the feed
      // stays a continuous newest→oldest list.
      final older = [
        for (final c in p.items)
          if (!existing.contains(c.id)) c,
      ];
      // Append the older page at the BOTTOM (the sentinel sits below the feed,
      // so the user scrolls DOWN toward it) and leave the scroll offset
      // UNTOUCHED. New rows land below the current viewport, so nothing above it
      // moves — no scroll anchoring is needed. This deliberately avoids any
      // post-frame `jumpTo`: mutating layout in a post-frame callback left the
      // sheet's translation wrapper (Wolt's SlideTransition) `debugNeedsLayout`
      // when Flutter's mouse-tracker ran its own post-frame hit-test, which
      // asserts `!debugNeedsLayout` on web → froze the app.
      setState(() {
        _comments = [..._comments, ...older];
        _commentsTotal = p.total;
        _loadingMore = false;
      });
      unawaited(_syncReferencedIssues());
    } catch (_) {
      // Keep what we have; the user can retry.
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Loads the next (older) page of change history and appends it below.
  Future<void> _loadMoreActivity() async {
    if (_loadingMore || !_hasMoreActivity) return;
    setState(() => _loadingMore = true);
    try {
      final next = _activityPage + 1;
      final p = await _issueApi.issueActivity(widget.issueId, page: next);
      if (!mounted) return;
      final existing = {for (final a in _activity) a.id};
      final older = [
        for (final a in p.items)
          if (!existing.contains(a.id)) a,
      ];
      setState(() {
        _activity = [..._activity, ...older];
        _activityTotal = p.total;
        _activityPage = next;
      });
    } catch (_) {
      // Keep what we have; the user can retry.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _toast(String message, {GlassToastKind kind = GlassToastKind.error}) {
    if (!mounted) return;
    // Resolve through i18n: a backend `ApiFailure.message` is already-localized
    // text (returned unchanged by `t`), while a frontend fallback key like
    // `errors.unexpected`/`errors.connection` gets localized here instead of
    // leaking the raw key into the toast.
    showGlassToast(context, context.t(message), kind: kind);
  }

  // ── inline editing + actions (driven by the top-bar / double-tap) ─────────

  /// Public entry points so the top-bar actions can drive the body.
  void beginTitleEdit() {
    final issue = _issue;
    if (issue == null) return;
    _titleCtrl.text = issue.title;
    setState(() => _editingTitle = true);
  }

  void _beginDescEdit() {
    final issue = _issue;
    if (issue == null) return;
    // Seed from the legacy markdown when the backfill left no document —
    // otherwise the editor opens blank and the first save writes that blankness
    // over a description that was still there.
    _descCtrl.load(documentOrLegacy(issue.descriptionDoc, issue.description));
    setState(() => _editingDesc = true);
  }

  Future<void> _saveTitle() async {
    final value = _titleCtrl.text.trim();
    setState(() => _editingTitle = false);
    if (value.isEmpty || value == _issue!.title) return;
    await _patch({'title': value});
  }

  Future<void> _saveDesc() async {
    final value = _descCtrl.doc;
    setState(() => _editingDesc = false);
    // Nothing changed: comparing documents rather than a dirty flag means an
    // edit that was typed and undone does not write.
    if (!_descCtrl.isDirty) return;
    _descCtrl.markSaved();
    await _patch({'descriptionDoc': value});
    // The edited description may reference new issues — resolve their chips.
    await _syncReferencedIssues();
  }

  /// The route back button (compact full-screen has no shell nav to fall back
  /// on): pop if there's a page underneath, otherwise — e.g. a cold-start deep
  /// link straight into the issue — go home so the user is never stranded.
  void _closeRoute() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      GoRouter.of(context).go('/dashboard');
    }
  }

  /// Full-page → modal: re-open the issue as a modal sheet and drop the route
  /// underneath it. The sheet is shown first (while this context is still
  /// mounted) so its provider reads succeed, then the route is popped away.
  void _minimizeToModal() {
    final navigator = Navigator.of(context);
    showIssueDetailSheet(
      context,
      issueId: widget.issueId,
      onChanged: widget.onChanged,
    );
    navigator.maybePop();
  }

  Future<void> confirmDeleteIssue() async {
    final issue = _issue;
    if (issue != null) await _confirmDelete(issue);
  }

  /// Opens the clone dialog and, on success, lands on the copy.
  ///
  /// Landing there is the point: a clone the user has to go and find on the
  /// board is a clone they will assume did not happen. Which way we get there
  /// follows the host — the sheet is replaced by the copy's sheet, the full page
  /// pushes the copy on top so back still returns to the original.
  Future<void> cloneIssue() async {
    final issue = _issue;
    if (issue == null) return;
    final me = context.read<AuthBloc>().state.user;
    // Taken before the dialog: after it, this context has been through an async
    // gap, and the navigator's own context is the one thing that outlives the
    // sheet we are about to close.
    final navigator = Navigator.of(context, rootNavigator: true);
    final host = navigator.context;
    final copy = await showIssueCloneDialog(
      context,
      issue: issue,
      users: _users,
      repository: _issueApi,
      meId: me?.id,
      multiAssignee:
          context.read<AppConfigBloc>().state.meta?.multiAssignee ?? false,
    );
    if (copy == null || !mounted) return;
    // A new issue in the project: every board, backlog and list showing it is
    // now stale.
    _notifyChanged();
    if (widget.header != null) {
      // Close this sheet, then open the copy's — in that order, and without an
      // await between them. Both live on the root navigator, so showing first
      // and popping after pops the sheet just opened and leaves the user
      // staring at the original. Popping first deactivates this context, which
      // is why the new sheet is opened from the navigator's own: it sits below
      // the app's providers and outlives any route above it.
      if (navigator.canPop()) navigator.pop();
      if (host.mounted) {
        showIssueDetailSheet(
          host,
          issueId: copy.id,
          onChanged: widget.onChanged,
        );
      }
      return;
    }
    GoRouter.of(context).push('/issues/${copy.id}');
  }

  /// Opens the move-to-another-project wizard for this issue and reloads on
  /// success — the issue keeps its id but gets a new readable id, project and
  /// status, so every panel on this screen has to be re-read.
  Future<void> moveIssue() async {
    final issue = _issue;
    if (issue == null || issue.archived) return;
    final moved = await showIssueMoveWizard(
      context,
      issueIds: [issue.id],
      currentProjectId: issue.projectId,
    );
    if (moved != true || !mounted) return;
    _notifyChanged();
    await _load();
  }

  // ── build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading && _issue == null) {
      return const SizedBox(height: 260, child: Center(child: HiveLoader()));
    }
    if (_error != null && _issue == null) {
      return SizedBox(
        height: 240,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.t(_error!),
                style: TextStyle(color: AppColors.inkSoft),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _load,
                child: Text(context.t('common.retry')),
              ),
            ],
          ),
        ),
      );
    }

    final issue = _issue!;
    // The wolt sheet (header != null) owns the top bar; the route renders its
    // own. Both are intrinsically sized — the route wraps this in a scroll view,
    // the sheet scrolls its own content.
    final documented = _documentedInSection();
    return SmartLinkScope(
      resolver: _buildResolver(issue),
      // Tap anywhere on the body (feed bubbles, empty gaps between them and the
      // docked composer) to drop focus and dismiss the keyboard — there's no
      // other way out on a full-screen chat. The composer lives in a separate
      // subtree (sticky action bar / route overlay) so tapping it keeps focus,
      // and interactive children (buttons, links, menus) still win their taps.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // On the COMPACT full-screen route the top bar is not inline — it's
            // pinned as a scroll-reactive glass bar by IssueDetailScreen (see
            // [buildRouteTopBar]) so back/minimize stay reachable when the thread
            // gets long. The sheet uses Wolt's own nav bar. The WIDE route keeps
            // an inline bar (no overlap with the desktop shell's own top bar).
            if (widget.header == null && !context.isCompact)
              _RouteTopBar(
                issue: issue,
                busy: _busy,
                stateColor: _projStateColor(_project, issue.state),
                link: issueWebLink(_issueApi.apiBaseUrl, issue.linkId),
                onMinimize: widget.canMinimize ? _minimizeToModal : null,
                onDelete: () => _confirmDelete(issue),
                onClone: () => cloneIssue(),
                onMove: () => moveIssue(),
                onClose: _closeRoute,
                onReply: _replyEmailAction(issue),
                watch: watchMenu,
                canDelete: _canDelete,
              ),
            Padding(
              // Extra bottom room when the composer floats, so the last comment
              // isn't hidden behind the docked input. The sheet no longer
              // resizes for the keyboard, so its height is added here too —
              // otherwise the newest comments can't be scrolled above it.
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                (composerFloats(context) ? 128 : 24) +
                    MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: LayoutBuilder(
                builder: (context, c) {
                  final hierarchy = _hierarchyCard(issue);
                  final left = <Widget>[
                    _contentCard(issue),
                    if (hierarchy != null) ...[
                      const SizedBox(height: 14),
                      hierarchy,
                    ],
                    // The Development block owns its own leading gap and hides
                    // entirely when no work is linked (Jira-style).
                    if (_gitConnected) _developmentBlock(issue),
                    const SizedBox(height: 14),
                    _linksSection(issue),
                    const SizedBox(height: 14),
                    _attachmentsSection(issue),
                    if (documented != null) ...[
                      const SizedBox(height: 14),
                      documented,
                    ],
                    const SizedBox(height: 14),
                    _activityCard(),
                  ];
                  final right = <Widget>[
                    _detailsCard(issue),
                    // Deployment sits between Details and Timeline.
                    if (_project != null) ...[
                      const SizedBox(height: 14),
                      _deploymentPanel(issue),
                    ],
                    const SizedBox(height: 14),
                    _timeCard(issue),
                    const SizedBox(height: 14),
                    _issueMeta(issue),
                  ];
                  if (c.maxWidth >= 680) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: left,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: right,
                          ),
                        ),
                      ],
                    );
                  }
                  // Stacked (phone): content, details, time, activity.
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _contentCard(issue),
                      if (hierarchy != null) ...[
                        const SizedBox(height: 14),
                        hierarchy,
                      ],
                      if (_gitConnected) _developmentBlock(issue),
                      const SizedBox(height: 14),
                      _linksSection(issue),
                      const SizedBox(height: 14),
                      _attachmentsSection(issue),
                      if (documented != null) ...[
                        const SizedBox(height: 14),
                        documented,
                      ],
                      const SizedBox(height: 14),
                      _detailsCard(issue),
                      // Deployment sits between Details and Timeline.
                      if (_project != null) ...[
                        const SizedBox(height: 14),
                        _deploymentPanel(issue),
                      ],
                      const SizedBox(height: 14),
                      _timeCard(issue),
                      const SizedBox(height: 14),
                      _issueMeta(issue),
                      const SizedBox(height: 14),
                      _activityCard(),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── smart-link wiring ────────────────────────────────────────────────────

  /// Resolves the full issues the current description and comments link to that
  /// aren't already loaded, so their chips + hover cards render richly —
  /// fetching only the referenced keys, never the whole project. Pass [commit]
  /// false during the initial load (the caller's own `setState` will render the
  /// result).
  ///
  /// The references are read out of each stored document rather than pattern
  /// matched out of text: a link is a node now, and the plain text beside it
  /// deliberately no longer contains the token.
  Future<void> _syncReferencedIssues({bool commit = true}) async {
    final keys = <String>{};
    void scan(String? doc) {
      if (doc == null || doc.isEmpty) return;
      keys.addAll(smartLinksIn(doc, SmartLinkKind.issue));
    }

    scan(_issue?.descriptionDoc);
    for (final c in _comments) {
      scan(c.textDoc);
    }
    for (final c in _pinned) {
      scan(c.textDoc);
    }
    for (final t in _replyThreads.values) {
      for (final r in t.replies) {
        scan(r.textDoc);
      }
    }
    keys.remove(_issue?.readableId);
    final missing = keys.where((k) => !_projectIssues.containsKey(k)).toList();
    if (missing.isEmpty) return;
    try {
      final resolved = await _issueApi.resolveIssues(missing);
      if (!mounted || resolved.isEmpty) return;
      final merged = {
        ..._projectIssues,
        // Index by every id the issue ever carried: a chip written before a
        // cross-project move still says "HIN-10" while the issue now reads
        // "MOB-10", and both must land on the same issue.
        for (final i in resolved)
          for (final key in i.allReadableIds) key: i,
      };
      if (commit) {
        setState(() => _projectIssues = merged);
      } else {
        _projectIssues = merged;
      }
    } catch (_) {
      // Unresolved keys render as a plain token chip; non-fatal.
    }
  }

  /// Resolver for the chips/`@`-menu: issue chips resolve against the referenced
  /// issues, the `@`-menu type-ahead hits the backend, people come from the
  /// loaded directory and articles from the shared KB seed. Rebuilt per frame
  /// (cheap) so it always reflects the freshly-resolved issues / users.
  IssueLinkResolver _buildResolver(Issue issue) => IssueLinkResolver(
    issuesByReadable: {issue.readableId: issue, ..._projectIssues},
    users: _users,
    knowledgeRepo: _knowledge,
    stateColorFor: (s) =>
        _projStateColor(_project, s) ?? AppColors.stateColor(s),
    onOpenIssue: _openLinkedIssue,
    onOpenDoc: _openArticle,
    searchIssues: (q) =>
        _issueApi.mentionSearch(projectId: issue.projectId, query: q),
  );

  /// Opens the real issue for a readable id (e.g. `HIV-208`): tries the loaded
  /// project issues first, then a backend search; toasts if there is no match.
  Future<void> _openLinkedIssue(String readableId) async {
    if (readableId == _issue?.readableId) return; // already open
    var match = _projectIssues[readableId];
    if (match == null) {
      try {
        final res = await _issueApi.issues(query: readableId, size: 20);
        match = res.issues.where((i) => i.readableId == readableId).firstOrNull;
      } on ApiFailure catch (failure) {
        _toast(failure.message);
        return;
      }
    }
    if (!mounted) return;
    if (match == null) {
      _toast(context.t('issues.linkedNotFound', variables: {'id': readableId}));
      return;
    }
    await showIssueDetailSheet(context, issueId: match.id);
    // The nested issue may have been re-parented, edited or deleted (e.g. a
    // sub-task removed from here) — refresh so the breadcrumb and the child /
    // sub-task panel reflect it instead of listing a stale row.
    if (mounted) await _reloadHierarchy();
  }

  /// Opens a KB article (doc smart-link) on the `/knowledge/:id` route. When the
  /// issue is shown as a modal sheet, close it first so the article isn't buried.
  void _openArticle(String articleId) {
    final router = GoRouter.of(context);
    if (widget.header != null) {
      Navigator.of(context, rootNavigator: true).maybePop();
    }
    router.push('/knowledge/$articleId');
  }

  /// "Documented in": KB articles that reference this issue, or null when none.
  Widget? _documentedInSection() {
    if (_documentedIn.isEmpty) return null;
    return _DocumentedIn(
      articles: _documentedIn,
      knowledge: _knowledge,
      onOpen: _openArticle,
    );
  }

  Widget _contentCard(Issue issue) {
    const titleStyle = TextStyle(
      fontFamily: AppTheme.fontBrand,
      fontSize: 20,
      fontWeight: FontWeight.w700,
      height: 1.25,
    );

    return SoftCard(
      color: Colors.transparent,
      borderRadius: BorderRadius.zero,
      border: Border.all(color: Colors.transparent),
      // Transparent, borderless card → no inset, so the description (and its
      // editor) use the full content width instead of losing 20px each side.
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Jira-style hierarchy breadcrumb: Epic / Story / Sub-task. Ancestors
          // are clickable; the current issue is the last, inert crumb.
          _breadcrumb(issue),
          // Title — double-tap to edit inline.
          if (_editingTitle)
            _InlineTitleEditor(
              controller: _titleCtrl,
              onSave: _saveTitle,
              onCancel: () => setState(() => _editingTitle = false),
            )
          else
            Tooltip(
              message: context.t('issues.editTitleHint'),
              waitDuration: const Duration(milliseconds: 700),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: beginTitleEdit,
                child: Text(issue.title, style: titleStyle),
              ),
            ),
          const SizedBox(height: 18),
          // Description — double-tap to edit as Markdown. While editing, the
          // section label rides on the editor's header row alongside the
          // Editor/Preview switcher, so it is rendered here only in view mode.
          if (_editingDesc)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionLabel(context.t('issues.description')),
                const SizedBox(height: 8),
                HinataEditor(
                  controller: _descCtrl,
                  fontSize: 14,
                  minHeight: 140,
                  autofocus: true,
                  // Image upload and the mention picker: the two authoring
                  // actions the toolbar cannot own, because they need this
                  // host's upload repository and smart-link resolver.
                  trailing: hinataEditorTools(context, _descCtrl),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.navy,
                      ),
                      onPressed: _saveDesc,
                      child: Text(context.t('common.save')),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => setState(() => _editingDesc = false),
                      child: Text(
                        context.t('common.cancel'),
                        style: TextStyle(color: AppColors.inkSoft),
                      ),
                    ),
                  ],
                ),
              ],
            )
          else ...[
            _sectionLabel(context.t('issues.description')),
            const SizedBox(height: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: _beginDescEdit,
              // A description the backfill could not convert still has its
              // markdown; "no description" would be a lie about a row that has
              // one.
              child: _describedDoc(issue) != null
                  ? HinataDocument(doc: _describedDoc(issue), fontSize: 14)
                  : Text(
                      context.t('issues.noDescription'),
                      style: TextStyle(
                        color: AppColors.inkFaint,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  /// The description to render: the stored document, or the legacy markdown
  /// the backfill left behind on the rows it could not convert.
  String? _describedDoc(Issue issue) =>
      documentOrLegacy(issue.descriptionDoc, issue.description);

  Widget _sectionLabel(String text) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      color: AppColors.inkFaint,
    ),
  );

  Widget _attachmentsSection(Issue issue) => AttachmentsSection(
    key: _attachmentsKey,
    issueId: widget.issueId,
    issueKey: issue.readableId,
    initial: issue.attachments,
    userNames: _names,
    onChanged: _notifyChanged,
  );

  /// "Verknüpfte Vorgänge" — the Jira-style issue links (blocks / duplicates /
  /// relates to …), shown for every issue directly under the sub-tasks card.
  Widget _linksSection(Issue issue) => IssueLinksSection(
    issueId: widget.issueId,
    projectId: issue.projectId,
    project: _project,
    userNames: _names,
    userAvatars: _avatars,
    onOpenIssue: _openLinkedIssue,
    onChanged: _notifyChanged,
  );

  /// Hierarchy breadcrumb above the title (`⚡ HIV-12 / ☑ HIV-48`). Hidden for
  /// top-level issues with no ancestors. Ancestors open on tap; the trailing
  /// crumb is the current issue and stays inert.
  Widget _breadcrumb(Issue issue) {
    final crumbs = [..._hierarchy.ancestors, issue];
    if (crumbs.length < 2) return const SizedBox.shrink();
    final row = <Widget>[];
    for (var i = 0; i < crumbs.length; i++) {
      final c = crumbs[i];
      final current = i == crumbs.length - 1;
      row.add(_breadcrumbCrumb(c, current: current));
      if (!current) {
        row.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Text(
              '/',
              style: TextStyle(color: AppColors.inkFaint, fontSize: 13),
            ),
          ),
        );
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 4,
        children: row,
      ),
    );
  }

  Widget _breadcrumbCrumb(Issue c, {required bool current}) {
    final inner = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TypeGlyph(type: c.type, size: 17),
        const SizedBox(width: 5),
        IdMono(
          c.readableId,
          fontSize: 12.5,
          color: current ? AppColors.ink : AppColors.stTodo,
        ),
      ],
    );
    if (current) return inner;
    return InkWell(
      onTap: () => _openLinkedIssue(c.readableId),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: inner,
      ),
    );
  }

  // ── child / sub-task panel ───────────────────────────────────────────────

  /// "Child issues" on an epic, "Sub-tasks" on a standard issue, nothing on a
  /// sub-task. Lists the direct children with a completion bar and an add
  /// affordance (a full create form for epics, an inline quick-add for tasks).
  /// Whether a child counts as "done". Authoritative on the project's resolved
  /// states — the issue's `resolvedAt` flag can go stale after a workflow change,
  /// which wrongly struck a still-open sub-task through.
  bool _childDone(Issue child) {
    final resolved = _project?.resolvedStates;
    if (resolved != null && resolved.isNotEmpty) {
      return resolved.contains(child.state);
    }
    return child.resolved;
  }

  Widget? _hierarchyCard(Issue issue) {
    if (issue.isSubtask) return null;
    final isEpic = issue.isEpic;
    final children = _hierarchy.children;
    final done = children.where(_childDone).length;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.t(isEpic ? 'issues.childIssues' : 'issues.subtasks'),
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (children.isNotEmpty)
                Text(
                  context.t(
                    'issues.progressDone',
                    variables: {'done': '$done', 'total': '${children.length}'},
                  ),
                  style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
            ],
          ),
          if (children.isNotEmpty) ...[
            const SizedBox(height: 10),
            HiveProgress(value: done / children.length),
          ],
          const SizedBox(height: 6),
          for (final c in children) _hierarchyRow(c, epic: isEpic),
          if (children.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                context.t(isEpic ? 'issues.noChildren' : 'issues.noSubtasks'),
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.inkFaint,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          const SizedBox(height: 8),
          if (isEpic)
            _addChildButton(issue)
          else
            _SubtaskQuickAdd(onSubmit: (title) => _addSubtask(issue, title)),
        ],
      ),
    );
  }

  Widget _hierarchyRow(Issue child, {required bool epic}) {
    final assignee = child.assigneeId != null
        ? _names[child.assigneeId!]
        : null;
    return InkWell(
      onTap: () => _openLinkedIssue(child.readableId),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            // Sub-tasks get a quick "done" toggle; epic children open to edit.
            if (!epic)
              GestureDetector(
                onTap: () => _toggleChildState(child),
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    _childDone(child)
                        ? LucideIcons.checkCheck
                        : LucideIcons.circle,
                    size: 17,
                    color: _childDone(child)
                        ? AppColors.success
                        : AppColors.inkFaint,
                  ),
                ),
              )
            else ...[
              TypeGlyph(type: child.type, size: 18),
              const SizedBox(width: 8),
            ],
            IdMono(child.readableId),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                child.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  decoration: _childDone(child)
                      ? TextDecoration.lineThrough
                      : null,
                  color: _childDone(child) ? AppColors.inkFaint : AppColors.ink,
                ),
              ),
            ),
            const SizedBox(width: 8),
            StateDotBadge(
              state: child.state,
              color: _projStateColor(_project, child.state),
            ),
            if (assignee != null) ...[
              const SizedBox(width: 10),
              HiveAvatar(name: assignee, size: 20),
            ],
          ],
        ),
      ),
    );
  }

  Widget _addChildButton(Issue epic) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: () => _addChild(epic),
      style: TextButton.styleFrom(foregroundColor: AppColors.stTodo),
      icon: const Icon(LucideIcons.plus, size: 16),
      label: Text(context.t('issues.addChild')),
    ),
  );

  Future<void> _addChild(Issue epic) async {
    final created = await showIssueForm(
      context,
      projectId: epic.projectId,
      parentId: epic.id,
      forcedType: 'STORY',
    );
    if (created != null) await _hierarchyChanged();
  }

  Future<bool> _addSubtask(Issue parent, String title) async {
    if (title.trim().isEmpty) return false;
    try {
      await _issueApi.createIssue({
        'projectId': parent.projectId,
        'title': title.trim(),
        'type': 'SUBTASK',
        'parentId': parent.id,
      });
      await _hierarchyChanged();
      return true;
    } on ApiFailure catch (failure) {
      _toast(failure.message);
      return false;
    } catch (_) {
      _toast('errors.unexpected');
      return false;
    }
  }

  /// Flips a sub-task between its first resolved state and its first open state.
  Future<void> _toggleChildState(Issue child) async {
    final resolved = _project?.resolvedStates ?? const [];
    final states = _project?.stateNames ?? const [];
    final String target;
    // Decide direction from the same authoritative "done" check that renders the
    // checkbox (project resolved-states), not the issue's stale `resolved` flag —
    // otherwise a state/flag mismatch makes the toggle a silent no-op.
    if (_childDone(child)) {
      target = states.firstWhere(
        (s) => !resolved.contains(s),
        orElse: () => child.state,
      );
    } else {
      target = resolved.isNotEmpty ? resolved.first : child.state;
    }
    if (target == child.state) return;
    try {
      await _issueApi.updateIssue(child.id, {'state': target});
      await _hierarchyChanged();
    } on ApiFailure catch (failure) {
      _toast(failure.message);
    } catch (_) {
      _toast('errors.unexpected');
    }
  }

  Widget _detailsCard(Issue issue) {
    final multiAssignee =
        context.read<AppConfigBloc>().state.meta?.multiAssignee ?? false;
    final reporterName = issue.reporterId != null
        ? _names[issue.reporterId!]
        : null;
    final me = context.read<AuthBloc>().state.user;
    final sprintName = issue.sprintId != null
        ? _sprints.where((s) => s.id == issue.sprintId).firstOrNull?.name
        : null;

    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('issues.details'),
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          // Status
          _DetailRow(
            label: context.t('issues.status'),
            onTap: _pickStatus,
            child: StateDotBadge(
              state: issue.state,
              color: _projStateColor(_project, issue.state),
            ),
          ),
          // Assignee(s) + "assign to me"
          _DetailRow(
            label: context.t(
              issue.assigneeIds.length > 1
                  ? 'issues.assignees'
                  : 'issues.assignee',
            ),
            onTap: _pickAssignee,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (issue.assigneeIds.isEmpty)
                  _person(null, fallback: context.t('issues.unassigned'))
                else if (issue.assigneeIds.length == 1)
                  _person(
                    _names[issue.assigneeIds.first],
                    imageUrl: _avatars[issue.assigneeIds.first],
                    fallback: context.t('issues.unassigned'),
                  )
                else
                  // Multiple assignees: a compact stacked avatar group (matches
                  // the board/cards); the full list is in the picker on tap.
                  HiveAvatarStack(
                    names: [
                      for (final aid in issue.assigneeIds) _names[aid] ?? '?',
                    ],
                    imageUrls: [
                      for (final aid in issue.assigneeIds) _avatars[aid],
                    ],
                    size: 28,
                  ),
                if (me != null && !issue.assigneeIds.contains(me.id)) ...[
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: () => _patch(
                      multiAssignee
                          ? {
                              'assigneeIds': [...issue.assigneeIds, me.id],
                            }
                          : {'assigneeId': me.id},
                    ),
                    child: Text(
                      context.t('issues.assignToMe'),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.stTodo,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Priority
          _DetailRow(
            label: context.t('issues.priority'),
            onTap: _pickPriority,
            child: PriorityFlag(priority: issue.priority, withLabel: true),
          ),
          // Type — a sub-task's type is fixed; everything else is switchable.
          _DetailRow(
            label: context.t('issues.type'),
            onTap: issue.isSubtask ? null : _pickType,
            child: TypeBadge(type: issue.type),
          ),
          // Parent link — epics have no parent; standard issues attach to an
          // epic; sub-tasks attach to a standard issue.
          if (!issue.isEpic) _parentRow(issue),
          // Story points (Scrum estimate)
          _DetailRow(
            label: context.t('issues.storyPoints'),
            onTap: _pickStoryPoints,
            child: _pointsValue(issue.storyPoints),
          ),
          // Labels ("Stichwort")
          _DetailRow(
            label: context.t('issues.label'),
            onTap: _pickLabels,
            child: issue.tags.isEmpty
                ? Text(
                    context.t('issues.noLabels'),
                    style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
                  )
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in issue.tags)
                        LabelTag(t, hue: _project?.hueForLabel(t)),
                    ],
                  ),
          ),
          // Sprint
          _DetailRow(
            label: context.t('issues.sprint'),
            onTap: _sprints.isEmpty ? null : _pickSprint,
            child: Text(
              sprintName ?? context.t('issues.noSprint'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: sprintName != null
                    ? AppColors.stTodo
                    : AppColors.inkFaint,
              ),
            ),
          ),
          // Author / reporter (read-only)
          _DetailRow(
            label: context.t('issues.author'),
            last: true,
            child: _person(
              reporterName,
              imageUrl: issue.reporterId != null
                  ? _avatars[issue.reporterId!]
                  : null,
              fallback: context.t('issues.unassigned'),
            ),
          ),
        ],
      ),
    );
  }

  /// The watch section of the top bars' "…" menu — the toggle row and the
  /// roster under it. Null until the issue is loaded (there is nothing to watch
  /// yet); read afresh on every top-bar build, since the directory that resolves
  /// the roster's names hydrates after first paint.
  IssueWatchMenuData? get watchMenu {
    final issue = _issue;
    if (issue == null) return null;
    return IssueWatchMenuData(
      cubit: _watch,
      issue: issue,
      onToggle: toggleWatch,
      nameFor: (id) => _names[id],
      avatarFor: (id) => _avatars[id],
    );
  }

  /// Subscribes or unsubscribes the caller. Unlike the switch this replaced,
  /// the control is gone from the screen the moment it is tapped (the menu
  /// closes), so the outcome is said out loud either way — the optimistic flip
  /// alone would leave a refused toggle looking like nothing happened.
  Future<void> toggleWatch() async {
    if (_watch.userId == null || _watch.state.busy) return;
    final wasWatching = _watch.watching;
    await _watch.toggle();
    if (!mounted) return;
    // Set for exactly one state after a failed toggle; `_toast` localises a
    // fallback key and passes an already-localised backend message through.
    final error = _watch.state.errorKey;
    if (error != null) {
      _toast(error);
      return;
    }
    _toast(
      wasWatching ? 'issues.watch.toastOff' : 'issues.watch.toastOn',
      kind: GlassToastKind.success,
    );
  }

  /// Read-only display of an issue's story-point estimate.
  Widget _pointsValue(int? points) {
    if (points == null) {
      return Text(
        context.t('issues.noValue'),
        style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
      );
    }
    return Text(
      '$points',
      style: const TextStyle(
        fontFamily: AppTheme.fontMono,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _person(String? name, {required String fallback, String? imageUrl}) {
    if (name == null || name.isEmpty) {
      return Text(
        fallback,
        style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HiveAvatar(name: name, imageUrl: imageUrl, size: 22),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _dateValue(DateTime? date, {required bool isStart}) {
    if (date == null) {
      return Text(
        context.t('issues.noValue'),
        style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          MaterialLocalizations.of(context).formatMediumDate(date),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: () =>
              _patch({isStart ? 'clearStartDate' : 'clearDueDate': true}),
          child: Icon(LucideIcons.x, size: 15, color: AppColors.inkFaint),
        ),
      ],
    );
  }

  Widget _timeCard(Issue issue) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.t('issues.timeline'),
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () async {
                  final logged = await showWorkLogSheet(context, issue.id);
                  if (logged == true && mounted) {
                    _notifyChanged();
                    await _reloadWorkItems();
                  }
                },
                child: Text(
                  context.t('issues.logTime'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accentStrong,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Schedule (moved here from the Details panel).
          _DetailRow(
            label: context.t('issues.startDate'),
            onTap: (_) => _pickDate(isStart: true),
            child: _dateValue(issue.startDate, isStart: true),
          ),
          _DetailRow(
            label: context.t('issues.dueDate'),
            onTap: (_) => _pickDate(isStart: false),
            last: true,
            child: _dateValue(issue.dueDate, isStart: false),
          ),
          const SizedBox(height: 12),
          Text(
            context.t(
              'issues.spent',
              variables: {
                'spent': fmtDuration(issue.spentMinutes),
                'estimate': fmtDuration(issue.estimateMinutes),
              },
            ),
            style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
          ),
          for (final item in _workItems.take(8))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.timer,
                    size: 16,
                    color: AppColors.accentStrong,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${fmtDuration(item.durationMinutes)} · ${item.activityType}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  if (item.date != null)
                    Text(
                      MaterialLocalizations.of(
                        context,
                      ).formatShortDate(item.date!),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.inkFaint,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Baseline issue provenance shown as a separate block directly beneath the
  /// Timeline card: when it was created and last touched, as short relative
  /// labels (e.g. "Created 2h ago" / "Updated 5m ago").
  Widget _issueMeta(Issue issue) {
    final created = issue.createdAt;
    // A brand-new issue has createdAt == updatedAt; showing "updated" then adds
    // no information, so only surface it once something was actually changed.
    final updated =
        (issue.updatedAt != null &&
            (created == null || !issue.updatedAt!.isAtSameMomentAs(created)))
        ? issue.updatedAt
        : null;
    if (created == null && updated == null) return const SizedBox.shrink();

    Widget line(IconData icon, String text) => Row(
      children: [
        Icon(icon, size: 13, color: AppColors.inkFaint),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (created != null)
            line(LucideIcons.clock, _relLabel(created, created: true)),
          if (updated != null) ...[
            if (created != null) const SizedBox(height: 6),
            line(LucideIcons.history, _relLabel(updated, created: false)),
          ],
        ],
      ),
    );
  }

  /// "Created/Updated N units ago", fully written out (Jira-style) and
  /// localized with proper plurals; falls back to a "just …" phrasing under a
  /// minute.
  String _relLabel(DateTime at, {required bool created}) {
    final d = DateTime.now().difference(at);
    if (d.inSeconds < 60) {
      return context.t(
        created ? 'issues.createdJustNow' : 'issues.updatedJustNow',
      );
    }

    final (String unitKey, int count) = switch (d) {
      _ when d.inMinutes < 60 => ('issues.relMinutes', d.inMinutes),
      _ when d.inHours < 24 => ('issues.relHours', d.inHours),
      _ when d.inDays < 7 => ('issues.relDays', d.inDays),
      _ when d.inDays < 30 => ('issues.relWeeks', d.inDays ~/ 7),
      _ when d.inDays < 365 => ('issues.relMonths', d.inDays ~/ 30),
      _ => ('issues.relYears', d.inDays ~/ 365),
    };

    final time = context.t(unitKey, count: count, variables: {'count': count});
    return context.t(
      created ? 'issues.createdAgo' : 'issues.updatedAgo',
      variables: {'time': time},
    );
  }

  /// True when the host floats the composer (sheet sticky bar / route overlay)
  /// rather than showing it inline in the activity card.
  bool composerFloats(BuildContext context) => widget.floatingComposer;

  /// Whether the issue has finished loading (so the host can defer the floating
  /// composer until there is something to comment on).
  bool get hasIssue => _issue != null;

  /// The full-screen route's pinned top bar (back · id/state · minimize · trash).
  /// Rendered by [IssueDetailScreen] as a top overlay — NOT inline in the body —
  /// so the actions stay reachable when the comment thread scrolls long. [glass]
  /// (0→1, driven by scroll offset) fades the shell-style progressive blur +
  /// scrim in as content scrolls up under it, so at the very top the bar is
  /// invisible chrome and only frosts once you start scrolling.
  Widget buildRouteTopBar(BuildContext context, {required double glass}) {
    final issue = _issue;
    if (issue == null) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final topInset = MediaQuery.viewPaddingOf(context).top;
    final g = glass.clamp(0.0, 1.0);
    final scrimTop = (dark ? 0.5 : 0.16) * g;
    return SizedBox(
      height: topInset + kRouteTopBarHeight,
      child: Stack(
        children: [
          // Progressive blur, faded in by scaling maxSigma with scroll (0 → no
          // filter → perfectly sharp at the top of the page). Non-interactive.
          Positioned.fill(
            child: IgnorePointer(
              child: ProgressiveBlur(
                maxSigma: (dark ? 14.0 : 12.0) * g,
                direction: ProgressiveBlurDirection.topToBottom,
              ),
            ),
          ),
          // Darkening scrim (fades to transparent at the bottom edge so the bar
          // dissolves into the content instead of a hard cut-off).
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: scrimTop),
                      Colors.black.withValues(alpha: scrimTop * 0.4),
                      Colors.black.withValues(alpha: 0),
                    ],
                    stops: const [0.0, 0.6, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // The bar row itself, pinned just below the status bar — always visible
          // and tappable regardless of [glass].
          Positioned(
            left: 0,
            right: 0,
            top: topInset,
            child: _RouteTopBar(
              issue: issue,
              busy: _busy,
              stateColor: _projStateColor(_project, issue.state),
              link: issueWebLink(_issueApi.apiBaseUrl, issue.linkId),
              onMinimize: widget.canMinimize ? _minimizeToModal : null,
              onDelete: () => _confirmDelete(issue),
              onClone: () => cloneIssue(),
              onMove: () => moveIssue(),
              onClose: _closeRoute,
              onReply: _replyEmailAction(issue),
              watch: watchMenu,
              canDelete: _canDelete,
            ),
          ),
        ],
      ),
    );
  }

  /// The docked composer, pinned to the bottom by the host (sheet: sticky bar;
  /// route: Stack overlay). Phone/narrow: spans the whole width. Tablet/desktop
  /// (2-column): constrained to the comment column's width + left-aligned with
  /// the body, so it floats only over the comment section, never the details
  /// column. [deviceSafeArea] adds the home-indicator inset (sheet); the route
  /// instead positions above the nav via `bottomGutter`, so it passes false.
  Widget buildFloatingComposer(
    BuildContext context, {
    bool deviceSafeArea = true,
  }) {
    // The floating composer lives in a separate subtree (the sheet's sticky
    // action bar / the route's Stack overlay) from the body, so it must re-supply
    // the SmartLinkScope — otherwise the composer's MentionField can't resolve
    // `@`-mentions/smart-links (it reads the resolver from context).
    final issue = _issue;
    if (issue == null) return const SizedBox.shrink();
    // Batch-selection mode takes over the bottom dock: the selection toolbar
    // (cancel · N selected · delete) floats here in place of the composer, so it
    // stays reachable however far the feed is scrolled — the actions are useless
    // if they scroll off-screen. It rides above the keyboard-guard below since
    // the keyboard is down while selecting.
    if (_selectionMode && _activityFilter != _ActivityFilter.history) {
      return _dockAligned(
        deviceSafeArea: deviceSafeArea,
        child: _selectionBar(floating: true),
      );
    }
    // Wolt lifts the sticky action bar above the keyboard whenever *any* field
    // is focused. That's wrong for the comment composer: while the keyboard is
    // up for another input (sub-task / linked-issue / inline title-edit), the
    // composer would still ride above it. Only keep it mounted when the keyboard
    // is down or the comment field itself is the reason it's up.
    //
    // Read the *raw* keyboard height off the FlutterView, NOT
    // `MediaQuery.viewInsetsOf(context)`: Wolt hosts the sheet in a Scaffold with
    // `resizeToAvoidBottomInset`, which strips the bottom view inset from the
    // sticky-bar subtree's MediaQuery (`removeViewInsets(removeBottom: true)`),
    // so MediaQuery would report 0 here even with the keyboard up — and the
    // composer would never hide. The physical view inset is immune to that.
    // [didChangeMetrics] nudges this subtree to re-evaluate as the keyboard moves.
    final keyboardUp = View.of(context).viewInsets.bottom > 0;
    if (keyboardUp && !_commentFocus.hasFocus) return const SizedBox.shrink();
    return SmartLinkScope(
      resolver: _buildResolver(issue),
      child: _dockAligned(
        deviceSafeArea: deviceSafeArea,
        child: _commentComposer(),
      ),
    );
  }

  /// Anchors a bottom-dock [child] (composer or selection toolbar) with the same
  /// width treatment: full-width on phone/narrow, constrained + left-aligned to
  /// the comment column (flex 3 of 3+2 with an 18px gutter) on the 2-column view.
  Widget _dockAligned({required Widget child, required bool deviceSafeArea}) {
    return LayoutBuilder(
      builder: (context, c) {
        // Content width mirrors the body's inner width (20px padding / side).
        final contentW = c.maxWidth - 40;
        if (contentW < 680) {
          // Phone / narrow: full-width dock over the whole area.
          return _composerDock(
            deviceSafeArea: deviceSafeArea,
            horizontal: 16,
            child: child,
          );
        }
        // 2-column: match the left column, aligned with the body's left padding.
        final leftW = (contentW - 18) * 3 / 5;
        return Padding(
          padding: const EdgeInsets.only(left: 20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: leftW,
              child: _composerDock(
                deviceSafeArea: deviceSafeArea,
                horizontal: 0,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }

  /// The docked composer chrome: a bottom-up fade into the translucent modal
  /// surface (so the feed dissolves behind it) wrapping the glass composer.
  /// Bottom-anchored at the modal edge, so the inline format editor grows
  /// *upward* in place.
  Widget _composerDock({
    required bool deviceSafeArea,
    required Widget child,
    double horizontal = 16,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Fade INTO the *translucent* modal surface (glassWoltSurface floats content
    // on `canvas @ 0.88/0.84`), not full-opacity canvas — else it reads as a
    // lighter, hard-edged box instead of a seamless dissolve.
    final wash = _panelWashAlpha(dark);
    final padding = EdgeInsets.fromLTRB(
      horizontal,
      26,
      horizontal,
      deviceSafeArea
          ? (MediaQuery.viewPaddingOf(context).bottom <= 0
                ? 16
                : MediaQuery.viewPaddingOf(context).bottom)
          : 12,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            // Horizontal mask: taper the wash's alpha over the outer ~32px on
            // each side, so the left/right edges dissolve too instead of
            // showing a hard vertical seam against the feed.
            shaderCallback: (rect) {
              final f = (32 / rect.width).clamp(0.0, 0.5);
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: const [
                  Color(0x00FFFFFF),
                  Color(0xFFFFFFFF),
                  Color(0xFFFFFFFF),
                  Color(0x00FFFFFF),
                ],
                stops: [0, f, 1 - f, 1],
              ).createShader(rect);
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.canvas.withValues(alpha: 0),
                    AppColors.canvas.withValues(alpha: wash * 0.7),
                    AppColors.canvas.withValues(alpha: wash),
                    AppColors.canvas.withValues(alpha: wash),
                  ],
                  stops: const [0, 0.35, 0.6, 1],
                ),
              ),
            ),
          ),
        ),
        Padding(padding: padding, child: child),
      ],
    );
  }

  /// The modal surface's canvas alpha (see `glassWoltSurface`), so the composer
  /// dock's fade dissolves into the *actual* translucent surface instead of
  /// painting an opaque, mismatched box over it.
  double _panelWashAlpha(bool dark) => dark ? 0.84 : 0.88;

  Widget _activityCard() {
    final filter = _activityFilter;
    // Hide the inline composer when it floats (phone sheet) — it's rendered in
    // the sticky action bar instead; otherwise keep it inline.
    final showComposer =
        filter != _ActivityFilter.history && !composerFloats(context);
    return SoftCard(
      color: Colors.transparent,
      borderRadius: BorderRadius.zero,
      border: Border.all(color: Colors.transparent),
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('issues.activity'),
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          // Filter tabs (All · Comments · History) + comment sort selector.
          // The tab bar hugs its content on the left (no Expanded — that
          // stretched its background); a Spacer pushes the sort selector right.
          LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                _ActivityTabs(
                  value: filter,
                  onChanged: (f) => setState(() => _activityFilter = f),
                ),
                const Spacer(),
                if (filter != _ActivityFilter.history)
                  CommentSortButton(
                    sort: _commentSort,
                    onChanged: _setCommentSort,
                    // Long localized labels ("Neueste zuerst") don't fit next
                    // to the tab bar on phones — fall back to icon-only.
                    compact: constraints.maxWidth < 480,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ..._activityItems(filter),
          if (showComposer) ...[const SizedBox(height: 4), _commentComposer()],
        ],
      ),
    );
  }

  /// Liquid-Glass comment composer (chat-style): `+` attachment menu, mic↔send
  /// morph, live voice recording and a Markdown format toolbar. Wraps a
  /// [MentionField] so `@`-smart-link autocomplete keeps working.
  Widget _commentComposer() {
    final replying = _replyingTo;
    return GlassCommentComposer(
      controller: _comment,
      focusNode: _commentFocus,
      actions: _commentActions,
      editing: _editingComment != null,
      onCancelEdit: _cancelEditComment,
      replyingToName: replying == null
          ? null
          : (_names[replying.authorId] ?? replying.authorId),
      replyingToPreview: replying == null ? null : _replyPreview(replying),
      onCancelReply: _cancelReply,
      onSubmitText: _submitComment,
      onSendVoice: _sendVoiceComment,
      onAttach: _onComposerAttach,
    );
  }

  /// One-line preview of a comment for the reply bar ("🎤"/"📷" for media).
  String _replyPreview(IssueComment c) {
    if (c.isVoice) return '🎤';
    final text = c.text.trim();
    if (RegExp(r'^\s*!\[[^\]]*\]\([^)]+\)\s*$').hasMatch(text)) return '📷';
    final oneLine = text.replaceAll(RegExp(r'\s+'), ' ');
    return oneLine.length > 80 ? '${oneLine.substring(0, 80)}…' : oneLine;
  }

  /// Handles the `+` menu picks. Camera/gallery insert an inline Markdown photo
  /// into the comment (the body is Markdown, like the editor); "Anhang" uploads
  /// any file — including video/PDF — as an issue attachment.
  Future<void> _onComposerAttach(ComposerAttach kind) async {
    switch (kind) {
      case ComposerAttach.camera:
        await insertCommentPhoto(context, _commentActions, ImageSource.camera);
      case ComposerAttach.gallery:
        await insertCommentPhoto(context, _commentActions, ImageSource.gallery);
      case ComposerAttach.file:
        // Drive the attachments section's own optimistic upload so the new tile
        // appears live (no reload, no dependence on the SSE `added` event).
        final section = _attachmentsKey.currentState;
        if (section != null) {
          await section.pickFiles();
        } else {
          // Fallback (section not mounted): blind upload + list refresh.
          await attachFileToIssue(
            context,
            widget.issueId,
            onChanged: _notifyChanged,
          );
        }
    }
  }

  /// Uploads a recorded voice message as a comment, then refreshes to the newest
  /// page so the playable bubble appears at the bottom of the thread.
  Future<void> _sendVoiceComment(VoiceRecording recording) async {
    if (_sendingComment) return;
    _sendingComment = true;
    try {
      final replyTarget = _replyingTo;
      final created = await _commentApi.addVoiceComment(
        widget.issueId,
        bytes: recording.bytes,
        mime: recording.mime,
        durationMs: recording.durationMs,
        peaks: recording.peaks,
        replyToId: replyTarget?.id,
      );
      if (!mounted) return;
      setState(() => _replyingTo = null);
      _bumpComposer();
      if (created.isReply) {
        _onReplyPosted(created);
      } else {
        await _refreshTopLevelAfterPost();
      }
      _notifyChanged();
    } catch (_) {
      if (!mounted) return;
      showGlassErrorToast(context, context.t('comments.voiceFailed'));
    } finally {
      _sendingComment = false;
    }
  }

  /// Builds the activity feed for [filter]:
  ///  • comments → comments newest-first (feed style)
  ///  • history  → change events newest-first
  ///  • all      → both, merged newest-first
  List<Widget> _activityItems(_ActivityFilter filter) {
    final me = context.read<AuthBloc>().state.user;
    // Every loaded comment (incl. loaded replies) gets a stable key so a
    // deep-link jump / reveal can scroll to it.
    for (final c in [
      ..._comments,
      ..._pinned,
      for (final t in _replyThreads.values) ...t.replies,
    ]) {
      _commentKeys.putIfAbsent(c.id, () => GlobalKey());
    }
    final interactions = CommentInteractions(
      meId: me?.id,
      nameFor: (id) => _names[id] ?? id,
      avatarFor: (id) => _avatars[id],
      loadVoice: (c) =>
          () => _commentApi.voiceCommentAudio(widget.issueId, c.id),
      canManage: (c) => me != null && c.authorId == me.id,
      onEdit: _promptEditComment,
      onDelete: _deleteComment,
      onReply: _startReply,
      onReact: _reactToComment,
      onCopy: _copyComment,
      onCopyLink: _copyCommentLink,
      onTogglePin: _togglePin,
      onEnterSelection: _enterSelection,
      onJumpToComment: _jumpToComment,
      threadOf: _threadOf,
      onToggleReplies: _toggleReplies,
      onLoadMoreReplies: _loadMoreReplies,
    );
    // Same flat tile as the Comments tab, so comments look identical in every
    // tab (voice comments stay playable in the merged "All" feed too). The
    // ValueKey gives each row a stable identity so a live reorder never reuses
    // one comment's State (e.g. a voice controller) for a different comment;
    // the RepaintBoundary keeps a bubble's glass/blur repaint from cascading.
    Widget commentTile(IssueComment c) => RepaintBoundary(
      key: ValueKey('cmt-${c.id}'),
      child: CommentBubbleRow(
        comment: c,
        interactions: interactions,
        selectionMode: _selectionMode,
        selected: _selectedIds.contains(c.id),
        onToggleSelected: _toggleSelected,
      ),
    );
    // id → readable id for the activity feed's PARENT rows. Drawn from the
    // referenced issues plus the loaded hierarchy (which always includes this
    // issue's parent), so a parent-change entry keeps its readable id without
    // draining the whole project.
    final issueIds = {
      for (final i in _projectIssues.values) i.id: i.readableId,
      for (final a in _hierarchy.ancestors) a.id: a.readableId,
      for (final c in _hierarchy.children) c.id: c.readableId,
    };
    Widget activityTile(IssueActivity a) => _ActivityTile(
      activity: a,
      actorName: a.actorId != null
          ? (_names[a.actorId!] ?? a.actorId!)
          : context.t('issues.systemActor'),
      names: _names,
      sprintNames: _sprintNames,
      issueIds: issueIds,
    );

    Widget loadMore(String label, VoidCallback onTap) =>
        _LoadMoreTile(label: label, loading: _loadingMore, onTap: onTap);

    CommentThread thread(List<IssueComment> items, {bool pinned = false}) =>
        CommentThread(
          comments: items,
          interactions: interactions,
          pinnedSection: pinned,
          selectionMode: _selectionMode,
          selectedIds: _selectedIds,
          onToggleSelected: _toggleSelected,
          highlightedId: _highlightedCommentId,
          commentKeys: _commentKeys,
        );

    switch (filter) {
      case _ActivityFilter.comments:
        // Pinned comments float above the feed (any member can pin); de-dupe them
        // out of the chronological list so a pinned comment shows only once.
        final pinnedIds = {for (final c in _pinned) c.id};
        final feed = [
          for (final c in _comments)
            if (!pinnedIds.contains(c.id)) c,
        ];
        if (_pinned.isEmpty && feed.isEmpty) {
          return [_emptyActivity(context.t('issues.activityEmpty'))];
        }
        return [
          if (_pinned.isNotEmpty) ...[
            _pinnedHeader(),
            thread(_pinned, pinned: true),
            const SizedBox(height: 8),
            Divider(height: 1, color: AppColors.hairline),
            const SizedBox(height: 12),
          ],
          // Liquid-Glass feed thread, newest-first (text + playable voice
          // bubbles): the newest comment sits at the TOP; older pages append
          // below as the user scrolls DOWN toward the sentinel.
          thread(feed),
          // Auto-loading sentinel at the BOTTOM of the thread (older comments
          // load below it); [_onCommentScroll] pulls the next older page as it
          // nears the viewport — no manual "load older" button. The keyed box
          // holds a stable position so [_onCommentScroll] can tell when it nears
          // the viewport; the spinner shows ONLY while a page is actually
          // loading (not as a permanent "there's more" marker, which read as
          // "stuck").
          if (_hasMoreComments)
            Padding(
              key: _commentsLoaderKey,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(
                height: 26,
                child: Center(
                  child: _loadingMore ? const HiveLoader(size: 26) : null,
                ),
              ),
            ),
        ];
      case _ActivityFilter.history:
        if (_activity.isEmpty) {
          return [_emptyActivity(context.t('issues.historyEmpty'))];
        }
        return [
          for (final a in _activity) activityTile(a),
          if (_hasMoreActivity)
            loadMore(context.t('issues.loadMore'), _loadMoreActivity),
        ];
      case _ActivityFilter.all:
        // Merge by timestamp, newest first.
        final epoch = DateTime.fromMillisecondsSinceEpoch(0);
        final merged = <({DateTime time, Widget tile})>[
          for (final c in _comments)
            (time: c.createdAt ?? epoch, tile: commentTile(c)),
          for (final a in _activity)
            (time: a.createdAt ?? epoch, tile: activityTile(a)),
        ]..sort((x, y) => y.time.compareTo(x.time));
        if (merged.isEmpty) {
          return [_emptyActivity(context.t('issues.activityEmpty'))];
        }
        return [
          for (final m in merged) m.tile,
          if (_hasMoreComments || _hasMoreActivity)
            loadMore(context.t('issues.loadMore'), _loadMoreAll),
        ];
    }
  }

  /// "All" tab: pull the next older page of whichever streams still have more.
  Future<void> _loadMoreAll() async {
    if (_loadingMore) return;
    if (_hasMoreComments) await _loadMoreComments();
    if (_hasMoreActivity) await _loadMoreActivity();
  }

  /// Batch-selection toolbar (cancel · N selected · delete) shown while
  /// selecting own comments. It floats in the bottom dock ([floating]) so the
  /// actions stay reachable no matter where the feed is scrolled.
  Widget _selectionBar({bool floating = false}) => Container(
    margin: floating ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.hairline),
      boxShadow: floating
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ]
          : null,
    ),
    child: Row(
      children: [
        IconButton(
          onPressed: _exitSelection,
          visualDensity: VisualDensity.compact,
          icon: Icon(LucideIcons.x, size: 18, color: AppColors.inkSoft),
        ),
        Text(
          context.t('comments.selectedCount', count: _selectedIds.length),
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
          icon: const Icon(
            LucideIcons.trash2,
            size: 16,
            color: AppColors.danger,
          ),
          label: Text(
            context.t('common.delete'),
            style: const TextStyle(
              color: AppColors.danger,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  /// Small "📌 Pinned" section header shown above pinned comments.
  Widget _pinnedHeader() => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Row(
      children: [
        Icon(LucideIcons.pin, size: 13, color: AppColors.inkFaint),
        const SizedBox(width: 6),
        Text(
          context.t('comments.pinnedSection'),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: AppColors.inkFaint,
          ),
        ),
      ],
    ),
  );

  Widget _emptyActivity(String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 22),
    child: Center(
      child: Text(
        message,
        style: TextStyle(color: AppColors.inkFaint, fontSize: 13),
      ),
    ),
  );

  // ── pickers ────────────────────────────────────────────────────────────

  Future<void> _pickStatus(Rect anchor) async {
    final states = _project?.stateNames ?? [_issue!.state];
    final chosen = await _showOptions<String>(
      title: context.t('issues.status'),
      anchorRect: anchor,
      options: [
        for (final s in states)
          (
            value: s,
            child: StateDotBadge(state: s, color: _projStateColor(_project, s)),
          ),
      ],
    );
    if (chosen != null) await _patch({'state': chosen});
  }

  Future<void> _pickPriority(Rect anchor) async {
    const priorities = kIssuePriorityCodes;
    final chosen = await _showOptions<String>(
      title: context.t('issues.priority'),
      anchorRect: anchor,
      options: [
        for (final p in priorities)
          (value: p, child: PriorityFlag(priority: p, withLabel: true)),
      ],
    );
    if (chosen != null) await _patch({'priority': chosen});
  }

  Future<void> _pickType(Rect anchor) async {
    // SUBTASK is never a free pick — it is created only via the sub-task panel.
    const types = ['STORY', 'TASK', 'BUG', 'FEATURE', 'EPIC'];
    final chosen = await _showOptions<String>(
      title: context.t('issues.type'),
      anchorRect: anchor,
      options: [for (final t in types) (value: t, child: TypeBadge(type: t))],
    );
    if (chosen != null) await _patch({'type': chosen});
  }

  /// The "Epic" (standard issues) / "Parent" (sub-tasks) detail row. Value is
  /// the immediate ancestor; tapping opens the parent picker.
  Widget _parentRow(Issue issue) {
    final parent = _hierarchy.ancestors.isNotEmpty
        ? _hierarchy.ancestors.last
        : null;
    return _DetailRow(
      label: issue.isSubtask
          ? context.t('issues.parent')
          : context.t('issues.epic'),
      onTap: (anchor) => _pickParent(issue, anchor),
      child: parent == null
          ? Text(
              issue.isSubtask ? '—' : context.t('issues.noEpic'),
              style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
            )
          : _parentChip(parent),
    );
  }

  Widget _parentChip(Issue parent) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      TypeGlyph(type: parent.type, size: 18),
      const SizedBox(width: 7),
      Flexible(
        child: Text(
          '${parent.readableId}  ${parent.title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );

  Future<void> _pickParent(Issue issue, Rect anchor) async {
    // On-the-fly parent assignment: an inline popover with a debounced, paginated
    // server search (recent items first). Sub-tasks attach to a standard issue;
    // standard issues attach to an epic.
    final result = await showEpicSearchPopover(
      context,
      anchorRect: anchor,
      projectId: issue.projectId,
      currentIssueId: issue.id,
      forSubtask: issue.isSubtask,
      hasCurrentParent: _hierarchy.ancestors.isNotEmpty,
    );
    if (result == null || !mounted) return;
    // `_patch` → PATCH /issues/{id} → `_reloadHierarchy`, so the breadcrumb and
    // parent row refresh immediately after the write.
    await _patch({'parentId': result.clear ? '' : result.issue!.id});
  }

  Future<void> _pickLabels(Rect anchor) async {
    final issue = _issue;
    if (issue == null) return;
    final available = <String>{
      ...?_project?.labelNames,
      ...issue.tags,
    }.where((l) => !_deletedLabels.contains(l)).toList();
    var didDelete = false;
    final result = await showLabelPicker(
      context,
      anchor: anchor,
      available: available,
      selected: issue.tags.where((l) => !_deletedLabels.contains(l)).toList(),
      onDelete: (l) async {
        await _projectApi.deleteProjectLabel(issue.projectId, l);
        _deletedLabels.add(l);
        didDelete = true;
      },
    );
    if (result != null) {
      await _patch({'tags': result});
    } else if (didDelete && mounted) {
      // Dismissed without saving, but a label was deleted server-side — pull
      // the fresh issue so its tag chips reflect the removal.
      try {
        final fresh = await _issueApi.issue(widget.issueId);
        if (mounted) setState(() => _adoptIssue(fresh));
      } catch (_) {
        /* next full load reflects server truth */
      }
    }
  }

  static const _noSprint = '__none__';

  Future<void> _pickSprint(Rect anchor) async {
    final chosen = await _showOptions<String>(
      title: context.t('issues.sprint'),
      anchorRect: anchor,
      options: [
        (
          value: _noSprint,
          child: Text(
            context.t('issues.noSprint'),
            style: TextStyle(color: AppColors.inkFaint),
          ),
        ),
        for (final s in _sprints) (value: s.id, child: Text(s.name)),
      ],
    );
    if (chosen != null) {
      // Empty string clears the sprint server-side (null is ignored by PATCH).
      await _patch({'sprintId': chosen == _noSprint ? '' : chosen});
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart ? _issue!.startDate : _issue!.dueDate;
    final picked = await showGlassDatePicker(
      context,
      title: context.t(isStart ? 'issues.startDate' : 'issues.dueDate'),
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      final iso = picked.toIso8601String().substring(0, 10);
      await _patch({isStart ? 'startDate' : 'dueDate': iso});
    }
  }

  // Anchor unused: estimate opens as a centered glass dialog, not a popover.
  Future<void> _pickStoryPoints(Rect anchor) async {
    final issue = _issue;
    if (issue == null) return;
    final result = await showStoryPointsDialog(
      context,
      current: issue.storyPoints,
      subtitle: '${issue.readableId} · ${issue.title}',
    );
    if (result != null) {
      await _patch(
        result.points == null
            ? {'clearStoryPoints': true}
            : {'storyPoints': result.points},
      );
    }
  }

  // Anchor unused: the people picker is a taller search list, kept as a sheet.
  Future<void> _pickAssignee(Rect anchor) async {
    final me = context.read<AuthBloc>().state.user;
    final multi =
        context.read<AppConfigBloc>().state.meta?.multiAssignee ?? false;
    // Tablet/desktop: an anchored, searchable popover beside the field (like the
    // board filter). Phone: the bottom sheet. Both reuse _PeoplePicker.
    final wide = MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint;
    Widget picker(BuildContext sheetContext) => _PeoplePicker(
      anchored: wide,
      users: _users,
      meId: me?.id,
      multiSelect: multi,
      initialSelected: (_issue?.assigneeIds ?? const []).toSet(),
      // Multi mode: stay open, persist the whole set on every toggle.
      onSelectionChanged: (ids) => _patch({'assigneeIds': ids.toList()}),
      onUnassign: () {
        Navigator.of(sheetContext).pop();
        // Empty string clears the assignee (PATCH ignores null).
        _patch({'assigneeId': ''});
      },
      onAssignMe: me == null
          ? null
          : () {
              Navigator.of(sheetContext).pop();
              _patch({'assigneeId': me.id});
            },
      onSelect: (id) {
        Navigator.of(sheetContext).pop();
        _patch({'assigneeId': id});
      },
    );

    if (wide) {
      await showGlassAnchoredPopover<void>(
        context,
        anchorRect: anchor,
        width: 340,
        maxHeight: 520,
        builder: picker,
      );
      return;
    }
    // _PeoplePicker draws its own grab handle, so suppress the helper's.
    await showGlassBottomSheet<void>(
      context,
      showHandle: false,
      builder: picker,
    );
  }

  Future<T?> _showOptions<T>({
    required String title,
    required List<({T value, Widget child})> options,
    Rect? anchorRect,
  }) {
    return showGlassOptions<T>(
      context,
      title: title,
      options: options,
      anchorRect: anchorRect,
    );
  }

  /// Archive / delete / restore entry point behind the top-bar action.
  /// An archived issue restores directly (non-destructive); otherwise the
  /// role-aware confirm offers archive to everyone and delete only to
  /// platform admins, project leads and team admins.
  Future<void> _confirmDelete(Issue issue) async {
    if (issue.archived) {
      try {
        final restored = await _issueApi.unarchiveIssue(issue.id);
        if (!mounted) return;
        setState(() => _adoptIssue(restored));
        _publishHeader(restored);
        _notifyChanged();
      } on ApiFailure catch (failure) {
        _toast(failure.message);
      }
      return;
    }
    final action = await showGlassModal<_IssueRemovalAction>(
      context,
      width: 420,
      builder: (_) => _RemoveIssueConfirm(issue: issue, canDelete: _canDelete),
    );
    if (action == null) return;
    try {
      switch (action) {
        case _IssueRemovalAction.delete:
          await _issueApi.deleteIssue(issue.id);
        case _IssueRemovalAction.archive:
          await _issueApi.archiveIssue(issue.id);
      }
      _notifyChanged();
      if (!mounted) return;
      // Sheet mode: pop the modal (Wolt owns the root-navigator route). Route
      // mode: reuse the same back-or-home fallback as the top bar's close
      // button, otherwise a directly deep-linked issue page — with no page
      // underneath to pop back to — leaves the user stranded on the now
      // deleted/archived issue after a plain `maybePop()` no-ops.
      if (widget.header != null) {
        Navigator.of(context).maybePop();
      } else {
        _closeRoute();
      }
    } on ApiFailure catch (failure) {
      _toast(failure.message);
    }
  }
}
