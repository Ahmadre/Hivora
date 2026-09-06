import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/repositories/user_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/models/team_models.dart';
import '../../core/models/work_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import 'team_modal_kit.dart';
import 'team_widgets.dart';

/// Add-members flow (2 steps: pick people → role & project access).
Future<bool?> showAddMembersModal(
  BuildContext context, {
  required Team team,
  required Map<String, Project> projectsById,
}) {
  final repo = context.read<TeamRepository>();
  final userRepo = context.read<UserRepository>();
  return showTeamModal<bool>(
    context,
    _AddMembersBody(
      repo: repo,
      userRepo: userRepo,
      team: team,
      projectsById: projectsById,
    ),
  );
}

/// Manage one member (role + access) with a remove/leave action.
Future<bool?> showManageMemberModal(
  BuildContext context, {
  required Team team,
  required TeamMembership membership,
  required DirectoryUser user,
  required Map<String, Project> projectsById,
  required bool isSelf,
}) {
  final repo = context.read<TeamRepository>();
  return showTeamModal<bool>(
    context,
    _ManageMemberBody(
      repo: repo,
      team: team,
      membership: membership,
      user: user,
      projectsById: projectsById,
      isSelf: isSelf,
    ),
    width: 520,
  );
}

// Shared access-picker helpers bound to a project lookup map.
mixin _ProjectLookup {
  Map<String, Project> get projectsById;
  String pName(String id) => projectsById[id]?.name ?? id;
  String pKey(String id) => projectsById[id]?.key ?? '?';
  Color pColor(String id) => projectHexColor(projectsById[id]?.color);
  String? pAvatar(String id) => projectsById[id]?.avatarUrl;
}

class _AddMembersBody extends StatefulWidget {
  const _AddMembersBody({
    required this.repo,
    required this.userRepo,
    required this.team,
    required this.projectsById,
  });

  final TeamRepository repo;
  final UserRepository userRepo;
  final Team team;
  final Map<String, Project> projectsById;

  @override
  State<_AddMembersBody> createState() => _AddMembersBodyState();
}

class _AddMembersBodyState extends State<_AddMembersBody> with _ProjectLookup {
  // Debounced server-side type-ahead over the directory (replaces draining the
  // whole org via users() and filtering in Dart).
  static const _debounceDelay = Duration(milliseconds: 250);
  static const _pageSize = 25;

  int _step = 1;
  String _query = '';
  final _selected = <String>{};
  TeamRole _role = TeamRole.member;
  AccessScope _scope = AccessScope.all;
  final _picked = <String>[];
  bool _busy = false;
  String? _error;

  Timer? _debounce;

  /// Monotonic request token — a debounced search that lands after a newer one
  /// started is discarded, so a slow response can never overwrite fresh results.
  int _reqSeq = 0;
  final List<DirectoryUser> _results = [];
  bool _loading = true;

  /// Ids already on the team — excluded from the picker rows so we only offer
  /// people who can actually be added.
  late final Set<String> _memberIds = widget.team.members
      .map((m) => m.userId)
      .toSet();

  @override
  Map<String, Project> get projectsById => widget.projectsById;

