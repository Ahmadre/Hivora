import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality, LiquidRoundedSuperellipse;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/blocs/auth_bloc.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/core_models.dart';
import '../../../core/models/work_models.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/hue_colors.dart';
import '../../../core/widgets/entity_avatar.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../search/search_tokens.dart';
import '../../deletion/delete_flows.dart';
import '../../git/settings/git_integration_section.dart';
import '../../shell/page_chrome.dart';
import 'archive_section.dart';
import 'danger_section.dart';
import 'general_section.dart';
import 'labels_section.dart';
import 'members_section.dart';
import 'settings_common.dart';
import 'workflow_section.dart';
import '../../../core/repositories/project_repository.dart';
import '../../../core/repositories/user_repository.dart';

/// Full project-settings surface: identity, accent, leads & members, colored
/// labels, colored workflow states, and archive — edited as a draft behind a
/// sticky save bar with hard validation (mirrors the HTML reference).
class ProjectSettingsScreen extends StatefulWidget {
  const ProjectSettingsScreen({super.key, required this.projectId});

  final String projectId;

  @override
  State<ProjectSettingsScreen> createState() => _ProjectSettingsScreenState();
}

class _ProjectSettingsScreenState extends State<ProjectSettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  Project? _saved;
  Project? _draft;
  Map<String, DirectoryUser> _users = const {};
  List<DirectoryUser> _allUsers = const [];

  /// Issue count per *saved* workflow-state name (for the delete guard).
  Map<String, int> _stateUsage = const {};

  /// Deleted-state id -> target-state id, collected as the user resolves
  /// deletions of states that still have issues; sent on save.
  final Map<String, String> _stateMigrations = {};

  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  int _rev = 0; // forces label/workflow sections to rebuild their controllers
  int _tmpSeq = 0;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() => _onTextChanged(name: _nameCtrl.text));
    _keyCtrl.addListener(() => _onTextChanged(key: _keyCtrl.text));
    _descCtrl.addListener(() => _onTextChanged(description: _descCtrl.text));
    _load();
  }

  /// Syncs an identity text field into the draft. Guards against the listener
  /// firing for our own programmatic [_syncTextControllers] writes (which keep
  /// controller and draft already in step) to avoid a setState loop.
  void _onTextChanged({String? name, String? key, String? description}) {
    final d = _draft;
    if (d == null) return;
    if (name != null && name != d.name) {
      setState(() => _draft = d.copyWith(name: name));
    } else if (key != null && key != d.key) {
      setState(() => _draft = d.copyWith(key: key));
    } else if (description != null && description != (d.description ?? '')) {
      setState(() => _draft = d.copyWith(description: description));
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _keyCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        context.read<ProjectRepository>().project(widget.projectId),
        context.read<UserRepository>().users(),
        context.read<ProjectRepository>().projectStateUsage(widget.projectId),
      ]);
      final project = results[0] as Project;
      final users = results[1] as List<DirectoryUser>;
      final usage = results[2] as Map<String, int>;
      // Settings are lead/admin-only. A member who deep-links here is bounced
      // back to the project's issues (the server also rejects any save).
      if (!mounted) return;
      final me = context.read<AuthBloc>().state.user;
      final canManage =
          me != null && (me.isAdmin || project.leadIds.contains(me.id));
      if (!canManage) {
        context.go('/issues?projectId=${widget.projectId}');
        return;
      }
      setState(() {
        _saved = project;
        _draft = project;
        _allUsers = users;
        _users = {for (final u in users) u.id: u};
        _stateUsage = usage;
        _stateMigrations.clear();
        _syncTextControllers(project);
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      setState(() {
        _loading = false;
        _loadError = failure.message;
      });
    }
  }

  void _syncTextControllers(Project p) {
    _nameCtrl.text = p.name;
    _keyCtrl.text = p.key;
    _descCtrl.text = p.description ?? '';
  }

  String get _tmpId => 'tmp_${_tmpSeq++}';

  bool get _dirty => _draft != _saved;

  bool get _valid {
    final d = _draft;
    if (d == null) return false;
    return d.name.trim().isNotEmpty &&
        d.key.trim().isNotEmpty &&
        d.leadIds.isNotEmpty &&
        d.workflowStates.length >= 2 &&
        d.resolvedStates.isNotEmpty;
  }

  void _mutate(Project Function(Project) f) {
    final d = _draft;
    if (d == null) return;
    setState(() => _draft = f(d));
  }

  // ── identity ──────────────────────────────────────────────────────────
  void _onHue(int hue) => _mutate((d) => d.copyWith(color: hexForHue(hue)));

  /// Records the picture the avatar endpoints just committed.
  ///
  /// Written into *both* the draft and the saved snapshot on purpose: the
  /// picture is not part of the PATCH body, so it must never show up as an
  /// unsaved change in the save bar (`_dirty` compares the two).
  void _onAvatar(String? url) {
    setState(() {
      _saved = _saved?.copyWith(avatarUrl: url, clearAvatar: url == null);
      _draft = _draft?.copyWith(avatarUrl: url, clearAvatar: url == null);
    });
  }

  // ── members & leads ───────────────────────────────────────────────────
  Future<void> _addMembers() async {
    final d = _draft;
    if (d == null) return;
    final candidates = _allUsers
        .where((u) => !d.memberIds.contains(u.id))
        .toList();
    final picked = await showMemberPicker(
      context,
      candidates: candidates,
      projectName: d.name,
    );
    if (picked != null && picked.isNotEmpty) {
      _mutate((d) => d.copyWith(memberIds: [...d.memberIds, ...picked]));
    }
  }

  void _toggleLead(String id) {
    final d = _draft!;
    if (d.leadIds.contains(id)) {
      if (d.leadIds.length == 1) {
        settingsToast(context, context.t('projectSettings.toastLeadRequired'));
        return;
      }
      _mutate(
        (d) => d.copyWith(leadIds: d.leadIds.where((l) => l != id).toList()),
      );
    } else {
      _mutate((d) => d.copyWith(leadIds: [...d.leadIds, id]));
    }
  }

  void _removeMember(String id) {
    final d = _draft!;
    if (d.leadIds.contains(id) && d.leadIds.length == 1) {
      settingsToast(context, context.t('projectSettings.toastLeadRequired'));
      return;
    }
    _mutate(
      (d) => d.copyWith(
        memberIds: d.memberIds.where((m) => m != id).toList(),
        leadIds: d.leadIds.where((l) => l != id).toList(),
      ),
    );
  }

  // ── labels ────────────────────────────────────────────────────────────
  void _renameLabel(String id, String name) => _mutate(
    (d) => d.copyWith(
      labels: d.labels
          .map((l) => l.id == id ? l.copyWith(name: name) : l)
          .toList(),
    ),
  );

  void _recolorLabel(String id, int hue) => _mutate(
    (d) => d.copyWith(
      labels: d.labels
          .map((l) => l.id == id ? l.copyWith(hue: hue) : l)
          .toList(),
    ),
  );

  void _removeLabel(String id) => _mutate(
    (d) => d.copyWith(labels: d.labels.where((l) => l.id != id).toList()),
  );

  void _addLabel(String name) {
    final d = _draft!;
    if (d.labelNames.any((n) => n.toLowerCase() == name.toLowerCase())) {
      settingsToast(context, context.t('projectSettings.toastDuplicateLabel'));
      return;
    }
    _mutate(
      (d) => d.copyWith(
        labels: [
          ...d.labels,
          ProjectLabel(
            id: _tmpId,
            name: name,
            hue: kLabelHues[d.labels.length % kLabelHues.length],
          ),
        ],
      ),
    );
  }

  // ── workflow ──────────────────────────────────────────────────────────
  void _renameState(String id, String name) => _mutate(
    (d) => d.copyWith(
      workflowStates: d.workflowStates
          .map((s) => s.id == id ? s.copyWith(name: name) : s)
          .toList(),
    ),
  );

  void _recolorState(String id, int hue) => _mutate(
    (d) => d.copyWith(
      workflowStates: d.workflowStates
          .map((s) => s.id == id ? s.copyWith(hue: hue) : s)
          .toList(),
    ),
  );

  // [newIndex] arrives already adjusted for the removed item (onReorderItem).
  void _reorderState(int oldIndex, int newIndex) {
    final d = _draft!;
    final states = [...d.workflowStates];
    final moved = states.removeAt(oldIndex);
    states.insert(newIndex, moved);
    _mutate((d) => d.copyWith(workflowStates: states));
  }

  void _toggleResolved(String name) {
    final d = _draft!;
    if (d.resolvedStates.contains(name)) {
      if (d.resolvedStates.length == 1) {
        settingsToast(
          context,
          context.t('projectSettings.toastResolvedRequired'),
        );
        return;
      }
      _mutate(
        (d) => d.copyWith(
          resolvedStates: d.resolvedStates.where((r) => r != name).toList(),
        ),
      );
    } else {
      _mutate((d) => d.copyWith(resolvedStates: [...d.resolvedStates, name]));
    }
  }

  Future<void> _deleteState(String id) async {
    final d = _draft!;
    if (d.workflowStates.length <= 2) {
      settingsToast(context, context.t('projectSettings.toastMinStates'));
      return;
    }
    final state = d.workflowStates.firstWhere((s) => s.id == id);
    if (d.resolvedStates.contains(state.name) && d.resolvedStates.length == 1) {
      settingsToast(
        context,
        context.t('projectSettings.toastResolvedRequired'),
      );
      return;
    }

    // A state with issues assigned (by its *saved* name) can't be removed until
    // the user picks a state to migrate those issues into.
    final savedName = _saved?.workflowStates
        .where((s) => s.id == id)
        .map((s) => s.name)
        .firstOrNull;
    final count = savedName == null ? 0 : (_stateUsage[savedName] ?? 0);
    if (count > 0) {
      final targets = d.workflowStates.where((s) => s.id != id).toList();
      final targetId = await showStateMigrationDialog(
        context,
        stateName: state.name,
        issueCount: count,
        targets: targets,
      );
      if (targetId == null) return; // cancelled — keep the state
      _stateMigrations[id] = targetId;
    }

    _mutate(
      (d) => d.copyWith(
        workflowStates: d.workflowStates.where((s) => s.id != id).toList(),
        resolvedStates: d.resolvedStates.where((r) => r != state.name).toList(),
      ),
    );
  }

  void _addState() => _mutate(
    (d) => d.copyWith(
      workflowStates: [
        ...d.workflowStates,
        WorkflowState(
          id: _tmpId,
          name: context.t('projectSettings.newState'),
          hue: 250,
        ),
      ],
    ),
  );

  // ── persistence ───────────────────────────────────────────────────────
  void _discard() {
    final saved = _saved;
    if (saved == null) return;
    setState(() {
      _draft = saved;
      _stateMigrations.clear();
      _syncTextControllers(saved);
      _rev++;
    });
  }

  Future<void> _save() async {
    final d = _draft;
    if (d == null || !_valid || _saving) return;
    setState(() => _saving = true);
    final projectApi = context.read<ProjectRepository>();
    try {
      final patch = <String, dynamic>{
        'name': d.name.trim(),
        'key': d.key.trim(),
        'description': d.description ?? '',
        'color': d.color,
        'leadIds': d.leadIds,
        'memberIds': d.memberIds,
        'workflowStates': d.workflowStates.map((s) => s.toJson()).toList(),
        'resolvedStates': d.resolvedStates,
        'labels': d.labels.map((l) => l.toJson()).toList(),
        'archived': d.archived,
        if (_stateMigrations.isNotEmpty) 'stateMigrations': _stateMigrations,
      };
      final updated = await projectApi.updateProject(d.id, patch);
      // Counts changed once issues were reassigned/deleted.
      final usage = await projectApi.projectStateUsage(d.id);
      if (!mounted) return;
      setState(() {
        _saved = updated;
        _draft = updated;
        _stateUsage = usage;
        _stateMigrations.clear();
        _syncTextControllers(updated);
        _saving = false;
        _rev++;
      });
      settingsToast(context, context.t('projectSettings.toastSaved'));
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _saving = false);
      settingsToast(context, failure.message);
    }
  }

  /// Merges a Git-connection change (connect / disconnect / automation / branch
  /// template) into both the saved and draft copies. Git mutations persist
  /// server-side immediately, so this only replaces the repository fields — the
  /// primary `git` plus the full `extraRepos` list — and leaves any in-progress
  /// draft edits (and the dirty state) untouched.
  void _onGitChanged(Project serverProject) {
    if (!mounted) return;
    setState(() {
      _saved = _saved?.withGit(
        serverProject.git,
        extraRepos: serverProject.extraRepos,
      );
      _draft = _draft?.withGit(
        serverProject.git,
        extraRepos: serverProject.extraRepos,
      );
    });
  }

  /// Opens the streamed delete flow; on success leaves settings so the projects
  /// list (which reloads when this route pops) no longer shows the project.
  Future<void> _deleteProject() async {
    final project = _saved ?? _draft;
    if (project == null) return;
    final deleted = await showDeleteProjectFlow(
      context,
      projectId: project.id,
      projectName: project.name,
    );
    if (deleted == true && mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    // The shell bar shows back + the generic section title; the project's name
    // lives only in the in-page _Header (avoids a doubled header).
    return PageChrome(
      title: context.t('projectSettings.title'),
      child: _loading
          ? const Center(child: HiveLoader())
          : _loadError != null
          ? Center(
              child: Text(
                _loadError!,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          : _buildBody(context, draft!),
    );
  }

  Widget _buildBody(BuildContext context, Project draft) {
    final nameErr = draft.name.trim().isEmpty;
    final keyErr = draft.key.trim().isEmpty;

    final general = GeneralSection(
      nameController: _nameCtrl,
      keyController: _keyCtrl,
      descController: _descCtrl,
      nameError: nameErr,
      keyError: keyErr,
      selectedHue: hueForHex(draft.color),
      onHue: _onHue,
      avatarUrl: draft.avatarUrl,
      onUploadAvatar: (file) => context
          .read<ProjectRepository>()
          .uploadProjectAvatar(widget.projectId, file),
      onRemoveAvatar: () => context
          .read<ProjectRepository>()
          .deleteProjectAvatar(widget.projectId),
      onAvatarChanged: _onAvatar,
    );
    final members = MembersSection(
      memberIds: draft.memberIds,
      leadIds: draft.leadIds,
      users: _users,
      onToggleLead: _toggleLead,
      onRemove: _removeMember,
      onAdd: _addMembers,
    );
    final labels = LabelsSection(
      key: ValueKey('labels_$_rev'),
      labels: draft.labels,
      onRename: _renameLabel,
      onRecolor: _recolorLabel,
      onRemove: _removeLabel,
      onAdd: _addLabel,
    );
    final workflow = WorkflowSection(
      key: ValueKey('workflow_$_rev'),
      states: draft.workflowStates,
      resolved: draft.resolvedStates,
      onRename: _renameState,
      onRecolor: _recolorState,
      onReorder: _reorderState,
      onToggleResolved: _toggleResolved,
      onDelete: _deleteState,
      onAdd: _addState,
    );
    final git = GitIntegrationSection(
      project: _saved ?? draft,
      users: _users,
      onProjectChanged: _onGitChanged,
    );
    final archive = ArchiveSection(
      archived: draft.archived,
      onChanged: (v) => _mutate((d) => d.copyWith(archived: v)),
    );
    final danger = DangerSection(onDelete: _deleteProject);

    return LayoutBuilder(
      builder: (context, box) {
        // Golden-ratio layout: once the body is wider than a φ² column, split
        // into a φ:1 two-column grid; below that, stack a single φ² column.
        final twoColumn = box.maxWidth >= Breakpoints.mediumMax;
        final contentMax = twoColumn
            ? Breakpoints.baseColumnWidth *
                  Breakpoints.phi *
                  Breakpoints.phi *
                  Breakpoints
                      .phi // ≈ 1597
            : Breakpoints.baseColumnWidth *
                  Breakpoints.phi *
                  Breakpoints.phi; // ≈ 987
        return _buildScaffold(
          context,
          draft: draft,
          contentMax: contentMax,
          twoColumn: twoColumn,
          general: general,
          members: members,
          labels: labels,
          workflow: workflow,
          git: git,
          archive: archive,
          danger: danger,
        );
      },
    );
  }

  Widget _buildScaffold(
    BuildContext context, {
    required Project draft,
    required double contentMax,
    required bool twoColumn,
    required Widget general,
    required Widget members,
    required Widget labels,
    required Widget workflow,
    required Widget git,
    required Widget archive,
    required Widget danger,
  }) {
    const gap = SizedBox(height: 16);
    // The multiline Description field's return key inserts a newline (never
    // resigns first responder), and this screen has no Scaffold/global unfocus —
    // so give it the same escape hatches as the admin forms: tap-outside to
    // unfocus + drag-to-dismiss. Otherwise the keyboard is trapped on phones.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              context.pageGutter,
              16 + context.topGutter,
              context.pageGutter,
              // Reserve room so the last card clears the floating save bar.
              (_dirty ? 96 : 24) + context.bottomGutter,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentMax),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(draft: draft),
                      const SizedBox(height: 20),
                      if (twoColumn)
                        // φ:1 golden split — heavy editing surfaces live in the
                        // wide column, light toggles/meta in the narrow one.
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 1618,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  general,
                                  gap,
                                  members,
                                  gap,
                                  workflow,
                                  gap,
                                  git,
                                ],
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              flex: 1000,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [labels, gap, archive, gap, danger],
                              ),
                            ),
                          ],
                        )
                      else ...[
                        general,
                        gap,
                        members,
                        gap,
                        labels,
                        gap,
                        workflow,
                        gap,
                        git,
                        gap,
                        archive,
                        gap,
                        danger,
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            // No SafeArea here: context.bottomGutter already carries the floating
            // nav's footprint + device inset (injected by the shell), so wrapping
            // in SafeArea would count that bottom inset twice and float the bar
            // up into the middle of the screen. When the keyboard is open, ride
            // above it instead of the nav.
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                context.pageGutter,
                0,
                context.pageGutter,
                context.isCompact
                    ? math.max(
                            context.bottomGutter,
                            MediaQuery.viewInsetsOf(context).bottom,
                          ) -
                          20
                    : 12 +
                          math.max(
                            context.bottomGutter,
                            MediaQuery.viewInsetsOf(context).bottom,
                          ),
              ),
              child: Center(
                child: ConstrainedBox(
                  // Match the content column so the bar visually docks to it.
                  constraints: BoxConstraints(
                    maxWidth: math.min(contentMax, 880),
                  ),
                  child: _SaveBar(
                    visible: _dirty,
                    valid: _valid,
                    saving: _saving,
                    onDiscard: _discard,
                    onSave: _save,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.draft});
  final Project draft;

  @override
  Widget build(BuildContext context) {
    final hue = hueForHex(draft.color);
    return Row(
      children: [
        // The picture, when there is one — this is the page that edits it, so
        // the header would otherwise still show the key square while the field
        // below it already shows the new image.
        EntityAvatar(
          avatarUrl: draft.avatarUrl,
          size: 54,
          radius: 15,
          fallback: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: hueSoft(hue),
              borderRadius: BorderRadius.circular(15),
            ),
            alignment: Alignment.center,
            child: Text(
              draft.key.isEmpty ? '—' : draft.key,
              style: TextStyle(
                fontFamily: AppTheme.fontMono,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: hueChipText(hue),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      draft.name.isEmpty
                          ? context.t('projectSettings.untitled')
                          : draft.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (draft.archived) ...[
                    const SizedBox(width: 10),
                    _ArchivedBadge(),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${context.t('projectSettings.title')} · ${draft.key.isEmpty ? '—' : draft.key}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTheme.fontMono,
                  fontSize: 13,
                  color: AppColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ArchivedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.canvas2,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.archive, size: 12, color: AppColors.inkSoft),
          const SizedBox(width: 5),
          Text(
            context.t('projectSettings.archived'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sticky glass save bar that slides in when the draft differs from saved.
class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.visible,
    required this.valid,
    required this.saving,
    required this.onDiscard,
    required this.onSave,
  });

  final bool visible;
  final bool valid;
  final bool saving;
  final VoidCallback onDiscard;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    // No SizeTransition here: it clips the child to its rectangular layout box,
    // which would cut the glass pill's soft shadow into a hard-edged rectangle.
    // A fade + slide keeps the shadow intact.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.35),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: !visible ? const SizedBox.shrink() : _bar(context),
    );
  }

  Widget _bar(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tokens = SearchTokens.of(Theme.of(context).brightness);
    return GlassPanelShadow(
      radius: BorderRadius.circular(30),
      shadows: tokens.panelShadow,
      child: GlassContainer(
        useOwnLayer: true,
        quality: GlassQuality.premium,
        clipBehavior: Clip.antiAlias,
        shape: const LiquidRoundedSuperellipse(borderRadius: 30),
        settings: liquidGlassPanelSettings(
          glassFill: tokens.glassFill,
          dark: dark,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
          child: Row(
            children: [
              Icon(
                valid ? LucideIcons.info : LucideIcons.triangleAlert,
                size: 17,
                color: valid ? AppColors.accentStrong : AppColors.danger,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  valid
                      ? context.t('projectSettings.unsavedChanges')
                      : context.t('projectSettings.fixRequired'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: tokens.inkSoft,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: saving ? null : onDiscard,
                style: TextButton.styleFrom(foregroundColor: tokens.ink),
                child: Text(context.t('projectSettings.discard')),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: (!valid || saving) ? null : onSave,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                  ),
                ),
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: HiveLoader(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(LucideIcons.check, size: 16),
                label: Text(context.t('projectSettings.saveChanges')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
