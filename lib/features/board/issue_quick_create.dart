import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/repositories/user_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_widgets.dart';
import '../sprint/modals/glass_modal.dart';
import 'package:hinata/core/widgets/user_pronouns.dart';

/// Issue types the quick composer offers. Mirrors the full create form minus
/// `SUBTASK`, which never gets picked — it arrives forced by a sub-task lane.
const List<String> kQuickCreateTypes = [
  'STORY',
  'TASK',
  'BUG',
  'FEATURE',
  'EPIC',
];

/// What a quick-created issue inherits from the place it is created in: the
/// column's project + workflow state, the sprint of the section, the lane's
/// epic/parent and assignee. Everything here is a pre-fill — the composer's own
/// controls still win.
class IssueQuickCreateSeed {
  const IssueQuickCreateSeed({
    this.projects = const [],
    this.stateFor,
    this.sprintId,
    this.parentId,
    this.forcedType,
    this.assigneeId,
    this.assigneeName,
    this.assigneeAvatarUrl,
  });

  /// The projects this spot can create into. One on an ordinary board; several
  /// on a merged board, where the composer shows a project control so a ticket
  /// can't land in the wrong project unnoticed.
  final List<Project> projects;

  /// The workflow state the chosen project should start in — the column's own
  /// state. Returns null where the spot carries no state (a backlog section),
  /// leaving the server to pick the project's default.
  final String? Function(Project project)? stateFor;

  final String? sprintId;

  /// Pre-selected parent: the lane's epic, or the parent issue of a sub-task
  /// lane. Not editable here.
  final String? parentId;

  /// Locks the type (e.g. `SUBTASK` inside a sub-task lane) — the type control
  /// still shows the glyph but stops responding.
  final String? forcedType;

  /// Pre-selected assignee (the lane's person under the assignee grouping).
  /// [assigneeName] / [assigneeAvatarUrl] only render its avatar; the picker
  /// replaces all three.
  final String? assigneeId;
  final String? assigneeName;
  final String? assigneeAvatarUrl;

  Project? get onlyProject => projects.length == 1 ? projects.first : null;
}

/// The "add issue" affordance at the foot of a board column / planning section.
///
/// Collapsed it is the dashed [DottedAddButton] it replaces; tapped it becomes
/// an inline composer — title, type, due date, assignee, submit — so a ticket
/// can be written without leaving the board. Enter creates, Escape closes;
/// anything the composer doesn't cover is edited afterwards on the card.
///
/// The composer closes on every successful create (the new card lands in the
/// column behind it) and reports the created issue via [onCreated] so the host
/// can reload.
class IssueQuickCreate extends StatefulWidget {
  const IssueQuickCreate({
    super.key,
    required this.label,
    required this.seed,
    required this.onCreated,
    this.dimmed = false,
  });

  final String label;
  final IssueQuickCreateSeed seed;
  final ValueChanged<Issue> onCreated;

  /// Fades the collapsed button out — board columns only reveal it on hover.
  /// An open composer is never dimmed: it holds the user's draft.
  final bool dimmed;

  @override
  State<IssueQuickCreate> createState() => _IssueQuickCreateState();
}

class _IssueQuickCreateState extends State<IssueQuickCreate> {
  final _titleCtrl = TextEditingController();
  late final FocusNode _titleFocus = FocusNode(onKeyEvent: _onTitleKey);

  bool _open = false;
  bool _saving = false;

  /// Suppresses the tap-outside close while one of the composer's own pickers
  /// is up: those open on the root navigator, so every tap inside them counts
  /// as a tap outside the composer.
  bool _pickerBusy = false;

  late String _type;
  String? _projectId;
  String? _assigneeId;
  String? _assigneeName;
  String? _assigneeAvatarUrl;
  DateTime? _dueDate;

  IssueRepository get _issueApi => context.read<IssueRepository>();

