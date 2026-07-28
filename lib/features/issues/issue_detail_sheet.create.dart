part of 'issue_detail_sheet.dart';

// ─────────────────────────── Create body ───────────────────────────────────

/// Lifecycle of the create-issue save button, shared between the body (which
/// drives it) and the wolt sticky action bar (which renders it).
enum IssueCreatePhase { idle, saving, success }

/// Bridges [IssueCreateBody] and the sticky save bar: the body publishes the
/// current [phase] and the bar reads it; the bar calls [submit] on tap, which
/// runs the form validation (so the button stays pressable to surface errors).
class IssueCreateController extends ChangeNotifier {
  IssueCreatePhase _phase = IssueCreatePhase.idle;
  IssueCreatePhase get phase => _phase;
  set phase(IssueCreatePhase value) {
    if (value != _phase) {
      _phase = value;
      notifyListeners();
    }
  }

  /// Wired by the body in initState; invoked by the sticky save button.
  Future<void> Function()? submit;

  /// Wired by the body in initState; reports whether the form holds an
  /// unsaved title/description so the host can confirm before discarding it.
  bool Function()? hasDraft;
}

/// The same two-column layout as [IssueDetailBody], but for CREATING an issue:
/// title + Markdown description on the left, an editable details card
/// (project · status · assignee · priority · type · sprint · dates) on the
/// right. The save button lives in the wolt sticky action bar and is driven via
/// [IssueCreateController]. Hosted by `showIssueForm`.
class IssueCreateBody extends StatefulWidget {
  const IssueCreateBody({
    super.key,
    required this.controller,
    this.projectId,
    this.initialState,
    this.initialSprintId,
    this.parentId,
    this.forcedType,
    this.initialAssigneeId,
    required this.onCreated,
  });

  final IssueCreateController controller;
  final String? projectId;
  final String? initialState;
  final String? initialSprintId;

  /// Pre-selected parent issue (an epic for child issues, a standard issue for
  /// sub-tasks). When set, the parent row is locked.
  final String? parentId;

  /// Forces and locks the issue type (e.g. `STORY` for an epic's child,
  /// `SUBTASK` for a sub-task). When set, the Type row is locked.
  final String? forcedType;

  /// Pre-selected assignee (e.g. the lane's user under the assignee board
  /// grouping). Only seeds the field — it stays editable.
  final String? initialAssigneeId;

  final ValueChanged<Issue> onCreated;

  @override
  State<IssueCreateBody> createState() => IssueCreateBodyState();
}

