import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/api_client.dart';
import '../i18n/i18n.dart';
import '../models/work_models.dart';
import '../repositories/project_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/hue_colors.dart';
import 'hive_loader.dart';
import 'hive_widgets.dart' show hiveEase;
import '../../features/sprint/modals/glass_modal.dart'
    show
        kGlassPopoverBreakpoint,
        showGlassAnchoredPopover,
        showGlassBottomSheet;

/// Opens the project picker anchored to [anchorRect] — the searchable,
/// server-paged counterpart to listing every project inline.
///
/// Mirrors the epic picker ([showEpicSearchPopover]): a search field, a
/// debounced paginated query and a responsive shell — an anchored dropdown on
/// wide screens, a glass bottom sheet on phones, where an anchored panel would
/// be buried under the keyboard.
///
/// Resolves to the picked projects (in pick order — a board's first project is
/// its template) or null when dismissed. In multi mode the choice is confirmed
/// with the footer button, so the picker doubles as the whole edit surface: the
/// caller can save straight from the result without wrapping it in a modal. In
/// single mode a tap picks and closes.
Future<List<Project>?> showProjectPicker(
  BuildContext context, {
  required Rect anchorRect,
  required Set<String> selected,
  required String titleKey,
  bool multi = true,
  String? excludeProjectId,
  List<Project> seed = const [],
  String? emptyLabelKey,
}) {
  // The popover is a root-navigator route, so it does not inherit the caller's
  // providers — hand the repository across explicitly.
  final repo = context.read<ProjectRepository>();
  Widget panel(bool sheet) => RepositoryProvider<ProjectRepository>.value(
    value: repo,
    child: _ProjectPickerPanel(
      selected: selected,
      multi: multi,
      excludeProjectId: excludeProjectId,
      seed: seed,
      emptyLabelKey: emptyLabelKey,
      titleKey: sheet ? titleKey : null,
    ),
  );

  if (MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint) {
    return showGlassAnchoredPopover<List<Project>>(
      context,
      anchorRect: anchorRect,
      width: 380,
      minHeight: 200,
      maxHeight: 440,
      builder: (_) => panel(false),
    );
  }
  // Sized to its content, capped so a long catalogue stays a sheet. A fixed
  // height left a slab of empty glass under the footer whenever the workspace
  // had few projects — the common case. Results do change per keystroke, so
  // AnimatedSize turns each debounced page into a motion rather than a jump.
  return showGlassBottomSheet<List<Project>>(
    context,
    builder: (_) => AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: hiveEase,
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 460),
        child: panel(true),
      ),
    ),
  );
}

/// One-line field that opens [showProjectPicker] — the same shape as the issue
/// sheet's epic row: current value, chevron, picker on tap.
///
/// Selected projects show as chips so the choice stays readable without opening
/// the picker; the count belongs above the field, in the label's trailing slot.
class ProjectPickerField extends StatelessWidget {
  const ProjectPickerField({
    super.key,
    required this.projects,
    required this.onTap,
    required this.placeholderKey,
  });

  /// The current selection, in pick order.
  final List<Project> projects;

  /// Receives the field's global rect so the picker anchors to it.
  final void Function(Rect anchorRect) onTap;

