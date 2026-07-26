import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/board_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/project_picker.dart' show projectAccent;
import '../sprint/modals/glass_modal.dart';

/// Arranges a board's columns by hand.
///
/// The automatic merge folds equivalent workflow states of the spanned projects
/// into shared columns and orders them from every project's own sequence. That
/// gets the common cases right, but it can only ever guess — two projects may
/// name the same step differently, or split one step into two. This is the
/// escape hatch: name the columns, decide which status of which project belongs
/// to which, and reorder them.
///
/// Two rules the server also enforces, because the board depends on them:
/// every status needs exactly one column (otherwise its issues would silently
/// disappear from the wall), and no column may hold two statuses of the *same*
/// project (a drop resolves the status from the card's own project and would
/// have no way to choose).
///
/// Returns true when the layout was saved or reset, so the caller can reload.
Future<bool?> showBoardColumnsEditor(BuildContext context, AgileBoard board) {
  final boardRepo = context.read<BoardRepository>();
  final projectRepo = context.read<ProjectRepository>();
  return showGlassModal<bool>(
    context,
    width: 640,
    builder: (_) => MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: boardRepo),
        RepositoryProvider.value(value: projectRepo),
      ],
      child: _ColumnsEditorBody(board: board),
    ),
  );
}

/// A status name together with every project that defines it — the unit the
/// editor moves around.
///
/// Grouping by name matters: a column collects states by name, so "Open" of two
/// projects is one thing here and lands in one column. It also decides where a
/// group may go — a column already serving a project cannot take a second group
/// that belongs to it.
class _StateGroup {
  _StateGroup(this.name) : projects = [];

  final String name;
  final List<Project> projects;

  String get lower => name.toLowerCase();
}

class _ColumnsEditorBody extends StatefulWidget {
  const _ColumnsEditorBody({required this.board});

  final AgileBoard board;

  @override
  State<_ColumnsEditorBody> createState() => _ColumnsEditorBodyState();
}

