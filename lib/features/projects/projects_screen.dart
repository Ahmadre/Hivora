import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/fetch_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/hue_colors.dart';
import '../../core/util/keys.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';
import '../sprint/modals/glass_modal.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/user_repository.dart';

typedef _ProjectsData = ({
  List<Project> active,
  List<Project> archived,
  Map<String, String> names,
  Map<String, String> avatars,
});

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  late final FetchCubit<_ProjectsData> _cubit;
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _cubit = FetchCubit<_ProjectsData>(() async {
      final results = await Future.wait([
        context.read<ProjectRepository>().projects(),
        context.read<ProjectRepository>().projects(archived: true),
        context.read<UserRepository>().users(),
      ]);
      final active = results[0] as List<Project>;
      final archived = results[1] as List<Project>;
      final users = results[2] as List<DirectoryUser>;
      final names = {for (final u in users) u.id: u.displayName};
      final avatars = {
        for (final u in users)
          if (u.avatarUrl != null && u.avatarUrl!.isNotEmpty)
            u.id: u.avatarUrl!,
      };
      return (
        active: active,
        archived: archived,
        names: names,
        avatars: avatars,
      );
    })..load();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<FetchCubit<_ProjectsData>, FetchState<_ProjectsData>>(
        builder: (context, state) {
          final active = state.data?.active ?? const <Project>[];
          final archived = state.data?.archived ?? const <Project>[];
          final names = state.data?.names ?? const <String, String>{};
          final avatars = state.data?.avatars ?? const <String, String>{};
          final projects = _showArchived ? archived : active;
          return RefreshIndicator(
            onRefresh: _cubit.load,
            color: AppColors.accent,
            edgeOffset: context.topGutter,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    context.pageGutter,
                    24 + context.topGutter,
                    context.pageGutter,
                    16,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: PageHead(
                      title: context.t('projects.title'),
                      subtitle: context.t(
                        'projects.summary',
                        variables: {
                          'active': '${active.length}',
                          'archived': '${archived.length}',
                        },
                      ),
                      actions: [
                        PrimaryButton(
                          label: context.t('projects.new'),
                          onPressed: _showCreate,
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    context.pageGutter,
                    0,
                    context.pageGutter,
                    16,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SegmentedControl(
                        selected: _showArchived ? 1 : 0,
                        onChanged: (i) =>
                            setState(() => _showArchived = i == 1),
                        items: [
                          SegmentItem(
                            label: context.t('projects.active'),
                            icon: LucideIcons.folderOpen,
                          ),
                          SegmentItem(
                            label: archived.isEmpty
                                ? context.t('projects.archived')
                                : '${context.t('projects.archived')} · ${archived.length}',
                            icon: LucideIcons.archive,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (state.isLoading && projects.isEmpty)
                  const SliverFillRemaining(child: Center(child: HiveLoader()))
                else if (projects.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: context.pageGutter,
                        vertical: 24,
                      ),
                      child: Center(
                        child: HiveEmptyState(
                          title: context.t('projects.title'),
                          message: _showArchived
                              ? context.t('projects.emptyArchived')
                              : context.t('projects.empty'),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      context.pageGutter,
                      0,
                      context.pageGutter,
                      context.pageGutter + context.bottomGutter,
                    ),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: context.gridColumns(minTileWidth: 300),
                        mainAxisSpacing: 18,
                        crossAxisSpacing: 18,
                        mainAxisExtent: 210,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _ProjectCard(
                          project: projects[index],
                          names: names,
                          avatars: avatars,
                          onSettings: () => _openSettings(projects[index]),
                        ),
                        childCount: projects.length,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Keys of the projects this user can see — archived ones included, since
  /// they hold their key too. What the create dialog steps around when it
  /// suggests one.
  Set<String> _takenProjectKeys() {
    final data = _cubit.state.data;
    if (data == null) return const {};
    return {
      for (final p in [...data.active, ...data.archived]) p.key.toUpperCase(),
    };
  }

  Future<void> _showCreate() async {
    final projects = context.read<ProjectRepository>();
    final users = context.read<UserRepository>();
    final meId = context.read<AuthBloc>().state.user?.id;
    final created = await showGlassModal<Project>(
      context,
      width: 580,
      builder: (modalContext) => MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: projects),
          RepositoryProvider.value(value: users),
        ],
        child: _CreateProjectBody(meId: meId, takenKeys: _takenProjectKeys()),
      ),
    );
    if (created != null) _cubit.load();
  }

  Future<void> _openSettings(Project project) async {
    await context.push('/projects/${project.id}/settings');
    if (mounted) _cubit.load();
  }
}

/// Parses a project's stored hex color (e.g. "#AEC6F4") to a Color, with a
/// stable hue fallback derived from the project key.
Color _projectColor(Project project) {
  final raw = project.color.replaceAll('#', '').trim();
  if (raw.length == 6) {
    final value = int.tryParse(raw, radix: 16);
    if (value != null) return Color(0xFF000000 | value);
  }
  return hiveHueColor(project.key);
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.names,
    required this.avatars,
    required this.onSettings,
  });

  final Project project;
  final Map<String, String> names;
  final Map<String, String> avatars;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    // Mobile shows the compact gear in the corner; larger views show the
    // full-width "Settings" button in the footer instead.
    final compact = context.isCompact;
    // Only project leads (and platform admins) may open project settings —
    // regular members work on the project but never see its configuration.
    final me = context.read<AuthBloc>().state.user;
    final canManage =
        me != null && (me.isAdmin || project.leadIds.contains(me.id));
    final color = _projectColor(project);
    final glyphColor = project.archived
        ? HSLColor.fromColor(color).withSaturation(0.25).toColor()
        : color;
    final leadName = project.leadId != null ? names[project.leadId!] : null;
    final memberNames = project.memberIds
        .map((id) => names[id] ?? id)
        .toList(growable: false);
    final memberAvatars = project.memberIds
        .map((id) => avatars[id])
        .toList(growable: false);
    final subtitle = leadName != null
        ? '${project.key} · ${context.t('projects.lead')} ${leadName.split(' ').first}'
        : project.key;

    final card = SoftCard(
      onTap: () => context.go('/issues?projectId=${project.id}'),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.soft(glyphColor),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  project.key,
                  style: TextStyle(
                    fontFamily: AppTheme.fontMono,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: glyphColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Leave room for the corner gear only when it's shown.
                    Padding(
                      padding: EdgeInsets.only(
                        right: compact && canManage ? 26 : 0,
                      ),
                      child: Text(
                        project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTheme.fontMono,
                        fontSize: 11.5,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Stat(
                value: '${project.memberIds.length}',
                label: context.t('projects.membersLabel'),
              ),
              const SizedBox(width: 20),
              _Stat(
                value: '${project.workflowStates.length}',
                label: context.t('projects.statesLabel'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          HiveProgress(value: _completion(project), color: glyphColor),
          const Spacer(),
          const SizedBox(height: 12),
          Row(
            children: [
              if (memberNames.isNotEmpty)
                Expanded(
                  child: HiveAvatarStack(
                    names: memberNames,
                    imageUrls: memberAvatars,
                    size: 26,
                  ),
                )
              else
                const Spacer(),
              if (project.labels.isNotEmpty) ...[
                Icon(LucideIcons.tag, size: 14, color: AppColors.inkFaint),
                const SizedBox(width: 4),
                Text(
                  '${project.labels.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              if (!compact && canManage) _SettingsButton(onTap: onSettings),
            ],
          ),
        ],
      ),
    );

    final stacked = Stack(
      children: [
        card,
        if (compact && canManage)
          Positioned(top: 10, right: 10, child: _GearButton(onTap: onSettings)),
      ],
    );

    return project.archived ? Opacity(opacity: 0.82, child: stacked) : stacked;
  }

  // Resolved-state ratio gives a rough completion proxy when no counts exist.
  double _completion(Project project) {
    if (project.workflowStates.isEmpty) return 0.0;
    return (project.resolvedStates.length / project.workflowStates.length)
        .clamp(0.0, 1.0);
  }
}

/// Small gear affordance in the card corner that opens project settings.
class _GearButton extends StatelessWidget {
  const _GearButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceMuted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: AppColors.hairline),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(LucideIcons.settings, size: 15, color: AppColors.inkSoft),
        ),
      ),
    );
  }
}

/// Footer "Settings" ghost button on each project card.
class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.slidersHorizontal,
                size: 14,
                color: AppColors.inkSoft,
              ),
              const SizedBox(width: 6),
              Text(
                context.t('projects.settings'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontFamily: AppTheme.fontBrand,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 11, color: AppColors.inkSoft)),
      ],
    );
  }
}