  @override
  void initState() {
    super.initState();
    // Empty query = first page of all active users (server-sorted).
    _runSearch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String v) {
    setState(() => _query = v);
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, _runSearch);
  }

  Future<void> _runSearch() async {
    _debounce?.cancel();
    final seq = ++_reqSeq;
    final query = _query.trim();
    setState(() => _loading = true);
    try {
      final res = await widget.userRepo.searchUsers(query, size: _pageSize);
      if (!mounted || seq != _reqSeq) return;
      setState(() {
        _results
          ..clear()
          ..addAll(res.items.where((u) => !_memberIds.contains(u.id)));
        _loading = false;
      });
    } on ApiFailure {
      if (!mounted || seq != _reqSeq) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _commit() async {
    final access = switch (_scope) {
      AccessScope.all => const ProjectAccess.all(),
      AccessScope.none => const ProjectAccess.none(),
      AccessScope.some => ProjectAccess.some(_picked),
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repo.addTeamMembers(
        widget.team.id,
        _selected.toList(),
        role: _role,
        access: access,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiFailure catch (failure) {
      setState(() {
        _busy = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final stepTwo = _step == 2;
    final canContinue = _selected.isNotEmpty;
    final canAdd = !(_scope == AccessScope.some && _picked.isEmpty);
    return ModalShell(
      icon: LucideIcons.userPlus,
      title: context.t('teams.addMembersTitle'),
      subtitle: stepTwo
          ? context.t('teams.addMembersStep2')
          : context.t(
              'teams.addMembersStep1',
              variables: {'name': widget.team.name},
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Stepper(step: _step),
          const SizedBox(height: 16),
          if (!stepTwo) ..._peopleStep(context) else ..._accessStep(context),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.danger, fontSize: 12.5),
            ),
          ],
        ],
      ),
      footer: ModalFooter(
        leadingIcon: stepTwo ? backArrow(context) : null,
        leadingLabel: stepTwo ? context.t('teams.back') : null,
        onLeading: stepTwo ? () => setState(() => _step = 1) : null,
        primaryLabel: stepTwo
            ? context.t(
                'teams.addCount',
                variables: {'count': '${_selected.length}'},
                count: _selected.length,
              )
            : context.t('common.continueAction'),
        primaryIcon: stepTwo ? LucideIcons.userPlus : forwardArrow(context),
        busy: _busy,
        onPrimary: stepTwo
            ? (canAdd ? _commit : null)
            : (canContinue ? () => setState(() => _step = 2) : null),
      ),
    );
  }

  List<Widget> _peopleStep(BuildContext context) {
    return [
      _SearchField(onChanged: _onQueryChanged),
      const SizedBox(height: 12),
      if (_loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(child: HiveLoader(size: 18)),
        )
      else if (_results.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            _query.trim().isEmpty
                ? context.t('teams.everyoneOnTeam')
                : context.t('common.noMatches'),
            style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
          ),
        )
      else
        for (var i = 0; i < _results.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          CheckRow(
            selected: _selected.contains(_results[i].id),
            onTap: () => setState(() {
              final id = _results[i].id;
              _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
            }),
            leading: HiveAvatar(
              name: _results[i].displayName,
              imageUrl: _results[i].avatarUrl,
              pronouns: _results[i].pronouns,
              size: 34,
            ),
            title: _results[i].displayName,
            subtitle: _results[i].title,
          ),
        ],
    ];
  }

  List<Widget> _accessStep(BuildContext context) {
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.users, size: 18, color: AppColors.inkSoft),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.t(
                  'teams.peopleSelected',
                  variables: {'count': '${_selected.length}'},
                  count: _selected.length,
                ),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      FieldLabel(context.t('teams.roleInTeam')),
      RoleSegmented(role: _role, onChanged: (r) => setState(() => _role = r)),
      const SizedBox(height: 8),
      Text(
        context.t(
          _role == TeamRole.admin
              ? 'teams.roleHintAdmin'
              : 'teams.roleHintMember',
        ),
        style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
      ),
      const SizedBox(height: 18),
      FieldLabel(context.t('teams.projectAccess')),
      AccessPicker(
        team: widget.team,
        projects: widget.team.projectIds,
        scope: _scope,
        pickedIds: _picked,
        onScope: (s) => setState(() => _scope = s),
        onTogglePick: (id) => setState(
          () => _picked.contains(id) ? _picked.remove(id) : _picked.add(id),
        ),
        projectName: pName,
        projectKey: pKey,
        projectColor: pColor,
        projectAvatar: pAvatar,
      ),
    ];
  }
}

class _ManageMemberBody extends StatefulWidget {
  const _ManageMemberBody({
    required this.repo,
    required this.team,
    required this.membership,
    required this.user,
    required this.projectsById,
    required this.isSelf,
  });