class _ColumnsEditorBodyState extends State<_ColumnsEditorBody> {
  List<Project> _projects = const [];
  List<_Draft> _columns = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final column in _columns) {
      column.dispose();
    }
    super.dispose();
  }

  /// Loads the board's current layout and the projects behind it. The view is
  /// the honest source: it already reflects renames and states added since a
  /// hand-made layout was stored.
  Future<void> _load() async {
    final boardRepo = context.read<BoardRepository>();
    final projectRepo = context.read<ProjectRepository>();
    try {
      final view = await boardRepo.boardView(widget.board.id);
      final projects = await projectRepo.resolveProjects(
        widget.board.projectIds,
      );
      if (!mounted) return;
      setState(() {
        _projects = projects;
        _columns = [
          for (final column in view.columns)
            _Draft(
              name: column.name,
              states: [...column.states],
              wipLimit: column.wipLimit,
            ),
        ];
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  /// Every distinct status name across the spanned projects, in project order,
  /// each carrying the projects that define it.
  List<_StateGroup> get _groups {
    final byName = <String, _StateGroup>{};
    final ordered = <_StateGroup>[];
    for (final project in _projects) {
      for (final state in project.workflowStates) {
        final group = byName.putIfAbsent(state.name.toLowerCase(), () {
          final fresh = _StateGroup(state.name);
          ordered.add(fresh);
          return fresh;
        });
        group.projects.add(project);
      }
    }
    return ordered;
  }

  /// Status names that no column collects yet.
  List<_StateGroup> get _unassigned {
    final taken = <String>{
      for (final column in _columns)
        for (final state in column.states) state.toLowerCase(),
    };
    return [
      for (final group in _groups)
        if (!taken.contains(group.lower)) group,
    ];
  }

  _StateGroup? _groupFor(String state) {
    for (final group in _groups) {
      if (group.lower == state.toLowerCase()) return group;
    }
    return null;
  }

  /// Projects a column already serves. It may serve each project only once —
  /// a second status of the same project would leave a drop without a single
  /// target, which is what the server rejects too.
  Set<String> _projectsIn(_Draft column) {
    final ids = <String>{};
    for (final state in column.states) {
      final group = _groupFor(state);
      if (group == null) continue;
      for (final project in group.projects) {
        ids.add(project.id);
      }
    }
    return ids;
  }

  bool get _complete =>
      _unassigned.isEmpty &&
      _columns.isNotEmpty &&
      _columns.every((c) => c.controller.text.trim().isNotEmpty);

  Future<void> _assign(_StateGroup group) async {
    final groupProjects = {for (final p in group.projects) p.id};
    final options = <({int value, Widget child})>[
      for (var i = 0; i < _columns.length; i++)
        if (_projectsIn(_columns[i]).intersection(groupProjects).isEmpty)
          (
            value: i,
            child: Text(
              _columns[i].controller.text.trim().isEmpty
                  ? context.t('board.columns.unnamed')
                  : _columns[i].controller.text.trim(),
              style: const TextStyle(fontSize: 13.5),
            ),
          ),
    ];
    if (options.isEmpty) {
      showGlassToast(
        context,
        context.t('board.columns.noColumnAvailable'),
        kind: GlassToastKind.warning,
      );
      return;
    }
    final chosen = await showGlassOptions<int>(
      context,
      title: context.t('board.columns.assignTo'),
      options: options,
    );
    if (chosen == null || !mounted) return;
    setState(() => _columns[chosen].states.add(group.name));
  }

  void _unassignState(_Draft column, String state) =>
      setState(() => column.states.remove(state));

  void _addColumn() => setState(
    () => _columns.add(_Draft(name: context.t('board.columns.newColumn'))),
  );

  void _removeColumn(int index) => setState(() {
    // The states go back to the pool rather than vanishing with the column.
    _columns.removeAt(index).dispose();
  });

  Future<void> _save() async {
    if (!_complete || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context
          .read<BoardRepository>()
          .updateBoardColumns(widget.board.id, [
            for (final column in _columns)
              BoardColumnLayout(
                name: column.controller.text.trim(),
                states: column.states,
                wipLimit: column.wipLimit,
              ),
          ]);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _reset() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<BoardRepository>().resetBoardColumns(widget.board.id);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.columns3,
          title: context.t('board.columns.title'),
          subtitle: context.t('board.columns.subtitle'),
        ),
        Flexible(child: _loading ? _loader() : _body()),
        GlassModalFooter(
          confirmLabel: context.t('common.save'),
          busy: _busy,
          hint: widget.board.columnsCustomized ? _resetButton() : null,
          onConfirm: (_complete && !_loading) ? _save : null,
        ),
      ],
    );
  }

  Widget _loader() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 40),
    child: Center(child: HiveLoader()),
  );

  Widget _resetButton() => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: _busy ? null : _reset,
      icon: const Icon(LucideIcons.wandSparkles, size: 15),
      label: Text(context.t('board.columns.automatic')),
    ),
  );

  Widget _body() {
    final unassigned = _unassigned;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (unassigned.isNotEmpty) _unassignedSection(unassigned),
          Flexible(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.only(bottom: 4),
              itemCount: _columns.length,
              onReorderItem: (from, to) =>
                  setState(() => _columns.insert(to, _columns.removeAt(from))),
              itemBuilder: (_, index) => _columnCard(index),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addColumn,
              icon: const Icon(LucideIcons.plus, size: 15),
              label: Text(context.t('board.columns.addColumn')),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(
              context.t(_error!),
              style: const TextStyle(color: AppColors.danger, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }

  /// The states with no column yet. Shown as a warning rather than silently
  /// accepted: saving with a homeless status would take its issues off the wall.
  Widget _unassignedSection(List<_StateGroup> unassigned) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.triangleAlert,
                size: 14,
                color: AppColors.warning,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  context.t('board.columns.unassignedHint'),
                  style: const TextStyle(fontSize: 12, height: 1.35),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final group in unassigned)
                _StateChip(
                  group: group,
                  icon: LucideIcons.plus,
                  onAction: () => _assign(group),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _columnCard(int index) {
    final column = _columns[index];
    return Container(
      key: ValueKey(column.id),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    LucideIcons.gripVertical,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: column.controller,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    hintText: context.t('board.columns.namePlaceholder'),
                    hintStyle: TextStyle(
                      fontSize: 13.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _WipField(
                value: column.wipLimit,
                onChanged: (limit) => setState(() => column.wipLimit = limit),
              ),
              IconButton(
                onPressed: _columns.length > 1
                    ? () => _removeColumn(index)
                    : null,
                icon: const Icon(LucideIcons.trash2, size: 15),
                color: AppColors.danger,
                tooltip: context.t('board.columns.removeColumn'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: column.states.isEmpty
                ? Text(
                    context.t('board.columns.emptyColumn'),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  )
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final state in column.states)
                        _StateChip(
                          // A state whose project vanished mid-edit still renders,
                          // and stays removable.
                          group: _groupFor(state) ?? _StateGroup(state),
                          icon: LucideIcons.x,
                          onAction: () => _unassignState(column, state),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Mutable editing state of one column. Holds its own controller so typing a
/// name never rebuilds the whole list, and a stable id so reordering does not
/// confuse the list's keys.
class _Draft {
  _Draft({required String name, List<String>? states, this.wipLimit})
    : controller = TextEditingController(text: name),
      states = states ?? [],
      id = _nextId++;

  static int _nextId = 0;

  final int id;
  final TextEditingController controller;
  final List<String> states;
  int? wipLimit;

  void dispose() => controller.dispose();
}

/// One status name in the editor: its projects' colour, its name, and the one
/// action that applies to it (assign it, or take it out of a column).
class _StateChip extends StatelessWidget {
  const _StateChip({
    required this.group,
    required this.icon,
    required this.onAction,
  });

  final _StateGroup group;
  final IconData icon;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
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
              // Shared by several projects: no single colour speaks for it.
              color: group.projects.length == 1
                  ? projectAccent(group.projects.first)
                  : AppColors.textSecondary.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            group.projects.length == 1
                ? group.projects.first.key
                : '${group.projects.length}×',
            style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 5),
          Text(
            group.name,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 2),
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onAction,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(icon, size: 13, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact work-in-progress limit box; empty means no limit.
class _WipField extends StatefulWidget {
  const _WipField({required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  State<_WipField> createState() => _WipFieldState();
}

class _WipFieldState extends State<_WipField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value?.toString() ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 62,
      child: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12.5),
        onChanged: (raw) => widget.onChanged(int.tryParse(raw)),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 7),
          hintText: context.t('board.columns.wip'),
          hintStyle: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          filled: true,
          fillColor: AppColors.surface.withValues(alpha: 0.5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppColors.hairline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppColors.hairline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
          ),
        ),
      ),
    );
  }
}
