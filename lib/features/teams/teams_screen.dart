import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/fetch_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/models/team_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';
import 'team_modals.dart';
import 'team_widgets.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/repositories/user_repository.dart';

typedef _TeamsData = ({
  List<Team> teams,
  Map<String, String> names,
  Map<String, String> avatars,
});

class TeamsScreen extends StatefulWidget {
  const TeamsScreen({super.key});

  @override
  State<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> {
  late final FetchCubit<_TeamsData> _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = FetchCubit<_TeamsData>(() async {
      final results = await Future.wait([
        context.read<TeamRepository>().teams(),
        context.read<UserRepository>().users(),
      ]);
      final teams = results[0] as List<Team>;
      final users = results[1] as List<DirectoryUser>;
      final names = {for (final u in users) u.id: u.displayName};
      final avatars = {
        for (final u in users)
          if (u.avatarUrl != null && u.avatarUrl!.isNotEmpty)
            u.id: u.avatarUrl!,
      };
      return (teams: teams, names: names, avatars: avatars);
    })..load();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  Future<void> _create() async {
    final created = await showCreateTeamModal(context);
    if (created != null && mounted) {
      await _cubit.load();
      if (mounted) context.go('/teams/${created.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<FetchCubit<_TeamsData>, FetchState<_TeamsData>>(
        builder: (context, state) {
          final teams = state.data?.teams ?? const <Team>[];
          final names = state.data?.names ?? const <String, String>{};
          final avatars = state.data?.avatars ?? const <String, String>{};
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
                      title: context.t('teams.title'),
                      subtitle: context.t(
                        'teams.summary',
                        variables: {'count': '${teams.length}'},
                        count: teams.length,
                      ),
                      actions: [
                        PrimaryButton(
                          label: context.t('teams.new'),
                          onPressed: _create,
                        ),
                      ],
                    ),
                  ),
                ),
                if (state.isLoading && teams.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: HiveLoader()),
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
                        mainAxisExtent: 206,
                      ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        if (index == teams.length) {
                          return _NewTeamCard(onTap: _create);
                        }
                        return _TeamCard(
                          team: teams[index],
                          names: names,
                          avatars: avatars,
                        );
                      }, childCount: teams.length + 1),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({
    required this.team,
    required this.names,
    required this.avatars,
  });

  final Team team;
  final Map<String, String> names;
  final Map<String, String> avatars;

  @override
  Widget build(BuildContext context) {
    // Resolve "my" membership for the role badge.
    final myId = context.read<AuthBloc>().state.user?.id;
    final mine = team.membershipOf(myId);
    final memberNames = team.members
        .map((m) => names[m.userId] ?? m.userId)
        .toList();
    final memberAvatars = team.members.map((m) => avatars[m.userId]).toList();

    return SoftCard(
      onTap: () => context.go('/teams/${team.id}'),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TeamGlyph(team: team),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      team.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${team.key} · ${context.t('teams.memberCount', variables: {'count': '${team.members.length}'}, count: team.members.length)}',
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
              if (mine != null) ...[
                const SizedBox(width: 8),
                RoleBadge(role: mine.role, compact: true),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if ((team.description ?? '').isNotEmpty)
            Text(
              team.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.8,
                height: 1.5,
                color: AppColors.inkSoft,
              ),
            ),
          const Spacer(),
          Divider(height: 1, color: AppColors.hairline2),
          const SizedBox(height: 12),
          Row(
            children: [
              if (memberNames.isNotEmpty)
                HiveAvatarStack(
                  names: memberNames,
                  imageUrls: memberAvatars,
                  size: 26,
                ),
              const SizedBox(width: 14),
              Icon(LucideIcons.folder, size: 14, color: AppColors.inkFaint),
              const SizedBox(width: 5),
              Text(
                '${team.projectIds.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkSoft,
                ),
              ),
              const Spacer(),
              Icon(LucideIcons.arrowRight, size: 16, color: AppColors.inkSoft),
            ],
          ),
        ],
      ),
    );
  }
}

class _NewTeamCard extends StatelessWidget {
  const _NewTeamCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: DottedReplacementBorder(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  LucideIcons.plus,
                  size: 22,
                  color: AppColors.accentStrong,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                context.t('teams.new'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  context.t('teams.newHint'),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: AppColors.inkFaint,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dashed-border container for the "New team" card.
class DottedReplacementBorder extends StatelessWidget {
  const DottedReplacementBorder({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: AppColors.hairline,
          width: 1.5,
          style: BorderStyle.solid,
        ),
      ),
      child: Center(child: child),
    );
  }
}