class IssueCreateBodyState extends State<IssueCreateBody> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = HinataEditorController();

  List<Project> _projects = const [];
  List<DirectoryUser> _users = const [];
  List<Sprint> _sprints = const [];
  // Project issues (keyed by readable id) feed the description editor's
  // `@`-menu and resolve `{{issue:…}}` chips in the preview; KB articles come
  // from the shared seed. Reloaded whenever the selected project changes.
  Map<String, Issue> _projectIssues = const {};
  KnowledgeRepository get _knowledge => context.read<KnowledgeRepository>();
  IssueRepository get _issueApi => context.read<IssueRepository>();
  ProjectRepository get _projectApi => context.read<ProjectRepository>();
  SprintRepository get _sprintApi => context.read<SprintRepository>();
  UserRepository get _userApi => context.read<UserRepository>();

  String? _projectId;
  String? _state;
  final List<String> _assigneeIds = [];
  String _priority = 'NORMAL';
  String _type = 'TASK';
  String? _parentId;

  /// The chosen/loaded parent (epic) issue, so its chip renders without needing
  /// the whole project issue set in memory.
  Issue? _parentIssue;

  /// Debounces resolving the `{{issue:KEY}}` chips referenced by the description
  /// as the user types, so the preview resolves them without a project drain.
  Timer? _descRefsDebounce;
  String? _sprintId;
  int? _storyPoints;
  DateTime? _startDate;
  DateTime? _dueDate;
  List<String> _labels = const [];
  final Set<String> _deletedLabels = {};

  bool _loading = true;
  String? _error;

  // Bumped on every project(-scoped) load so a slow response from a previously
  // selected project can't land after a newer one and overwrite its sprints /
  // issues (rapid project switching in the picker).
  int _projectLoadGen = 0;

  // Validation stays silent until the first save attempt, then switches to
  // live (onUserInteraction) validation — Flutter's standard form pattern.
  final _formKey = GlobalKey<FormState>();
  bool _autovalidate = false;

  static const _none = '__none__';

  Project? get _project =>
      _projects.where((p) => p.id == _projectId).firstOrNull;
  Map<String, String> get _names => {
    for (final u in _users) u.id: u.displayName,
  };

  @override
  void initState() {
    super.initState();
    _projectId = widget.projectId;
    _state = widget.initialState;
    _sprintId = widget.initialSprintId;
    _parentId = widget.parentId;
    if (widget.initialAssigneeId != null) {
      _assigneeIds.add(widget.initialAssigneeId!);
    }
    if (widget.forcedType != null) _type = widget.forcedType!;
    widget.controller.submit = _save;
    widget.controller.hasDraft = () =>
        _titleCtrl.text.trim().isNotEmpty || _descCtrl.hasContent;
    _descCtrl.addListener(_onDescriptionChanged);
    _load();
  }

  @override
  void dispose() {
    _descRefsDebounce?.cancel();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _projectApi.projects(),
        _userApi.users(),
      ]);
      _projects = results[0] as List<Project>;
      _users = results[1] as List<DirectoryUser>;
      _projectId ??= _projects.firstOrNull?.id;
      // A forced parent (e.g. "add sub-task" / "add to epic") is passed by id —
      // resolve it once so its chip renders without a project-wide drain.
      if (widget.parentId != null) {
        try {
          _parentIssue = await _issueApi.issue(widget.parentId!);
        } catch (_) {
          /* the parent row falls back to a placeholder */
        }
      }
      await _loadProjectScoped();
      if (mounted) setState(() => _loading = false);
    } on ApiFailure catch (failure) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = failure.message;
        });
      }
    } catch (_) {
      // Never leave the body stuck on an eternal HiveLoader if something other
      // than an ApiFailure escapes (mapping error, race) — surface it instead.
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'errors.unexpected';
        });
      }
    }
  }

  /// Loads sprints + a default status for the selected project. The `@`-menu now
  /// fetches issue candidates from the backend on demand and `{{issue:…}}` chips
  /// resolve only the referenced keys, so this no longer drains the project's
  /// whole issue set.
  Future<void> _loadProjectScoped() async {
    _state ??= _project?.stateNames.firstOrNull;
    _sprints = const [];
    _projectIssues = const {};
    final pid = _projectId;
    final gen = ++_projectLoadGen;
    if (pid == null) return;
    try {
      final sprints = await _sprintApi.sprintsForProject(pid);
      if (gen != _projectLoadGen) return; // a newer project won the race
      _sprints = sprints;
    } catch (_) {
      if (gen == _projectLoadGen) _sprints = const [];
    }
    try {
      await _knowledge.init();
    } catch (_) {
      /* smart-link doc resolution falls back to "not found" */
    }
    // Resolve any issues already referenced by the draft description (e.g. a
    // pre-filled template); typed/picked ones resolve via the debounced listener.
    unawaited(_resolveDescriptionRefs());
  }

  /// Resolves the full issues the draft description links to that aren't
  /// already loaded, so their preview chips render — fetching only the
  /// referenced keys, never the whole project. Read from the document's smart
  /// links, which is where a reference lives now that it is a node.
  Future<void> _resolveDescriptionRefs() async {
    final keys = documentSmartLinks(
      _descCtrl.editor,
      SmartLinkKind.issue,
    ).toSet();
    final missing = keys.where((k) => !_projectIssues.containsKey(k)).toList();
    if (missing.isEmpty) return;
    try {
      final resolved = await _issueApi.resolveIssues(missing);
      if (!mounted || resolved.isEmpty) return;
      setState(() {
        _projectIssues = {
          ..._projectIssues,
          for (final i in resolved) i.readableId: i,
        };
      });
    } catch (_) {
      // Unresolved keys render as a plain token chip; non-fatal.
    }
  }

  /// Debounced trigger for [_resolveDescriptionRefs], wired to the description
  /// controller so chips resolve shortly after a mention is inserted/typed.
  void _onDescriptionChanged() {
    _descRefsDebounce?.cancel();
    _descRefsDebounce = Timer(
      const Duration(milliseconds: 300),
      _resolveDescriptionRefs,
    );
  }

  Future<void> _onProjectChanged(String id) async {
    setState(() {
      _projectId = id;
      _state = null; // reset to the new project's default
      _sprintId = null;
      // These are all project-scoped: a parent epic and labels from the old
      // project are meaningless (and invalid) in the new one. Clearing them
      // stops a stale cross-project parentId/tags being silently submitted while
      // the form visibly shows "no epic" / no labels.
      _parentId = null;
      _labels = const [];
      _deletedLabels.clear();
    });
    await _loadProjectScoped();
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    // Run the form validators; from now on validate live as the user types.
    final formValid = _formKey.currentState?.validate() ?? false;
    if (!_autovalidate) setState(() => _autovalidate = true);
    if (!formValid || _projectId == null) {
      if (_projectId == null) {
        setState(() => _error = context.t('errors.required'));
      }
      return;
    }
    final title = _titleCtrl.text.trim();
    widget.controller.phase = IssueCreatePhase.saving;
    setState(() => _error = null);
    try {
      final created = await _issueApi.createIssue({
        'projectId': _projectId,
        'title': title,
        'descriptionDoc': _descCtrl.doc,
        'type': _type,
        'priority': _priority,
        if (_state != null) 'state': _state,
        if (_assigneeIds.isNotEmpty) 'assigneeIds': _assigneeIds,
        if (_parentId != null) 'parentId': _parentId,
        if (_sprintId != null) 'sprintId': _sprintId,
        if (_storyPoints != null) 'storyPoints': _storyPoints,
        if (_startDate != null)
          'startDate': _startDate!.toIso8601String().substring(0, 10),
        if (_dueDate != null)
          'dueDate': _dueDate!.toIso8601String().substring(0, 10),
        if (_labels.isNotEmpty) 'tags': _labels,
      });
      if (!mounted) return;
      // Hold on the green check briefly before handing off to the detail view.
      widget.controller.phase = IssueCreatePhase.success;
      await Future<void>.delayed(const Duration(milliseconds: 750));
      // The user may have dismissed the sheet during the hold (barrier tap /
      // Esc / swipe-down) — the wolt page is then unmounted and onCreated would
      // pop a defunct context. Bail; the issue is already created server-side.
      if (!mounted) return;
      widget.onCreated(created);
    } on ApiFailure catch (failure) {
      if (mounted) {
        widget.controller.phase = IssueCreatePhase.idle;
        setState(() => _error = failure.message);
      }
    } catch (_) {
      // Any non-ApiFailure must still reset the save button out of its spinner,
      // otherwise it's stuck disabled forever (phase never returns to idle).
      if (mounted) {
        widget.controller.phase = IssueCreatePhase.idle;
        setState(() => _error = 'errors.unexpected');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: HiveLoader()),
      );
    }
    return SmartLinkScope(
      resolver: _buildResolver(),
      child: Form(
        key: _formKey,
        autovalidateMode: _autovalidate
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Padding(
          // Bottom clearance for the pinned save bar (which overlays the content):
          // ~save button + its padding + the device safe-area inset.
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            88 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, c) {
                  final left = _contentCard();
                  final right = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _detailsCard(),
                      const SizedBox(height: 14),
                      _timelineCard(),
                    ],
                  );
                  if (c.maxWidth >= 680) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: left),
                        const SizedBox(width: 18),
                        Expanded(flex: 2, child: right),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [left, const SizedBox(height: 14), right],
                  );
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  // ApiFailure.message can be an i18n key (e.g. 'errors.connection');
                  // context.t is idempotent for already-resolved strings.
                  context.t(_error!),
                  style: const TextStyle(color: AppColors.danger),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── smart-link wiring (mirrors IssueDetailBody) ──────────────────────────

  /// Resolver for the description editor's `@`-menu + preview chips: issues +
  /// people from the backend (project issues + directory users), articles from
  /// the shared KB seed. Rebuilt per frame (cheap) so it tracks the freshly
  /// loaded project issues / users.
  IssueLinkResolver _buildResolver() => IssueLinkResolver(
    issuesByReadable: _projectIssues,
    users: _users,
    knowledgeRepo: _knowledge,
    stateColorFor: (s) =>
        _projStateColor(_project, s) ?? AppColors.stateColor(s),
    onOpenIssue: _openLinkedIssue,
    onOpenDoc: _openArticle,
    searchIssues: (q) =>
        _issueApi.mentionSearch(projectId: _projectId, query: q),
  );

  /// Opens the real issue for a readable id (e.g. `HIN-12`): tries the loaded
  /// project issues first, then a backend search; silently ignores no match.
  Future<void> _openLinkedIssue(String readableId) async {
    var match = _projectIssues[readableId];
    if (match == null) {
      try {
        final res = await _issueApi.issues(query: readableId, size: 20);
        match = res.issues.where((i) => i.readableId == readableId).firstOrNull;
      } on ApiFailure {
        return;
      }
    }
    if (!mounted || match == null) return;
    await showIssueDetailSheet(context, issueId: match.id);
  }

  /// Opens a KB article (doc smart-link) on the `/knowledge/:id` route. The
  /// create modal stays mounted underneath so the draft isn't lost.
  void _openArticle(String articleId) =>
      GoRouter.of(context).push('/knowledge/$articleId');

  Widget _sectionLabel(String text) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      color: AppColors.inkFaint,
    ),
  );

  Widget _contentCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context.t('issues.title')),
        const SizedBox(height: 8),
        TextFormField(
          controller: _titleCtrl,
          maxLines: null,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(
            fontFamily: AppTheme.fontBrand,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            // height: 1.25,
          ),
          decoration: InputDecoration(
            hintText: context.t('issues.title'),
            errorStyle: const TextStyle(color: AppColors.danger, fontSize: 12),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 8,
            ),
          ),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? context.t('errors.required')
              : null,
        ),
        const SizedBox(height: 18),
        // Same authoring surface as the issue detail and the knowledge base.
        _sectionLabel(context.t('issues.description')),
        const SizedBox(height: 8),
        HinataEditor(
          controller: _descCtrl,
          fontSize: 14,
          minHeight: 140,
          trailing: hinataEditorTools(context, _descCtrl),
        ),
      ],
    );
  }

  Widget _detailsCard() {
    final sprintName = _sprints
        .where((s) => s.id == _sprintId)
        .firstOrNull
        ?.name;
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
          _DetailRow(
            label: context.t('issues.project'),
            onTap: _pickProject,
            child: Text(
              _project != null
                  ? '${_project!.key} – ${_project!.name}'
                  : context.t('errors.required'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          _DetailRow(
            label: context.t('issues.status'),
            onTap: (_project?.workflowStates.isEmpty ?? true)
                ? null
                : _pickStatus,
            child: _state != null
                ? StateDotBadge(
                    state: _state!,
                    color: _projStateColor(_project, _state!),
                  )
                : Text(
                    context.t('issues.noValue'),
                    style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
                  ),
          ),
          _DetailRow(
            label: context.t(
              _assigneeIds.length > 1 ? 'issues.assignees' : 'issues.assignee',
            ),
            onTap: _pickAssignee,
            child: _assigneeIds.isEmpty
                ? _person(null, fallback: context.t('issues.unassigned'))
                : _assigneeIds.length == 1
                ? _person(
                    _names[_assigneeIds.first],
                    fallback: context.t('issues.unassigned'),
                  )
                : HiveAvatarStack(
                    names: [for (final aid in _assigneeIds) _names[aid] ?? '?'],
                    size: 28,
                  ),
          ),
          _DetailRow(
            label: context.t('issues.priority'),
            onTap: _pickPriority,
            child: PriorityFlag(priority: _priority, withLabel: true),
          ),
          _DetailRow(
            // A forced type (epic child / sub-task) is locked.
            label: context.t('issues.type'),
            onTap: widget.forcedType != null ? null : _pickType,
            child: TypeBadge(type: _type),
          ),
          // Epic link for standard issues; sub-tasks arrive with a fixed parent.
          if (_type.toUpperCase() != 'EPIC') _createParentRow(),
          _DetailRow(
            label: context.t('issues.storyPoints'),
            onTap: _pickStoryPoints,
            child: _pointsValue(_storyPoints),
          ),
          _DetailRow(
            label: context.t('issues.label'),
            onTap: _pickLabels,
            child: _labels.isEmpty
                ? Text(
                    context.t('issues.noLabels'),
                    style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
                  )
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in _labels)
                        LabelTag(t, hue: _project?.hueForLabel(t)),
                    ],
                  ),
          ),
          _DetailRow(
            label: context.t('issues.sprint'),
            onTap: _sprints.isEmpty ? null : _pickSprint,
            last: true,
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
        ],
      ),
    );
  }

  /// The "Timeline" card for the create form: schedule (start / due dates).
  Widget _timelineCard() {
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('issues.timeline'),
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          _DetailRow(
            label: context.t('issues.startDate'),
            onTap: (_) => _pickDate(isStart: true),
            child: _dateValue(_startDate, isStart: true),
          ),
          _DetailRow(
            label: context.t('issues.dueDate'),
            onTap: (_) => _pickDate(isStart: false),
            last: true,
            child: _dateValue(_dueDate, isStart: false),
          ),
        ],
      ),
    );
  }

  /// Read-only display of the chosen story-point estimate.
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
          onTap: () => setState(() {
            if (isStart) {
              _startDate = null;
            } else {
              _dueDate = null;
            }
          }),
          child: Icon(LucideIcons.x, size: 15, color: AppColors.inkFaint),
        ),
      ],
    );
  }

  Future<void> _pickProject(Rect anchor) async {
    final chosen = await _pickOption<String>(
      context,
      title: context.t('issues.project'),
      anchorRect: anchor,
      options: [
        for (final p in _projects)
          (
            value: p.id,
            child: Text(
              '${p.key} – ${p.name}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
    if (chosen != null && chosen != _projectId) await _onProjectChanged(chosen);
  }

  Future<void> _pickStatus(Rect anchor) async {
    final states = _project?.stateNames ?? const <String>[];
    final chosen = await _pickOption<String>(
      context,
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
    if (chosen != null) setState(() => _state = chosen);
  }

  Future<void> _pickPriority(Rect anchor) async {
    const priorities = ['SHOWSTOPPER', 'CRITICAL', 'MAJOR', 'NORMAL', 'MINOR'];
    final chosen = await _pickOption<String>(
      context,
      title: context.t('issues.priority'),
      anchorRect: anchor,
      options: [
        for (final p in priorities)
          (value: p, child: PriorityFlag(priority: p, withLabel: true)),
      ],
    );
    if (chosen != null) setState(() => _priority = chosen);
  }

  Future<void> _pickType(Rect anchor) async {
    const types = ['STORY', 'TASK', 'BUG', 'FEATURE', 'EPIC'];
    final chosen = await _pickOption<String>(
      context,
      title: context.t('issues.type'),
      anchorRect: anchor,
      options: [for (final t in types) (value: t, child: TypeBadge(type: t))],
    );
    if (chosen != null) {
      setState(() {
        _type = chosen;
        // Epics never have a parent — drop any epic link when switching to one.
        if (chosen.toUpperCase() == 'EPIC') _parentId = null;
      });
    }
  }

  /// Epic (standard issue) / Parent (sub-task) row in the create form. Locked
  /// when the parent was forced by the launching panel.
  Widget _createParentRow() {
    final isSubtask = _type.toUpperCase() == 'SUBTASK';
    final parent = _parentId == null ? null : _parentIssue;
    final locked = widget.parentId != null;
    return _DetailRow(
      label: isSubtask ? context.t('issues.parent') : context.t('issues.epic'),
      onTap: (locked || isSubtask) ? null : _pickParent,
      child: parent == null
          ? Text(
              isSubtask ? '—' : context.t('issues.noEpic'),
              style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
            )
          : _createParentChip(parent),
    );
  }

  Future<void> _pickParent(Rect anchor) async {
    final pid = _projectId;
    if (pid == null) return;
    // Fetch the project's epics on demand (a bounded set) instead of filtering a
    // drained whole-project list.
    List<Issue> epics;
    try {
      final res = await _issueApi.issues(
        projectId: pid,
        types: const ['EPIC'],
        size: 100,
      );
      epics = res.issues.toList()
        ..sort((a, b) => a.readableId.compareTo(b.readableId));
    } on ApiFailure {
      epics = const [];
    }
    if (!mounted) return;
    final chosen = await _pickOption<String>(
      context,
      title: context.t('issues.epic'),
      anchorRect: anchor,
      options: [
        (
          value: _none,
          child: Text(
            context.t('issues.noEpic'),
            style: TextStyle(color: AppColors.inkFaint),
          ),
        ),
        for (final e in epics) (value: e.id, child: _createParentChip(e)),
      ],
    );
    if (chosen != null) {
      setState(() {
        _parentId = chosen == _none ? null : chosen;
        _parentIssue = chosen == _none
            ? null
            : epics.where((e) => e.id == chosen).firstOrNull;
      });
    }
  }

  Widget _createParentChip(Issue parent) => Row(
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

  Future<void> _pickLabels(Rect anchor) async {
    final pid = _projectId;
    final available = <String>{
      ...?_project?.labelNames,
      ..._labels,
    }.where((l) => !_deletedLabels.contains(l)).toList();
    final result = await showLabelPicker(
      context,
      anchor: anchor,
      available: available,
      selected: _labels.where((l) => !_deletedLabels.contains(l)).toList(),
      onDelete: pid == null
          ? null
          : (l) async {
              try {
                await _projectApi.deleteProjectLabel(pid, l);
              } on ApiFailure catch (failure) {
                if (mounted) {
                  showGlassErrorToast(context, context.t(failure.message));
                }
                return;
              } catch (_) {
                if (mounted) {
                  showGlassErrorToast(context, context.t('errors.unexpected'));
                }
                return;
              }
              _deletedLabels.add(l);
              if (mounted) {
                setState(() => _labels = _labels.where((x) => x != l).toList());
              }
            },
    );
    if (result != null) setState(() => _labels = result);
  }

  Future<void> _pickSprint(Rect anchor) async {
    final chosen = await _pickOption<String>(
      context,
      title: context.t('issues.sprint'),
      anchorRect: anchor,
      options: [
        (
          value: _none,
          child: Text(
            context.t('issues.noSprint'),
            style: TextStyle(color: AppColors.inkFaint),
          ),
        ),
        for (final s in _sprints) (value: s.id, child: Text(s.name)),
      ],
    );
    if (chosen != null) {
      setState(() => _sprintId = chosen == _none ? null : chosen);
    }
  }

  // Reuses the detail view's searchable people picker so assigning while
  // creating an issue scales past a handful of users: an anchored popover beside
  // the field on tablet/desktop, the bottom sheet on phones.
  Future<void> _pickAssignee(Rect anchor) async {
    final me = context.read<AuthBloc>().state.user;
    final multi =
        context.read<AppConfigBloc>().state.meta?.multiAssignee ?? false;
    final wide = MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint;
    Widget picker(BuildContext sheetContext) => _PeoplePicker(
      anchored: wide,
      users: _users,
      meId: me?.id,
      multiSelect: multi,
      initialSelected: _assigneeIds.toSet(),
      onSelectionChanged: (ids) => setState(() {
        _assigneeIds
          ..clear()
          ..addAll(ids);
      }),
      onUnassign: () {
        Navigator.of(sheetContext).pop();
        setState(_assigneeIds.clear);
      },
      onAssignMe: me == null
          ? null
          : () {
              Navigator.of(sheetContext).pop();
              setState(
                () => _assigneeIds
                  ..clear()
                  ..add(me.id),
              );
            },
      onSelect: (id) {
        Navigator.of(sheetContext).pop();
        setState(
          () => _assigneeIds
            ..clear()
            ..add(id),
        );
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
    await showGlassBottomSheet<void>(
      context,
      showHandle: false,
      builder: picker,
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart ? _startDate : _dueDate;
    final picked = await showGlassDatePicker(
      context,
      title: context.t(isStart ? 'issues.startDate' : 'issues.dueDate'),
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _dueDate = picked;
        }
      });
    }
  }

  // Anchor unused: estimate opens as a centered glass dialog, not a popover.
  Future<void> _pickStoryPoints(Rect anchor) async {
    final title = _titleCtrl.text.trim();
    final result = await showStoryPointsDialog(
      context,
      current: _storyPoints,
      subtitle: title.isEmpty ? context.t('issues.new') : title,
    );
    if (result != null) {
      setState(() => _storyPoints = result.points);
    }
  }
}