  final TeamRepository repo;
  final Team team;
  final TeamMembership membership;
  final DirectoryUser user;
  final Map<String, Project> projectsById;
  final bool isSelf;

  @override
  State<_ManageMemberBody> createState() => _ManageMemberBodyState();
}

class _ManageMemberBodyState extends State<_ManageMemberBody>
    with _ProjectLookup {
  late TeamRole _role = widget.membership.role;
  late AccessScope _scope = widget.membership.access.scope;
  late final List<String> _picked = widget.membership.access.projectIds
      .toList();
  bool _busy = false;
  String? _error;

  @override
  Map<String, Project> get projectsById => widget.projectsById;

  bool get _isLastAdmin =>
      widget.membership.isAdmin && widget.team.adminCount <= 1;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) Navigator.of(context).pop(true);
    } on ApiFailure catch (failure) {
      setState(() {
        _busy = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _save() => _run(() {
    final access = switch (_scope) {
      AccessScope.all => const ProjectAccess.all(),
      AccessScope.none => const ProjectAccess.none(),
      AccessScope.some => ProjectAccess.some(_picked),
    };
    return widget.repo.updateTeamMembership(
      widget.team.id,
      widget.user.id,
      role: _role,
      access: access,
    );
  });

  Future<void> _remove() =>
      _run(() => widget.repo.removeTeamMember(widget.team.id, widget.user.id));

  @override
  Widget build(BuildContext context) {
    return ModalShell(
      icon: LucideIcons.userCog,
      title: widget.user.displayName,
      subtitle: widget.user.title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldLabel(context.t('teams.roleLabel')),
          RoleSegmented(
            role: _role,
            adminDisabled: false,
            onChanged: (r) {
              // Block demoting the last admin.
              if (r == TeamRole.member && _isLastAdmin) return;
              setState(() => _role = r);
            },
          ),
          if (_isLastAdmin) ...[
            const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.info, size: 14, color: AppColors.inkFaint),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.t('teams.lastAdminHint'),
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          FieldLabel(context.t('teams.projectAccess')),
          AccessPicker(
            team: widget.team,
            projects: widget.team.projectIds,
            scope: _scope,
            pickedIds: _picked,
            onScope: (s) => setState(() => _scope = s),
            onTogglePick: (id) => setState(
              () => _picked.contains(id) ? _picked.remove(id) : _picked.add(id),
            ),
            projectName: pName,
            projectKey: pKey,
            projectColor: pColor,
            projectAvatar: pAvatar,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.danger, fontSize: 12.5),
            ),
          ],
        ],
      ),
      footer: ModalFooter(
        leadingIcon: _isLastAdmin ? null : LucideIcons.userMinus,
        leadingLabel: _isLastAdmin
            ? null
            : context.t(widget.isSelf ? 'teams.leave' : 'teams.remove'),
        onLeading: _isLastAdmin ? null : _remove,
        leadingDanger: true,
        primaryLabel: context.t('common.save'),
        busy: _busy,
        onPrimary: _save,
      ),
    );
  }
}

// ─────────────────────────── small modal widgets ──────────────────────────

class _Stepper extends StatelessWidget {
  const _Stepper({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _chip(context, 1, context.t('teams.stepPeople'), step >= 1),
        Expanded(
          child: Container(
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: AppColors.hairline,
          ),
        ),
        _chip(context, 2, context.t('teams.stepAccess'), step >= 2),
      ],
    );
  }

  Widget _chip(BuildContext context, int n, String label, bool on) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: on
                ? AppColors.accent
                : AppColors.surface.withValues(alpha: 0.7),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$n',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: on ? const Color(0xFF2A2410) : AppColors.inkFaint,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: on ? AppColors.ink : AppColors.inkFaint,
          ),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      autofocus: true,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration:
          teamFieldDecoration(
            context,
            hint: context.t('teams.searchPeople'),
          ).copyWith(
            prefixIcon: Icon(
              LucideIcons.search,
              size: 18,
              color: AppColors.inkFaint,
            ),
          ),
    );
  }
}
