import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/team_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/entity_avatar.dart';

// ════════════════════════════════════════════════════════════════════════
//  Teams design kit — glyphs, role/access chips, the shared hue palette and
//  the lucide→Material icon map. Built from the Hive tokens (AppColors).
// ════════════════════════════════════════════════════════════════════════

/// One option in the team color picker. [hue] is the stored oklch hue.
class TeamSwatch {
  const TeamSwatch(this.hue, this.nameKey);
  final int hue;
  final String nameKey;
}

const teamSwatches = <TeamSwatch>[
  TeamSwatch(70, 'teams.color.honey'),
  TeamSwatch(250, 'teams.color.indigo'),
  TeamSwatch(300, 'teams.color.violet'),
  TeamSwatch(200, 'teams.color.teal'),
  TeamSwatch(155, 'teams.color.green'),
  TeamSwatch(20, 'teams.color.coral'),
];

const teamIconNames = <String>[
  'hexagon',
  'smartphone',
  'server',
  'book-open',
  'rocket',
  'palette',
  'shield',
  'globe',
  'code-xml',
  'layers',
];

const _iconMap = <String, IconData>{
  'hexagon': LucideIcons.hexagon,
  'smartphone': LucideIcons.smartphone,
  'server': LucideIcons.server,
  'book-open': LucideIcons.bookOpen,
  'rocket': LucideIcons.rocket,
  'palette': LucideIcons.palette,
  'shield': LucideIcons.shield,
  'globe': LucideIcons.globe,
  'code-xml': LucideIcons.code,
  'layers': LucideIcons.layers,
};

IconData teamIcon(String name) => _iconMap[name] ?? LucideIcons.hexagon;

/// Ink color for a team/palette hue (≈ oklch(0.55 0.13 hue)). Known palette
/// hues are mapped to hand-tuned tokens; anything else falls back to HSL.
Color teamHueColor(int hue) => switch (hue) {
  70 => AppColors.accentStrong,
  250 => const Color(0xFF5B6FD6),
  300 => AppColors.stReview,
  200 => const Color(0xFF2E9BA8),
  155 => AppColors.stDone,
  20 => AppColors.priUrgent,
  _ => HSLColor.fromAHSL(1, (hue % 360).toDouble(), 0.5, 0.52).toColor(),
};

/// Hex string for a hue — used when creating a project (server stores hex).
String teamHueHex(int hue) {
  final c = teamHueColor(hue);
  final argb = c.toARGB32();
  return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// Parse a project's stored hex color, falling back to a neutral indigo.
Color projectHexColor(String? hex) {
  final raw = (hex ?? '').replaceAll('#', '').trim();
  if (raw.length == 6) {
    final value = int.tryParse(raw, radix: 16);
    if (value != null) return Color(0xFF000000 | value);
  }
  return const Color(0xFF5B6FD6);
}

/// Tinted rounded-square team glyph with the team's icon — or the team's
/// uploaded picture, in the very same footprint.
///
/// Every place a team is shown already builds this, so teaching the glyph about
/// [Team.avatarUrl] is what makes the picture appear on the overview cards, the
/// detail header and the pickers at once, instead of threading a new widget
/// through each of them.
class TeamGlyph extends StatelessWidget {
  const TeamGlyph({
    super.key,
    required this.team,
    this.size = 44,
    this.radius = 13,
  });

  final Team team;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return EntityAvatar(
      avatarUrl: team.avatarUrl,
      size: size,
      radius: radius,
      fallback: TeamIconGlyph(
        icon: team.icon,
        color: teamHueColor(team.colorHue),
        size: size,
        radius: radius,
      ),
    );
  }
}

/// The icon-only team glyph, without the picture lookup.
///
/// Split out of [TeamGlyph] so the forms that preview a *not yet saved* colour
/// and icon (the create/edit modal) can draw exactly the same square from loose
/// values instead of inventing their own.
class TeamIconGlyph extends StatelessWidget {
  const TeamIconGlyph({
    super.key,
    required this.icon,
    required this.color,
    this.size = 44,
    this.radius = 13,
  });

  final String icon;
  final Color color;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.soft(color),
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Icon(teamIcon(icon), size: size * 0.46, color: color),
    );
  }
}

/// Key-letter glyph for a project (mono key on a tinted square) — or the
/// project's uploaded picture, in the very same footprint.
///
/// [avatarUrl] is optional because this glyph is also drawn for things that are
/// not a saved project yet (the key being typed in the create form), and for
/// project ids a caller only knows by key and colour.
class ProjectKeyGlyph extends StatelessWidget {
  const ProjectKeyGlyph({
    super.key,
    required this.label,
    required this.color,
    this.avatarUrl,
    this.size = 36,
    this.radius = 10,
    this.fontSize = 12,
  });

  final String label;
  final Color color;

  /// Server-owned picture URL of the project, when there is one.
  final String? avatarUrl;
  final double size;
  final double radius;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return EntityAvatar(
      avatarUrl: avatarUrl,
      size: size,
      radius: radius,
      fallback: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.soft(color),
          borderRadius: BorderRadius.circular(radius),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontFamily: AppTheme.fontMono,
            fontWeight: FontWeight.w600,
            fontSize: fontSize,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// Role pill (Team-Admin = honey, Member = indigo).
class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.role, this.compact = false});

  final TeamRole role;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final admin = role == TeamRole.admin;
    final color = admin ? AppColors.accentStrong : const Color(0xFF5B6FD6);
    final label = admin
        ? context.t(compact ? 'teams.role.adminShort' : 'teams.role.admin')
        : context.t('teams.role.member');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.soft(color),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            admin ? LucideIcons.shieldCheck : LucideIcons.user,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline access chip: icon + "All projects" / "N projects" / "No projects".
class AccessChip extends StatelessWidget {
  const AccessChip({super.key, required this.team, required this.membership});

  final Team team;
  final TeamMembership membership;

  @override
  Widget build(BuildContext context) {
    final scope = membership.access.scope;
    final (IconData icon, Color color, String label) = switch (scope) {
      AccessScope.all => (
        LucideIcons.layers,
        AppColors.stDone,
        context.t('teams.access.all'),
      ),
      AccessScope.none => (
        LucideIcons.lock,
        AppColors.inkSoft,
        context.t('teams.access.none'),
      ),
      AccessScope.some => () {
        final n = membership.access.projectIds
            .where(team.projectIds.contains)
            .length;
        return (
          LucideIcons.folderOpen,
          AppColors.accentStrong,
          context.t(
            'teams.access.someCount',
            variables: {'count': '$n'},
            count: n,
          ),
        );
      }(),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// Overview KPI tile (icon badge · big number · label).
///
/// Tappable when [onTap] is provided — jumps to the related detail tab
/// (projects, members, …). Purely decorative when omitted.
class TeamKpi extends StatelessWidget {
  const TeamKpi({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.hue,
    this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final int hue;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = teamHueColor(hue);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.hairline),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.soft(color),
                borderRadius: BorderRadius.circular(11),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTheme.fontBrand,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
