part of 'team_tabs.dart';

// ═══════════════════════════════ Settings ═════════════════════════════════

class TeamSettingsTab extends StatelessWidget {
  const TeamSettingsTab({
    super.key,
    required this.data,
    required this.manage,
    required this.onReload,
  });

  final TeamDetailData data;
  final bool manage;
  final Future<void> Function() onReload;

  Future<void> _edit(BuildContext context) async {
    await showEditTeamModal(context, data.team);
    // Reload regardless of the outcome: the picture inside that modal is stored
    // the moment it is uploaded, independently of the form's save button, so
    // "cancelled" no longer implies "nothing changed".
    await onReload();
  }

  Future<void> _delete(BuildContext context) async {
    final deleted = await showDeleteTeamModal(context, data.team);
    // Go to a fresh teams overview so the deleted team is gone from the list.
    if (deleted == true && context.mounted) context.go('/teams');
  }

  @override
  Widget build(BuildContext context) {
    if (!manage) {
      return SoftCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Column(
            children: [
              Icon(LucideIcons.lock, size: 26, color: AppColors.inkSoft),
              const SizedBox(height: 10),
              Text(
                context.t('teams.adminsOnly'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.t('teams.adminsOnlyHint'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
      );
    }
    final team = data.team;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: context.t('teams.identity'),
                actionLabel: context.t('common.edit'),
                onAction: () => _edit(context),
              ),
              const SizedBox(height: 8),
              _SettingRow(
                k: context.t('teams.avatar.label'),
                vWidget: _TeamAvatarSetting(team: team, onReload: onReload),
              ),
              _SettingRow(k: context.t('teams.name'), v: team.name),
              _SettingRow(k: context.t('teams.key'), v: team.key, mono: true),
              _SettingRow(
                k: context.t('teams.description'),
                v: (team.description ?? '').isEmpty ? '—' : team.description!,
              ),
              _SettingRow(
                k: context.t('teams.colorLabel'),
                vWidget: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: teamHueColor(team.colorHue),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _hueName(context, team.colorHue),
                      style: TextStyle(fontSize: 13, color: AppColors.ink),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(title: context.t('teams.rolesPermissions')),
              const SizedBox(height: 6),
              _PermRow(
                icon: LucideIcons.shieldCheck,
                title: context.t('teams.role.admin'),
                body: context.t(
                  'teams.permAdmin',
                  variables: {'name': team.name},
                ),
              ),
              const SizedBox(height: 12),
              _PermRow(
                icon: LucideIcons.user,
                title: context.t('teams.role.member'),
                body: context.t('teams.permMember'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SoftCard(
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.45)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.t('teams.dangerZone'),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, c) {
                  final narrow = c.maxWidth < 460;
                  final text = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.t('teams.deleteThis'),
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        context.t('teams.deleteThisHint'),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ],
                  );
                  final btn = FilledButton.icon(
                    onPressed: () => _delete(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusControl,
                        ),
                      ),
                    ),
                    icon: const Icon(LucideIcons.trash2, size: 16),
                    label: Text(context.t('teams.deleteCta')),
                  );
                  return narrow
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [text, const SizedBox(height: 12), btn],
                        )
                      : Row(
                          children: [
                            Expanded(child: text),
                            const SizedBox(width: 16),
                            btn,
                          ],
                        );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _hueName(BuildContext context, int hue) {
    for (final s in teamSwatches) {
      if (s.hue == hue) return context.t(s.nameKey);
    }
    return context.t('teams.color.custom');
  }
}

/// The team picture in the settings identity card: tap to upload or remove.
///
/// Keeps the URL the upload answered with as a local override so the new
/// picture is on screen the instant it is stored, rather than one page reload
/// later — the reload still runs, to refresh the header glyph and the rest of
/// the detail page, and hands back the very same URL.
class _TeamAvatarSetting extends StatefulWidget {
  const _TeamAvatarSetting({required this.team, required this.onReload});

  final Team team;
  final Future<void> Function() onReload;

  @override
  State<_TeamAvatarSetting> createState() => _TeamAvatarSettingState();
}

class _TeamAvatarSettingState extends State<_TeamAvatarSetting> {
  String? _url;
  bool _local = false;

  @override
  void didUpdateWidget(_TeamAvatarSetting old) {
    super.didUpdateWidget(old);
    // A reload (ours or somebody else's edit) is the newer truth.
    if (old.team.avatarUrl != widget.team.avatarUrl) _local = false;
  }

  @override
  Widget build(BuildContext context) {
    final team = widget.team;
    final repo = context.read<TeamRepository>();
    return Row(
      children: [
        EntityAvatarField(
          avatarUrl: _local ? _url : team.avatarUrl,
          size: 64,
          radius: 18,
          strings: EntityAvatarStrings.team,
          fallback: TeamIconGlyph(
            icon: team.icon,
            color: teamHueColor(team.colorHue),
            size: 64,
            radius: 18,
          ),
          onUpload: (file) => repo.uploadTeamAvatar(team.id, file),
          onRemove: () => repo.deleteTeamAvatar(team.id),
          onChanged: (url) {
            setState(() {
              _url = url;
              _local = true;
            });
            widget.onReload();
          },
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            context.t('teams.avatar.hint'),
            style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
          ),
        ),
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.k, this.v, this.vWidget, this.mono = false});
  final String k;
  final String? v;
  final Widget? vWidget;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              k,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.inkSoft,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child:
                vWidget ??
                Text(
                  v ?? '',
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: mono ? AppTheme.fontMono : null,
                    color: AppColors.ink,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

class _PermRow extends StatelessWidget {
  const _PermRow({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.accentStrong),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                body,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
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