  @override
  void initState() {
    super.initState();
    _resetFields();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  void _resetFields() {
    final seed = widget.seed;
    _type = seed.forcedType ?? 'TASK';
    _projectId = seed.projects.firstOrNull?.id;
    _assigneeId = seed.assigneeId;
    _assigneeName = seed.assigneeName;
    _assigneeAvatarUrl = seed.assigneeAvatarUrl;
    _dueDate = null;
    _titleCtrl.clear();
  }

  Project? get _project =>
      widget.seed.projects.where((p) => p.id == _projectId).firstOrNull;

  bool get _canSubmit => !_saving && _titleCtrl.text.trim().isNotEmpty;

  void _expand() {
    // Read the seed fresh on every open: the lane/column behind this composer
    // may have been re-seeded by a board reload while it sat closed.
    setState(() {
      _resetFields();
      _open = true;
    });
    // The field mounts with this frame; ask for focus once it exists.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _open) _titleFocus.requestFocus();
    });
  }

  void _collapse() {
    if (!mounted) return;
    _titleFocus.unfocus();
    setState(() {
      _open = false;
      _resetFields();
    });
  }

  /// Hardware-keyboard shortcuts on the title field: Enter creates (Shift+Enter
  /// still breaks the line), Escape closes. Lives on the field's own focus node
  /// so it runs before the editable turns Enter into a newline.
  KeyEventResult _onTitleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _collapse();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        return KeyEventResult.ignored;
      }
      unawaited(_submit());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Runs [action] with the tap-outside guard raised, so the picker it opens
  /// can't close the composer underneath it.
  Future<T?> _withPicker<T>(Future<T?> Function() action) async {
    _pickerBusy = true;
    try {
      return await action();
    } finally {
      // Release a frame later: the dismissing tap on the barrier still arrives
      // after the route pops.
      WidgetsBinding.instance.addPostFrameCallback((_) => _pickerBusy = false);
    }
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    final projectId = _projectId;
    if (title.isEmpty || projectId == null || _saving) return;
    setState(() => _saving = true);
    final project = _project;
    final state = project == null ? null : widget.seed.stateFor?.call(project);
    final assigneeId = _assigneeId;
    final dueDate = _dueDate;
    try {
      final created = await _issueApi.createIssue({
        'projectId': projectId,
        'title': title,
        'type': _type,
        'priority': 'NORMAL',
        'state': ?state,
        'sprintId': ?widget.seed.sprintId,
        'parentId': ?widget.seed.parentId,
        if (assigneeId != null) 'assigneeIds': [assigneeId],
        // Date-only field: the calendar day the user picked, never shifted
        // through a timezone.
        if (dueDate != null)
          'dueDate': dueDate.toIso8601String().substring(0, 10),
      });
      if (!mounted) return;
      setState(() => _saving = false);
      _collapse();
      widget.onCreated(created);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _saving = false);
      // The draft stays in the composer — a failed create must not eat it.
      showGlassErrorToast(context, context.t(failure.message));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showGlassErrorToast(context, context.t('errors.unexpected'));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_open) {
      return AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        opacity: widget.dimmed ? 0 : 1,
        child: IgnorePointer(
          ignoring: widget.dimmed,
          child: DottedAddButton(label: widget.label, onTap: _expand),
        ),
      );
    }
    return TapRegion(
      onTapOutside: (_) {
        // Only an empty composer gets closed by a stray tap; a written draft is
        // dismissed deliberately (Escape) or by creating it.
        if (!_pickerBusy && !_saving && _titleCtrl.text.trim().isEmpty) {
          _collapse();
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(color: AppColors.accent, width: 2),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleCtrl,
              focusNode: _titleFocus,
              // Opens two lines tall so a title of any normal length has its
              // room already claimed — the card grows from there rather than
              // jolting the toolbar down on the first wrap. Past eight lines
              // the field scrolls instead of pushing the column apart.
              minLines: 2,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              // readOnly, not disabled: a disabled field drops focus, and a
              // failed create would hand the draft back with the caret gone.
              readOnly: _saving,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: context.t('board.quickCreateHint'),
                hintStyle: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.inkFaint,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _toolbar(),
          ],
        ),
      ),
    );
  }

  Widget _toolbar() => Row(
    children: [
      if (widget.seed.projects.length > 1) ...[
        _projectTool(),
        const SizedBox(width: 6),
      ],
      _typeTool(),
      const SizedBox(width: 4),
      _dueDateTool(),
      const SizedBox(width: 4),
      _assigneeTool(),
      const Spacer(),
      _submitButton(),
    ],
  );

  // ── project (merged boards only) ──────────────────────────────────────────

  Widget _projectTool() => _QuickTool(
    tooltip: context.t('issues.project'),
    onTap: _saving ? null : _pickProject,
    child: Text(
      _project?.key ?? '—',
      style: TextStyle(
        fontFamily: AppTheme.fontMono,
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: AppColors.inkSoft,
      ),
    ),
  );

  Future<void> _pickProject(Rect anchor) async {
    final chosen = await _withPicker(
      () => showGlassOptions<String>(
        context,
        title: context.t('issues.project'),
        anchorRect: anchor,
        options: [
          for (final p in widget.seed.projects)
            (
              value: p.id,
              child: Text(
                '${p.key} – ${p.name}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
    if (chosen != null && mounted) setState(() => _projectId = chosen);
  }

  // ── type ──────────────────────────────────────────────────────────────────

  Widget _typeTool() {
    final locked = widget.seed.forcedType != null;
    return _QuickTool(
      tooltip: context.t('issues.type'),
      onTap: (locked || _saving) ? null : _pickType,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TypeGlyph(type: _type, size: 19),
          if (!locked) ...[
            const SizedBox(width: 3),
            Icon(LucideIcons.chevronDown, size: 14, color: AppColors.inkFaint),
          ],
        ],
      ),
    );
  }

  Future<void> _pickType(Rect anchor) async {
    final chosen = await _withPicker(
      () => showGlassOptions<String>(
        context,
        title: context.t('issues.type'),
        anchorRect: anchor,
        options: [
          for (final t in kQuickCreateTypes)
            (value: t, child: TypeBadge(type: t)),
        ],
      ),
    );
    if (chosen != null && mounted) setState(() => _type = chosen);
  }

  // ── due date ──────────────────────────────────────────────────────────────

  /// Stays an icon whether or not a date is set — a column is narrow, and the
  /// date spelled out here pushed the toolbar past the card's width. A set date
  /// shows as the honey tint every other active control in this toolbar uses;
  /// the exact day lives in the picker (and afterwards on the card).
  Widget _dueDateTool() {
    final due = _dueDate;
    return _QuickTool(
      tooltip: due == null
          ? context.t('issues.dueDate')
          : '${context.t('issues.dueDate')}: '
                '${MaterialLocalizations.of(context).formatShortDate(due)}',
      active: due != null,
      onTap: _saving ? null : _pickDueDate,
      child: Icon(
        LucideIcons.calendarDays,
        size: 17,
        color: due != null ? AppColors.accentStrong : AppColors.inkSoft,
      ),
    );
  }

  Future<void> _pickDueDate(Rect anchor) async {
    final title = context.t('issues.dueDate');
    final initial = _dueDate ?? DateTime.now();
    final first = DateTime(2015);
    final last = DateTime(2100);
    // Without the inline date chip there is no × to clear on, so the way back
    // out lives in the calendar itself.
    final onClear = _dueDate == null
        ? null
        : () {
            if (mounted) setState(() => _dueDate = null);
          };
    // Anchored beside the control where there is room for it; on a phone the
    // calendar needs the whole modal, so it keeps the sheet.
    final wide = MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint;
    final picked = await _withPicker(
      () => wide
          ? showGlassDatePopover(
              context,
              anchorRect: anchor,
              title: title,
              initialDate: initial,
              firstDate: first,
              lastDate: last,
              onClear: onClear,
            )
          : showGlassDatePicker(
              context,
              title: title,
              initialDate: initial,
              firstDate: first,
              lastDate: last,
              onClear: onClear,
            ),
    );
    if (picked != null && mounted) setState(() => _dueDate = picked);
  }

  // ── assignee ──────────────────────────────────────────────────────────────

  Widget _assigneeTool() {
    final name = _assigneeName;
    return _QuickTool(
      tooltip: context.t('issues.assignee'),
      active: _assigneeId != null,
      padding: const EdgeInsets.all(3),
      onTap: _saving ? null : _pickAssignee,
      child: _assigneeId != null && name != null
          ? HiveAvatar(name: name, imageUrl: _assigneeAvatarUrl, size: 22)
          : Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(LucideIcons.user, size: 13, color: AppColors.inkSoft),
            ),
    );
  }

  Future<void> _pickAssignee(Rect anchor) async {
    final wide = MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint;
    final me = context.read<AuthBloc>().state.user;
    // The picker is pushed on the root navigator, which sits above the
    // repository providers — hand it the directory rather than let it look one
    // up through a context that no longer reaches them.
    final directory = context.read<UserRepository>();
    Widget picker(BuildContext hostContext) => _QuickPeoplePicker(
      directory: directory,
      anchored: wide,
      meId: me?.id,
      selectedId: _assigneeId,
      onPicked: (user) {
        Navigator.of(hostContext).pop();
        if (!mounted) return;
        setState(() {
          _assigneeId = user?.id;
          _assigneeName = user?.displayName;
          _assigneeAvatarUrl = user?.avatarUrl;
        });
      },
    );

    await _withPicker(
      () => wide
          ? showGlassAnchoredPopover<void>(
              context,
              anchorRect: anchor,
              width: 320,
              maxHeight: 420,
              builder: picker,
            )
          : showGlassBottomSheet<void>(
              context,
              showHandle: false,
              builder: picker,
            ),
    );
  }

  // ── submit ────────────────────────────────────────────────────────────────

  Widget _submitButton() {
    final enabled = _canSubmit;
    return Tooltip(
      message: context.t('board.quickCreateSubmit'),
      child: Material(
        color: enabled ? AppColors.accent : AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: InkWell(
          onTap: enabled ? () => unawaited(_submit()) : null,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          child: SizedBox(
            width: 38,
            height: 30,
            child: Center(
              child: _saving
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.inkSoft,
                      ),
                    )
                  : Icon(
                      LucideIcons.cornerDownLeft,
                      size: 16,
                      color: enabled
                          ? const Color(0xFF2A2410)
                          : AppColors.inkFaint,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One control in the composer's toolbar: a small rounded hit target that hands
/// its own global rect to [onTap], so the picker it opens anchors beside it.
class _QuickTool extends StatefulWidget {
  const _QuickTool({
    required this.child,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
  });

  final Widget child;
  final String tooltip;
  final void Function(Rect anchor)? onTap;
  final bool active;
  final EdgeInsets padding;

  @override
  State<_QuickTool> createState() => _QuickToolState();
}

class _QuickToolState extends State<_QuickTool> {
  final _key = GlobalKey();
  bool _hovered = false;

  Rect get _anchor {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Rect.zero;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final border = widget.active || _hovered
        ? AppColors.accentLine
        : Colors.transparent;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: enabled ? () => widget.onTap!(_anchor) : null,
          behavior: HitTestBehavior.opaque,
          child: Container(
            key: _key,
            padding: widget.padding,
            decoration: BoxDecoration(
              color: widget.active ? AppColors.accentSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(color: border),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Searchable single-person picker for the composer. Types ahead against the
/// directory endpoint (server-side, paged) rather than loading every user, so it
/// stays usable in a large organisation.
class _QuickPeoplePicker extends StatefulWidget {
  const _QuickPeoplePicker({
    required this.directory,
    required this.anchored,
    required this.meId,
    required this.selectedId,
    required this.onPicked,
  });

  /// Passed in rather than read off the context: this picker lives on the root
  /// navigator, above the repository providers.
  final UserRepository directory;

  /// Wide screens host this in an anchored popover, which sizes itself; phones
  /// host it in a bottom sheet, which needs the picker to claim a height.
  final bool anchored;
  final String? meId;
  final String? selectedId;

  /// Fires with the chosen user, or null for "unassigned".
  final ValueChanged<DirectoryUser?> onPicked;

  @override
  State<_QuickPeoplePicker> createState() => _QuickPeoplePickerState();
}

class _QuickPeoplePickerState extends State<_QuickPeoplePicker> {
  static const _pageSize = 25;

  final _scroll = ScrollController();
  Timer? _debounce;

  String _query = '';
  List<DirectoryUser> _users = const [];
  int _total = 0;
  int _page = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  /// Guards against a slow response for an older query overwriting a newer one.
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_search());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loadingMore || _users.length >= _total) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 120) {
      unawaited(_loadMore());
    }
  }

  void _onQueryChanged(String value) {
    _query = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _search());
  }

  Future<void> _search() async {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.directory.searchUsers(
        _query.trim(),
        size: _pageSize,
      );
      if (!mounted || gen != _gen) return;
      setState(() {
        _users = res.items;
        _total = res.total;
        _page = 0;
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _loadMore() async {
    final gen = _gen;
    setState(() => _loadingMore = true);
    try {
      final res = await widget.directory.searchUsers(
        _query.trim(),
        page: _page + 1,
        size: _pageSize,
      );
      if (!mounted || gen != _gen) return;
      setState(() {
        _users = [..._users, ...res.items];
        _total = res.total;
        _page += 1;
        _loadingMore = false;
      });
    } on ApiFailure {
      if (mounted && gen == _gen) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      // "Unassigned" leads the list — the board's own default, and the only way
      // back once someone has been picked.
      ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 15,
          backgroundColor: AppColors.surfaceMuted,
          child: Icon(LucideIcons.user, size: 15, color: AppColors.inkSoft),
        ),
        title: Text(context.t('issues.unassigned')),
        selected: widget.selectedId == null,
        onTap: () => widget.onPicked(null),
      ),
    ];

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            autofocus: true,
            onChanged: _onQueryChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(LucideIcons.search, size: 18),
              hintText: context.t('issues.searchPeople'),
              filled: true,
              fillColor: AppColors.surfaceMuted,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                borderSide: BorderSide(color: AppColors.hairline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                borderSide: BorderSide(color: AppColors.hairline),
              ),
            ),
          ),
        ),
        // Anchored: the popover panel bounds the height, so the list flexes into
        // it. Sheet: nothing bounds it, so the wrapper below claims a height and
        // the list fills that.
        Flexible(
          fit: widget.anchored ? FlexFit.loose : FlexFit.tight,
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      context.t(_error!),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.inkFaint),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  shrinkWrap: widget.anchored,
                  padding: const EdgeInsets.only(bottom: 6),
                  itemCount:
                      rows.length +
                      (_users.isEmpty ? 1 : _users.length) +
                      (_loadingMore ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i < rows.length) return rows[i];
                    final index = i - rows.length;
                    if (_users.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
                        child: Center(
                          child: Text(
                            context.t('issues.noPeopleFound'),
                            style: TextStyle(color: AppColors.inkFaint),
                          ),
                        ),
                      );
                    }
                    if (index >= _users.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    final user = _users[index];
                    final isMe = user.id == widget.meId;
                    return ListTile(
                      dense: true,
                      leading: HiveAvatar(
                        name: user.displayName,
                        imageUrl: user.avatarUrl,
                        size: 30,
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              user.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 6),
                            Text(
                              context.t('issues.assignToMe'),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppColors.inkFaint,
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        userHandle(user.username),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      selected: user.id == widget.selectedId,
                      onTap: () => widget.onPicked(user),
                    );
                  },
                ),
        ),
      ],
    );
    if (widget.anchored) return body;
    // The glass bottom sheet sizes to its child, so the picker claims the same
    // share of the screen as the issue-detail people picker it mirrors.
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.62,
      child: body,
    );
  }
}

/// Dashed "Add issue" button — the collapsed state of [IssueQuickCreate], and
/// the plain add affordance wherever a composer doesn't fit.
class DottedAddButton extends StatefulWidget {
  const DottedAddButton({super.key, required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  State<DottedAddButton> createState() => _DottedAddButtonState();
}

class _DottedAddButtonState extends State<DottedAddButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.radiusControl);
    final accent = _hovered ? AppColors.accentStrong : AppColors.inkFaint;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: radius,
            color: _hovered ? AppColors.accentSoft : null,
          ),
          child: CustomPaint(
            painter: _DashedBorderPainter(
              color: _hovered ? AppColors.accent : AppColors.hairline,
              radius: AppTheme.radiusControl,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.plus, size: 15, color: accent),
                  const SizedBox(width: 7),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a rounded-rectangle border made of evenly spaced dashes.
class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;
  static const double dashWidth = 5;
  static const double dashGap = 4;
  static const double strokeWidth = 1.3;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const inset = strokeWidth / 2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        inset,
        inset,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dashWidth, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
