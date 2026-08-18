import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/repositories/team_repository.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/models/team_models.dart';
import '../../core/models/work_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/entity_avatar_editor.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';
import '../sprint/modals/glass_modal.dart'
    show showGlassConfirm, showGlassErrorToast;
import 'team_detail_screen.dart' show TeamDetailData;
import 'team_modals.dart';
import 'team_widgets.dart';

part 'team_tabs.members_projects.dart';
part 'team_tabs.settings.dart';

// ─────────────────────────── modal launchers ──────────────────────────────
// Shared by the header actions and the per-tab buttons. Each reloads on success.

Future<void> openAddMembers(
  BuildContext context,
  TeamDetailData data,
  Future<void> Function() reload,
) async {
  // The picker now type-aheads the directory server-side (excluding current
  // members itself), so we no longer drain data.usersById here.
  final changed = await showAddMembersModal(
    context,
    team: data.team,
    projectsById: data.projectsById,
  );
  if (changed == true) await reload();
}

Future<void> openAddProject(
  BuildContext context,
  TeamDetailData data,
  Future<void> Function() reload,
) async {
  final available =
      data.projectsById.values
          .where((p) => !data.team.projectIds.contains(p.id))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
  // Team members first, then everyone else — matches the reference lead pool.
  final memberIds = data.team.members.map((m) => m.userId).toList();
  final leadPool = <DirectoryUser>[
    for (final id in memberIds)
      if (data.usersById[id] != null) data.usersById[id]!,
    for (final u in data.usersById.values)
      if (!memberIds.contains(u.id)) u,
  ];
  final me = context.read<AuthBloc>().state.user;
  final changed = await showAddProjectModal(
    context,
    team: data.team,
    available: available,
    leadCandidates: leadPool,
    currentUserId: me?.id ?? (memberIds.isNotEmpty ? memberIds.first : ''),
  );
  if (changed == true) await reload();
}

Future<void> _openManageMember(
  BuildContext context,
  TeamDetailData data,
  TeamMembership membership,
  Future<void> Function() reload,
) async {
  final user =
      data.usersById[membership.userId] ??
      DirectoryUser(
        id: membership.userId,
        username: '',
        displayName: membership.userId,
      );
  final me = context.read<AuthBloc>().state.user;
  final changed = await showManageMemberModal(
    context,
    team: data.team,
    membership: membership,
    user: user,
    projectsById: data.projectsById,
    isSelf: me?.id == membership.userId,
  );
  if (changed == true) await reload();
}

// Progress proxy from the project's resolved/workflow ratio (no extra query).
double _progress(Project p) {
  if (p.workflowStates.isEmpty) return 0;
  return (p.resolvedStates.length / p.workflowStates.length).clamp(0.0, 1.0);
}

// ═══════════════════════════════ Overview ═════════════════════════════════

class TeamOverviewTab extends StatelessWidget {
  const TeamOverviewTab({
    super.key,
    required this.data,
    required this.manage,
    required this.onReload,
    required this.onGotoProjects,
    required this.onGotoMembers,
    required this.activity,
    required this.activityHasMore,
    required this.activityLoadingMore,
    required this.onLoadMoreActivity,
  });

  final TeamDetailData data;
  final bool manage;
  final Future<void> Function() onReload;
  final VoidCallback onGotoProjects;

  /// Jumps to the Members tab — also used by the Admins KPI (admins are
  /// shown within the Members tab, there's no dedicated Admins tab).
  final VoidCallback onGotoMembers;

  /// Paginated activity (page 0 from the bundle + any loaded older pages).
  final List<TeamActivity> activity;
  final bool activityHasMore;
  final bool activityLoadingMore;
  final VoidCallback onLoadMoreActivity;