  /// i18n key for the empty state ("choose a project…").
  final String placeholderKey;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      onTap: () {
        final box = context.findRenderObject() as RenderBox?;
        final rect = (box != null && box.hasSize)
            ? box.localToGlobal(Offset.zero) & box.size
            : Rect.zero;
        onTap(rect);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          children: [
            Expanded(
              child: projects.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        context.t(placeholderKey),
                        style: TextStyle(
                          fontSize: 13.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  : Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final project in projects)
                          _ProjectChip(project: project),
                      ],
                    ),
            ),
            const SizedBox(width: 8),
            Icon(
              LucideIcons.chevronsUpDown,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectChip extends StatelessWidget {
  const _ProjectChip({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 9, 4),
      decoration: BoxDecoration(
        color: AppColors.canvas2.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: projectAccent(project),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            project.name,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          Text(
            project.key,
            style: TextStyle(
              fontSize: 10.5,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Picker body: search field, pinned selection, paged results, confirm footer.
///
/// Pages the server ([ProjectRepository.searchProjects]) rather than listing
/// every project — one page per request, more on scroll, filtering by name and
/// key in the database. The current selection is pinned above the results and
/// stays visible even while a search hides it: a picker that makes you scroll
/// back to find what you already chose is worse than the list it replaced.
class _ProjectPickerPanel extends StatefulWidget {
  const _ProjectPickerPanel({
    required this.selected,
    required this.multi,
    required this.excludeProjectId,
    required this.seed,
    required this.emptyLabelKey,
    required this.titleKey,
  });

  final Set<String> selected;
  final bool multi;
  final String? excludeProjectId;
  final List<Project> seed;
  final String? emptyLabelKey;

  /// Shown as a sheet header on phones; null in the anchored popover, where the
  /// field the user just tapped is still visible behind it.
  final String? titleKey;

  @override
  State<_ProjectPickerPanel> createState() => _ProjectPickerPanelState();
}

class _ProjectPickerPanelState extends State<_ProjectPickerPanel> {
  static const _debounceDelay = Duration(milliseconds: 180);
  static const _pageSize = 25;

  final _searchCtrl = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  Timer? _debounce;

  /// Working copy — the caller's selection only changes if the pick is
  /// confirmed, so dismissing the picker leaves the board untouched.
  late final Set<String> _picked = {...widget.selected};

  /// Every project seen so far, by id — the label source for pinned rows whose
  /// project is not on the current page.
  final Map<String, Project> _known = {};

  final List<Project> _results = [];

  /// Ids already in [_results] — a project can shift across a page boundary
  /// while paging, and the same row twice looks like a bug.
  final Set<String> _seen = {};

  String _query = '';
  int _page = 0;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;

  /// Set once the server hands back a short page. [_results] can legitimately
  /// stay below [_total] — an excluded project is dropped client-side — so the
  /// count alone would keep asking for a page that no longer exists.
  bool _exhausted = false;
  String? _error;

  /// Monotonic request token: a debounced search that lands after a newer one
  /// started is dropped, so a slow response can never overwrite fresh results.
  int _reqSeq = 0;

  bool get _hasMore => !_exhausted && _results.length < _total;

  @override
  void initState() {
    super.initState();
    for (final project in widget.seed) {
      _known[project.id] = project;
    }
    _scroll.addListener(_onScroll);
    // The search pill draws its own focus ring, so it has to repaint on focus.
    _focus.addListener(_onFocusChanged);
    _focus.requestFocus();
    _resolveSelected();
    _runSearch(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _searchCtrl.dispose();
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  /// Labels selected ids the caller did not seed — a board's stored span, for
  /// instance, which arrives as ids only.
  Future<void> _resolveSelected() async {
    final missing = _picked.where((id) => !_known.containsKey(id));
    if (missing.isEmpty) return;
    try {
      final resolved = await context.read<ProjectRepository>().resolveProjects(
        missing.toList(),
      );
      if (!mounted || resolved.isEmpty) return;
      setState(() {
        for (final project in resolved) {
          _known[project.id] = project;
        }
      });
    } on ApiFailure {
      // A pinned row falls back to being skipped — not worth an error surface
      // of its own while the list below still works.
    }
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () => _runSearch(reset: true));
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 100) {
      _runSearch(reset: false);
    }
  }

  Future<void> _runSearch({required bool reset}) async {
    if (reset) {
      _debounce?.cancel();
    } else if (_loadingMore || _loading || !_hasMore) {
      return;
    }

    final seq = ++_reqSeq;
    final page = reset ? 0 : _page + 1;
    final query = _query.trim();

    setState(() {
      if (reset) {
        _loading = true;
      } else {
        _loadingMore = true;
      }
      _error = null;
    });

    try {
      final result = await context.read<ProjectRepository>().searchProjects(
        query: query.isEmpty ? null : query,
        page: page,
        size: _pageSize,
      );
      if (!mounted || seq != _reqSeq) return;
      setState(() {
        if (reset) {
          _results.clear();
          _seen.clear();
        }
        for (final project in result.projects) {
          _known[project.id] = project;
          if (project.id == widget.excludeProjectId) continue;
          if (_seen.add(project.id)) _results.add(project);
        }
        _page = page;
        _total = result.total;
        _exhausted = result.projects.length < _pageSize;
        _loading = false;
        _loadingMore = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted || seq != _reqSeq) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = failure.message;
      });
    }
  }

  /// The picked projects, in the order they were picked. Ids that could not be
  /// labelled are skipped rather than rendered as a placeholder row.
  List<Project> get _pinned => [
    for (final id in _picked)
      if (id != widget.excludeProjectId && _known[id] != null) _known[id]!,
  ];

  void _onRowTap(Project project) {
    if (!widget.multi) {
      Navigator.of(context).pop([project]);
      return;
    }
    setState(() {
      if (!_picked.remove(project.id)) _picked.add(project.id);
    });
  }

  void _confirm() => Navigator.of(context).pop(_pinned);

  @override
  Widget build(BuildContext context) {
    final pinned = _pinned;
    final pinnedIds = {for (final project in pinned) project.id};
    final rest = [
      for (final project in _results)
        if (!pinnedIds.contains(project.id)) project,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.titleKey != null) _sheetTitle(),
        _searchField(),
        Flexible(child: _list(pinned, rest)),
        if (widget.multi) ...[
          Divider(height: 1, thickness: 1, color: AppColors.hairline2),
          _footer(),
        ],
      ],
    );
  }

  Widget _sheetTitle() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
    child: Text(
      context.t(widget.titleKey!),
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    ),
  );

  /// Search row drawn as an inset glass pill rather than a `TextField` with the
  /// app's input decoration: that theme fills opaquely, which on the glass panel
  /// reads as a separate dark bar stuck on top instead of part of the surface.
  /// So the field itself is collapsed (no fill, no border) and the pill around
  /// it is a translucent tint with a hairline that warms to the accent on focus.
  Widget _searchField() {
    final focused = _focus.hasFocus;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: focused ? 0.4 : 0.26),
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(
            color: focused ? AppColors.accent : AppColors.hairline2,
            width: focused ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.search,
              size: 16,
              color: focused ? AppColors.accentStrong : AppColors.textSecondary,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                focusNode: _focus,
                onChanged: _onQueryChanged,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 13.5),
                cursorColor: AppColors.accentStrong,
                // Every border state is cleared by hand: the app's input theme
                // supplies `enabledBorder`/`focusedBorder`, and those survive
                // `InputDecoration.collapsed` (which only clears `border`) —
                // that is what drew a second rounded box inside the pill.
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  hintText: context.t('projects.picker.searchHint'),
                  hintStyle: TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            if (_query.isNotEmpty)
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  _searchCtrl.clear();
                  _onQueryChanged('');
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    LucideIcons.x,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    final canConfirm = _picked.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.t(
                'board.projectsSelected',
                variables: {'count': '${_picked.length}'},
              ),
              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
          ),
          TextButton.icon(
            onPressed: canConfirm ? _confirm : null,
            icon: const Icon(LucideIcons.check, size: 15),
            label: Text(context.t('common.apply')),
          ),
        ],
      ),
    );
  }

  Widget _list(List<Project> pinned, List<Project> rest) {
    if (_loading && _results.isEmpty && pinned.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 26),
        child: Center(child: HiveLoader(size: 18)),
      );
    }
    if (_error != null && _results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Text(
          context.t(_error!),
          style: const TextStyle(fontSize: 12.5, color: AppColors.danger),
        ),
      );
    }

    // One flat list so pinned rows and results scroll together: a section header
    // that stayed put while its rows moved would read as a filter, not a group.
    final rows = <Widget>[
      if (pinned.isNotEmpty) ...[
        _SectionLabel(text: context.t('projects.picker.selected')),
        for (final project in pinned)
          _ProjectRow(
            project: project,
            selected: true,
            // Deselecting the last project would leave a board spanning
            // nothing, which the server rejects — so don't offer it.
            enabled: widget.multi ? _picked.length > 1 : false,
            multi: widget.multi,
            onTap: () => _onRowTap(project),
          ),
      ],
      if (rest.isNotEmpty || _loadingMore)
        _SectionLabel(
          text: context.t(
            _query.trim().isEmpty
                ? 'projects.picker.all'
                : 'projects.picker.results',
          ),
        ),
      for (final project in rest)
        _ProjectRow(
          project: project,
          selected: _picked.contains(project.id),
          enabled: true,
          multi: widget.multi,
          onTap: () => _onRowTap(project),
        ),
      if (rest.isEmpty && !_loading && !_loadingMore)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Text(
            context.t(
              _query.trim().isEmpty && pinned.isEmpty
                  ? (widget.emptyLabelKey ?? 'projects.picker.noResults')
                  : 'projects.picker.noResults',
            ),
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
        ),
      if (_loadingMore)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Center(child: HiveLoader(size: 15)),
        ),
    ];

    return ListView.builder(
      controller: _scroll,
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: rows.length,
      itemBuilder: (_, index) => rows[index],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.project,
    required this.selected,
    required this.enabled,
    required this.multi,
    required this.onTap,
  });

  final Project project;
  final bool selected;
  final bool enabled;
  final bool multi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final IconData mark = multi
        ? (selected ? LucideIcons.squareCheck : LucideIcons.square)
        : (selected ? LucideIcons.circleCheck : LucideIcons.circle);
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            Icon(
              mark,
              size: 18,
              color: selected
                  ? AppColors.accentStrong
                  : AppColors.textSecondary.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 10),
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: projectAccent(project),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                project.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: enabled
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
            ),
            Text(
              project.key,
              style: TextStyle(
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A project's accent colour: the configured hex, falling back to the hue of its
/// first workflow state so every project stays distinguishable. The same signal
/// the board cards use, so a pick made here is recognisable on the board.
Color projectAccent(Project project) {
  final hex = project.color.replaceFirst('#', '');
  final value = int.tryParse(hex, radix: 16);
  if (value != null && hex.length == 6) return Color(0xFF000000 | value);
  final states = project.workflowStates;
  return states.isEmpty ? AppColors.accent : hueColor(states.first.hue);
}