/// "New project" creation modal, rendered on the app's Liquid Glass material
/// (same as the sprint/team modals) and matching the design: glyph + name/key,
/// description, lead, accent color and the default-workflow note.
class _CreateProjectBody extends StatefulWidget {
  const _CreateProjectBody({required this.meId, this.takenKeys = const {}});

  final String? meId;

  /// Keys already in use, so the suggested one doesn't walk into a conflict the
  /// server would only report after the form is submitted. Best effort — the
  /// server stays the authority (it answers 409 for a key this list missed).
  final Set<String> takenKeys;

  @override
  State<_CreateProjectBody> createState() => _CreateProjectBodyState();
}

class _CreateProjectBodyState extends State<_CreateProjectBody> {
  final _key = TextEditingController();
  final _name = TextEditingController();
  final _description = TextEditingController();

  /// While true the key follows the name. The first edit of the key field ends
  /// that for good — a key somebody typed is theirs to keep.
  bool _keyFollowsName = true;

  List<DirectoryUser> _users = const [];
  String? _leadId;
  int _hue = kProjectHues.first.hue;
  bool _saving = false;
  String? _error;

  static final _keyPattern = RegExp(r'^[A-Z][A-Z0-9]{1,9}$');

  @override
  void initState() {
    super.initState();
    _leadId = widget.meId;
    _name.addListener(_onNameChanged);
    _key.addListener(_onKeyChanged);
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await context.read<UserRepository>().users();
      if (mounted) setState(() => _users = users);
    } on ApiFailure {
      // Lead picker simply stays limited to the current user.
    }
  }

  void _refresh() => setState(() {});

  /// Types the key along with the name — the whole point being that nobody has
  /// to invent one, while it stays a plain text field they can overrule.
  void _onNameChanged() {
    if (_keyFollowsName) {
      final suggestion = suggestKey(_name.text, taken: widget.takenKeys);
      if (suggestion != _key.text) {
        // Set through the controller's value so the caret stays at the end.
        _key.value = TextEditingValue(
          text: suggestion,
          selection: TextSelection.collapsed(offset: suggestion.length),
        );
        return; // the key listener refreshes
      }
    }
    _refresh();
  }

  void _onKeyChanged() {
    // Only a *typed* key breaks the link; the one we just wrote does not.
    if (_keyFollowsName &&
        _key.text != suggestKey(_name.text, taken: widget.takenKeys)) {
      _keyFollowsName = false;
    }
    _refresh();
  }

  /// A key the client already knows is taken — surfaced before the round trip.
  bool get _keyTaken =>
      widget.takenKeys.contains(_key.text.trim().toUpperCase());

  @override
  void dispose() {
    _key.dispose();
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      _keyPattern.hasMatch(_key.text.trim()) &&
      !_keyTaken;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.folderPlus,
          title: context.t('projects.new'),
          subtitle: context.t('projects.newSubtitle'),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _identityRow(compact),
                const SizedBox(height: 16),
                GlassField(
                  label: context.t('projects.descriptionOptional'),
                  child: TextField(
                    controller: _description,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 2,
                    maxLines: 4,
                    decoration: glassInputDecoration(
                      hint: context.t('projectSettings.descHint'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _leadAndColor(compact),
                const SizedBox(height: 16),
                GlassInfoLine(
                  icon: LucideIcons.info,
                  child: Text(
                    context.t('projects.defaultWorkflowInfo'),
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('common.create'),
          confirmIcon: LucideIcons.check,
          busy: _saving,
          onConfirm: _valid ? _save : null,
        ),
      ],
    );
  }

  Widget _identityRow(bool compact) {
    final glyph = _GlyphPreview(hue: _hue, keyText: _key.text);
    final nameField = GlassField(
      label: context.t('projects.name'),
      child: TextField(
        controller: _name,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        decoration: glassInputDecoration(hint: 'e.g. Billing & Plans'),
      ),
    );
    final keyField = GlassField(
      label: context.t('projects.key'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _key,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            maxLength: 10,
            style: const TextStyle(fontFamily: AppTheme.fontMono),
            inputFormatters: [_UpperAlphaNumFormatter()],
            decoration: glassInputDecoration(
              hint: 'BILL',
            ).copyWith(counterText: ''),
          ),
          // Said here rather than after a round trip that fails.
          if (_keyTaken)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                context.t('projects.keyTaken'),
                style: const TextStyle(fontSize: 11.5, color: AppColors.danger),
              ),
            ),
        ],
      ),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              glyph,
              const SizedBox(width: 12),
              Expanded(child: nameField),
            ],
          ),
          const SizedBox(height: 14),
          keyField,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        glyph,
        const SizedBox(width: 12),
        Expanded(child: nameField),
        const SizedBox(width: 12),
        SizedBox(width: 104, child: keyField),
      ],
    );
  }

  Widget _leadAndColor(bool compact) {
    final lead = GlassField(
      label: context.t('projects.projectLead'),
      child: _LeadDropdown(
        users: _users,
        meId: widget.meId,
        value: _leadId,
        onChanged: (v) => setState(() => _leadId = v),
      ),
    );
    final color = GlassField(
      label: context.t('projects.color'),
      child: _AccentSwatches(
        selected: _hue,
        onPick: (h) => setState(() => _hue = h),
      ),
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [lead, const SizedBox(height: 16), color],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: lead),
        const SizedBox(width: 16),
        Flexible(child: color),
      ],
    );
  }

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final project = await context.read<ProjectRepository>().createProject(
        key: _key.text.trim().toUpperCase(),
        name: _name.text.trim(),
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        color: hexForHue(_hue),
        leadId: _leadId,
      );
      if (mounted) Navigator.of(context).pop(project);
    } on ApiFailure catch (failure) {
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    }
  }
}

