part of 'team_tabs.dart';

// ═══════════════════════════════ Members ══════════════════════════════════

class TeamMembersTab extends StatelessWidget {
  const TeamMembersTab({
    super.key,
    required this.data,
    required this.manage,
    required this.onReload,
  });

  final TeamDetailData data;
  final bool manage;
  final Future<void> Function() onReload;

  @override
  Widget build(BuildContext context) {
    final myId = context.read<AuthBloc>().state.user?.id;
    final members = [...data.team.members]
      ..sort((a, b) {
        if (a.isAdmin == b.isAdmin) return 0;
        return a.isAdmin ? -1 : 1;
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.t(
                  'teams.membersSummary',
                  variables: {
                    'members': '${data.team.members.length}',
                    'admins': '${data.team.adminCount}',
                  },
                ),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
            if (manage)
              GhostButton(
                label: context.t('teams.addMembers'),
                icon: LucideIcons.userPlus,
                onPressed: () => openAddMembers(context, data, onReload),
              ),
          ],
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < members.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _MemberRow(
            data: data,
            membership: members[i],
            isSelf: members[i].userId == myId,
            manage: manage,
            onManage: () =>
                _openManageMember(context, data, members[i], onReload),
          ),
        ],
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.data,
    required this.membership,
    required this.isSelf,
    required this.manage,
    required this.onManage,
  });

  final TeamDetailData data;
  final TeamMembership membership;
  final bool isSelf;
  final bool manage;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final user = data.usersById[membership.userId];
    final name = user?.displayName ?? membership.userId;
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 460;
          final identity = Row(
            children: [
              HiveAvatar(name: name, imageUrl: user?.avatarUrl, size: 38),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        PronounsLabel(pronouns: user?.pronouns, leadingGap: 6),
                        if (isSelf) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accentSoft,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              context.t('teams.you'),
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                                color: AppColors.accentStrong,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if ((user?.title ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        user!.title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );

          final tags = Wrap(
            spacing: 9,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              RoleBadge(role: membership.role),
              AccessChip(team: data.team, membership: membership),
            ],
          );

          final kebab = manage
              ? IconButton(
                  onPressed: onManage,
                  visualDensity: VisualDensity.compact,
                  tooltip: context.t('teams.manage'),
                  icon: Icon(
                    LucideIcons.slidersHorizontal,
                    size: 18,
                    color: AppColors.inkSoft,
                  ),
                )
              : const SizedBox(width: 8);

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: identity),
                    kebab,
                  ],
                ),
                const SizedBox(height: 10),
                tags,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 12),
              tags,
              const SizedBox(width: 6),
              kebab,
            ],
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════ Projects ═════════════════════════════════

class TeamProjectsTab extends StatelessWidget {
  const TeamProjectsTab({
    super.key,
    required this.data,
    required this.manage,
    required this.onReload,
  });

  final TeamDetailData data;
  final bool manage;
  final Future<void> Function() onReload;

  Future<void> _detach(BuildContext context, Project project) async {
    final confirmed = await showGlassConfirm(
      context,
      icon: LucideIcons.unlink,
      title: context.t('teams.detachTitle'),
      message: context.t(
        'teams.detachConfirm',
        variables: {'name': project.name},
      ),
      confirmLabel: context.t('teams.detach'),
      confirmIcon: LucideIcons.unlink,
      destructive: true,
    );
    if (confirmed != true || !context.mounted) return;
    final repo = context.read<TeamRepository>();
    final errText = context.t('errors.unexpected');
    try {
      await repo.detachTeamProject(data.team.id, project.id);
      await onReload();
    } catch (_) {
      if (!context.mounted) return;
      showGlassErrorToast(context, errText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final projects = data.team.projectIds
        .map((id) => data.projectsById[id])
        .whereType<Project>()
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.t(
                  'teams.projectsSummary',
                  variables: {'count': '${data.team.projectIds.length}'},
                  count: data.team.projectIds.length,
                ),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
            if (manage)
              GhostButton(
                label: context.t('teams.addProject'),
                icon: LucideIcons.folderPlus,
                onPressed: () => openAddProject(context, data, onReload),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (projects.isEmpty)
          SoftCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  context.t('teams.noProjectsYet'),
                  style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
                ),
              ),
            ),
          )
        else
          for (var i = 0; i < projects.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _ProjectRow(
              data: data,
              project: projects[i],
              manage: manage,
              onDetach: () => _detach(context, projects[i]),
            ),
          ],
      ],
    );
  }
}

void _openProjectSettings(BuildContext context, String projectId) =>
    GoRouter.of(context).push('/projects/$projectId/settings');

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.data,
    required this.project,
    required this.manage,
    required this.onDetach,
  });

  final TeamDetailData data;
  final Project project;
  final bool manage;
  final VoidCallback onDetach;

  @override
  Widget build(BuildContext context) {
    final color = projectHexColor(project.color);
    final lead = project.leadId != null
        ? data.usersById[project.leadId!]
        : null;
    // Members whose access covers this project.
    final withAccessMembers = data.team.members.where((m) {
      final a = m.access;
      if (m.isAdmin || a.scope == AccessScope.all) return true;
      if (a.scope == AccessScope.some) {
        return a.projectIds.contains(project.id);
      }
      return false;
    }).toList();
    final withAccess = withAccessMembers
        .map((m) => data.usersById[m.userId]?.displayName ?? m.userId)
        .toList();
    final withAccessAvatars = withAccessMembers
        .map((m) => data.usersById[m.userId]?.avatarUrl)
        .toList();

    return SoftCard(
      onTap: () => _openProjectSettings(context, project.id),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 540;
          final identity = Row(
            children: [
              ProjectKeyGlyph(
                label: project.key,
                color: color,
                avatarUrl: project.avatarUrl,
                size: 40,
                radius: 11,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (lead != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        context.t(
                          'teams.leadName',
                          variables: {
                            'name': lead.displayName.split(' ').first,
                          },
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );

          final trailing = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (withAccess.isNotEmpty)
                HiveAvatarStack(
                  names: withAccess,
                  imageUrls: withAccessAvatars,
                  size: 24,
                  max: 3,
                ),
              if (manage) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onDetach,
                  visualDensity: VisualDensity.compact,
                  tooltip: context.t('teams.detach'),
                  icon: Icon(
                    LucideIcons.unlink,
                    size: 18,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ],
          );

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                identity,
                const SizedBox(height: 10),
                HiveProgress(value: _progress(project), color: color),
                const SizedBox(height: 10),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: trailing,
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 14),
              SizedBox(
                width: 120,
                child: HiveProgress(value: _progress(project), color: color),
              ),
              const SizedBox(width: 14),
              trailing,
            ],
          );
        },
      ),
    );
  }
}