  @override
  Widget build(BuildContext context) {
    final team = data.team;
    final projects = team.projectIds
        .map((id) => data.projectsById[id])
        .whereType<Project>()
        .toList();
    final kpis = [
      TeamKpi(
        icon: LucideIcons.users,
        value: '${team.members.length}',
        label: context.t('teams.kpiMembers'),
        hue: 250,
        onTap: onGotoMembers,
      ),
      TeamKpi(
        icon: LucideIcons.shieldCheck,
        value: '${team.adminCount}',
        label: context.t('teams.kpiAdmins'),
        hue: 70,
        onTap: onGotoMembers,
      ),
      TeamKpi(
        icon: LucideIcons.folder,
        value: '${team.projectIds.length}',
        label: context.t('teams.kpiProjects'),
        hue: 200,
        onTap: onGotoProjects,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            // Let each card size to its own content so text/scale changes never
            // clip — a fixed grid aspect ratio overflowed on phones.
            if (c.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < kpis.length; i++) ...[
                    if (i > 0) const SizedBox(height: 14),
                    kpis[i],
                  ],
                ],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < kpis.length; i++) ...[
                    if (i > 0) const SizedBox(width: 14),
                    Expanded(child: kpis[i]),
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            final stacked = c.maxWidth < 720;
            final projectsCard = _ProjectsMiniCard(
              data: data,
              projects: projects,
              manage: manage,
              onReload: onReload,
              onViewAll: onGotoProjects,
            );
            final activityCard = _ActivityCard(
              data: data,
              activity: activity,
              hasMore: activityHasMore,
              loadingMore: activityLoadingMore,
              onLoadMore: onLoadMoreActivity,
            );
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  projectsCard,
                  const SizedBox(height: 16),
                  activityCard,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: projectsCard),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: activityCard),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ProjectsMiniCard extends StatelessWidget {
  const _ProjectsMiniCard({
    required this.data,
    required this.projects,
    required this.manage,
    required this.onReload,
    required this.onViewAll,
  });

  final TeamDetailData data;
  final List<Project> projects;
  final bool manage;
  final Future<void> Function() onReload;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: context.t('teams.tabProjects'),
            actionLabel: projects.isEmpty ? null : context.t('teams.viewAll'),
            onAction: projects.isEmpty ? null : onViewAll,
          ),
          const SizedBox(height: 12),
          if (projects.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                context.t('teams.noProjectsYet'),
                style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
              ),
            )
          else
            for (var i = 0; i < projects.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _MiniProjectRow(project: projects[i]),
            ],
        ],
      ),
    );
  }
}

class _MiniProjectRow extends StatelessWidget {
  const _MiniProjectRow({required this.project});
  final Project project;

  @override
  Widget build(BuildContext context) {
    final color = projectHexColor(project.color);
    return Row(
      children: [
        ProjectKeyGlyph(
          label: project.key,
          color: color,
          avatarUrl: project.avatarUrl,
          size: 36,
          radius: 10,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                project.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              HiveProgress(value: _progress(project), color: color),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.data,
    required this.activity,
    required this.hasMore,
    required this.loadingMore,
    required this.onLoadMore,
  });
  final TeamDetailData data;
  final List<TeamActivity> activity;
  final bool hasMore;
  final bool loadingMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final acts = activity;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: context.t('teams.recentActivity')),
          const SizedBox(height: 12),
          if (acts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                context.t('teams.noActivity'),
                style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
              ),
            )
          else
            for (var i = 0; i < acts.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              _ActivityRow(activity: acts[i], data: data),
            ],
          if (hasMore) ...[
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                onPressed: loadingMore ? null : onLoadMore,
                icon: loadingMore
                    ? const HiveLoader(size: 14, strokeWidth: 2)
                    : Icon(
                        LucideIcons.chevronDown,
                        size: 15,
                        color: AppColors.inkSoft,
                      ),
                label: Text(
                  context.t('issues.loadMore'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.activity, required this.data});
  final TeamActivity activity;
  final TeamDetailData data;

  @override
  Widget build(BuildContext context) {
    final actorName =
        data.usersById[activity.actorId]?.displayName.split(' ').first ?? '—';
    // For member verbs the objectLabel is a userId; resolve it to a name.
    final memberVerb = const {
      'ADDED_MEMBER',
      'PROMOTED',
      'DEMOTED',
      'REMOVED_MEMBER',
    }.contains(activity.verb);
    final object = memberVerb
        ? (data.usersById[activity.objectLabel]?.displayName ??
              activity.objectLabel ??
              '')
        : (activity.objectLabel ?? '');
    final verbText = context.t('teams.activity.${_verbKey(activity.verb)}');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HiveAvatar(
          name: actorName,
          imageUrl: data.usersById[activity.actorId]?.avatarUrl,
          size: 28,
        ),
        const SizedBox(width: 11),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.inkSoft,
              ),
              children: [
                TextSpan(
                  text: actorName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                TextSpan(text: ' $verbText '),
                TextSpan(
                  text: object,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.accentStrong,
                  ),
                ),
                if ((activity.extra ?? '').isNotEmpty)
                  TextSpan(text: ' ${activity.extra}'),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _ago(activity.createdAt),
          style: TextStyle(
            fontFamily: AppTheme.fontMono,
            fontSize: 11,
            color: AppColors.inkFaint,
          ),
        ),
      ],
    );
  }

  String _verbKey(String verb) => switch (verb) {
    'CREATED' => 'created',
    'UPDATED' => 'updated',
    'ADDED_MEMBER' => 'addedMember',
    'PROMOTED' => 'promoted',
    'DEMOTED' => 'demoted',
    'REMOVED_MEMBER' => 'removedMember',
    'ATTACHED_PROJECT' => 'attachedProject',
    'CREATED_PROJECT' => 'createdProject',
    'DETACHED_PROJECT' => 'detachedProject',
    _ => 'updated',
  };

  String _ago(DateTime? time) {
    if (time == null) return '';
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${(diff.inDays / 7).floor()}w';
  }
}