/// Live glyph tile previewing the project's key + accent in the create modal.
class _GlyphPreview extends StatelessWidget {
  const _GlyphPreview({required this.hue, required this.keyText});
  final int hue;
  final String keyText;

  @override
  Widget build(BuildContext context) {
    final label = keyText.isEmpty
        ? 'P'
        : keyText.substring(0, keyText.length.clamp(0, 3));
    return Container(
      width: 54,
      height: 54,
      margin: const EdgeInsets.only(top: 22),
      decoration: BoxDecoration(
        color: hueSoft(hue),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTheme.fontMono,
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: hueChipText(hue),
        ),
      ),
    );
  }
}

/// Project-lead dropdown rendered on the glass material.
class _LeadDropdown extends StatelessWidget {
  const _LeadDropdown({
    required this.users,
    required this.meId,
    required this.value,
    required this.onChanged,
  });

  final List<DirectoryUser> users;
  final String? meId;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = users.isEmpty && value != null
        ? [
            DropdownMenuItem(
              value: value,
              child: Text(context.t('projects.you')),
            ),
          ]
        : [
            for (final u in users)
              DropdownMenuItem(
                value: u.id,
                child: Text(
                  u.id == meId
                      ? '${u.displayName} (${context.t('projects.you')})'
                      : u.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ];
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      icon: Icon(
        LucideIcons.chevronsUpDown,
        size: 16,
        color: AppColors.inkSoft,
      ),
      decoration: glassInputDecoration(),
      items: items,
      onChanged: onChanged,
    );
  }
}

/// Static accent-color swatch row for the create modal.
class _AccentSwatches extends StatelessWidget {
  const _AccentSwatches({required this.selected, required this.onPick});
  final int selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in kProjectHues)
          GestureDetector(
            onTap: () => onPick(c.hue),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: hueSwatch(c.hue),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: c.hue == selected ? AppColors.ink : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Uppercases and strips non-[A-Z0-9] as the project key is typed.
class _UpperAlphaNumFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.toUpperCase().replaceAll(
      RegExp('[^A-Z0-9]'),
      '',
    );
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
