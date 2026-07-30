import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/git_dev_info.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/hue_colors.dart';
import '../../../core/widgets/hive_widgets.dart';
import '../git_tokens.dart';

/// A hue-tinted rounded glyph tile used at the head of each development row.
class DevGlyph extends StatelessWidget {
  const DevGlyph({
    super.key,
    required this.hue,
    required this.icon,
    this.size = 26,
  });

  final int hue;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hueSoft(hue),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, size: size * 0.58, color: hueInk(hue)),
    );
  }
}

/// A compact state pill (PR/MR state or checks/build status).
class StatePill extends StatelessWidget {
  const StatePill({
    super.key,
    required this.hue,
    required this.icon,
    required this.label,
  });

  final int hue;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final fg = hueChipText(hue);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: hueSoft(hue),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniChecks extends StatelessWidget {
  const _MiniChecks({required this.status});

  final CheckState status;

  @override
  Widget build(BuildContext context) {
    final s = checkStyle(context, status);
    final c = hueChipText(s.hue);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(s.icon, size: 12, color: c),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            s.label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: c,
            ),
          ),
        ),
      ],
    );
  }
}

/// Shared row shell: glyph + main column (title row + wrapping meta) + actions.
class _DevRow extends StatelessWidget {
  const _DevRow({
    required this.glyph,
    required this.top,
    required this.sub,
    this.actions,
  });

  final Widget glyph;
  final Widget top;
  final List<Widget> sub;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: glyph),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                top,
                const SizedBox(height: 3),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: sub,
                ),
              ],
            ),
          ),
          if (actions != null) ...[const SizedBox(width: 6), actions!],
        ],
      ),
    );
  }
}

Widget _subText(String text) =>
    Text(text, style: TextStyle(fontSize: 11, color: AppColors.inkFaint));

Widget _avatar(
  String? id,
  Map<String, String> names,
  Map<String, String> avatars,
) => HiveAvatar(
  name: id == null ? '·' : (names[id] ?? '·'),
  imageUrl: id == null ? null : avatars[id],
  size: 16,
);

class BranchRow extends StatelessWidget {
  const BranchRow({
    super.key,
    required this.branch,
    required this.names,
    required this.avatars,
    required this.onOpen,
  });

  final GitBranch branch;
  final Map<String, String> names;
  final Map<String, String> avatars;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return _DevRow(
      glyph: const DevGlyph(hue: kHueBranch, icon: LucideIcons.gitBranch),
      top: Text(
        branch.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: AppTheme.fontMono,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
      sub: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${branch.ahead}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const TextSpan(text: '↑  '),
              TextSpan(
                text: '${branch.behind}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const TextSpan(text: '↓'),
            ],
          ),
          style: TextStyle(
            fontFamily: AppTheme.fontMono,
            fontSize: 10.5,
            color: AppColors.inkSoft,
          ),
        ),
        _subText(context.t('git.branchFrom', variables: {'base': branch.base})),
        if (branch.updatedAt != null)
          _subText(
            '· ${context.t('git.updated', variables: {'ago': agoSuffixed(branch.updatedAt)})}',
          ),
        _avatar(branch.authorId, names, avatars),
      ],
      actions: _OpenButton(tooltip: context.t('git.openBranch'), onTap: onOpen),
    );
  }
}

class CommitRow extends StatelessWidget {
  const CommitRow({
    super.key,
    required this.commit,
    required this.names,
    required this.avatars,
    required this.onOpen,
  });

  final GitCommit commit;
  final Map<String, String> names;
  final Map<String, String> avatars;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return InkWell(onTap: onOpen, child: _row(context));
  }

  Widget _row(BuildContext context) {
    return _DevRow(
      glyph: const DevGlyph(
        hue: kHueCommit,
        icon: LucideIcons.gitCommitHorizontal,
      ),
      actions: _OpenButton(tooltip: context.t('git.openCommit'), onTap: onOpen),
      top: Text(
        commit.message,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
      sub: [
        Text(
          commit.sha,
          style: const TextStyle(
            fontFamily: AppTheme.fontMono,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.accentStrong,
          ),
        ),
        if (commit.verified)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.badgeCheck,
                size: 12,
                color: AppColors.success,
              ),
              const SizedBox(width: 3),
              Text(
                context.t('git.verified'),
                style: const TextStyle(fontSize: 11, color: AppColors.success),
              ),
            ],
          ),
        _avatar(commit.authorId, names, avatars),
        if (commit.at != null) _subText(agoSuffixed(commit.at)),
        // Only surface the counts that actually changed — a bare +0 or −0 is
        // noise (matches how Git itself omits zero-line sides).
        if (commit.additions > 0 || commit.deletions > 0)
          Text.rich(
            TextSpan(
              children: [
                if (commit.additions > 0)
                  TextSpan(
                    text: '+${commit.additions}',
                    style: const TextStyle(color: AppColors.success),
                  ),
                if (commit.additions > 0 && commit.deletions > 0)
                  const TextSpan(text: ' '),
                if (commit.deletions > 0)
                  TextSpan(
                    text: '−${commit.deletions}',
                    style: const TextStyle(color: AppColors.danger),
                  ),
              ],
            ),
            style: const TextStyle(fontFamily: AppTheme.fontMono, fontSize: 11),
          ),
      ],
    );
  }
}

class PrRow extends StatelessWidget {
  const PrRow({
    super.key,
    required this.pr,
    required this.provider,
    required this.names,
    required this.avatars,
    required this.onMerge,
    required this.onReady,
    required this.onOpen,
    required this.busy,
  });

  final GitPullRequest pr;
  final GitProvider provider;
  final Map<String, String> names;
  final Map<String, String> avatars;
  final VoidCallback onMerge;
  final VoidCallback onReady;
  final VoidCallback onOpen;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final style = prStateStyle(context, pr.state);
    return _DevRow(
      glyph: DevGlyph(hue: style.hue, icon: style.icon),
      top: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: Text(
              pr.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '#${pr.number}',
            style: TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 11,
              color: AppColors.inkFaint,
            ),
          ),
        ],
      ),
      sub: [
        StatePill(hue: style.hue, icon: style.icon, label: style.label),
        if (pr.reviewerIds.isNotEmpty)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HiveAvatarStack(
                names: [for (final id in pr.reviewerIds) names[id] ?? '·'],
                imageUrls: [for (final id in pr.reviewerIds) avatars[id]],
                size: 17,
                max: 3,
              ),
              if (pr.approvals > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '✓${pr.approvals}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.success,
                  ),
                ),
              ],
              if (pr.changesRequested > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '±${pr.changesRequested}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.danger,
                  ),
                ),
              ],
            ],
          ),
        _MiniChecks(status: pr.checks),
        if (pr.at != null) _subText(agoSuffixed(pr.at)),
        // The action lives in the wrapping meta area (not a fixed right column)
        // so it reflows below the pills on a narrow rail instead of squeezing
        // them into an overflow.
        if (pr.state == PrState.draft)
          _GhostAction(
            label: context.t('git.ready'),
            onTap: busy ? null : onReady,
          ),
        if (pr.state == PrState.open)
          _GhostAction(
            label: context.t('git.merge'),
            icon: LucideIcons.gitMerge,
            onTap: busy ? null : onMerge,
          ),
      ],
      actions: _OpenButton(
        tooltip: context.t('git.openPr', variables: {'pr': provider.prShort}),
        onTap: onOpen,
      ),
    );
  }
}

class BuildRow extends StatelessWidget {
  const BuildRow({super.key, required this.run});

  final GitBuild run;

  @override
  Widget build(BuildContext context) {
    final s = checkStyle(context, run.status);
    return _DevRow(
      glyph: DevGlyph(hue: s.hue, icon: s.icon),
      top: Text(
        run.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
      sub: [
        Text(
          run.workflow,
          style: TextStyle(
            fontFamily: AppTheme.fontMono,
            fontSize: 11,
            color: AppColors.inkFaint,
          ),
        ),
        _subText('· ${run.branch}'),
        if (run.duration != null) _subText('· ${run.duration}'),
        if (run.at != null) _subText('· ${agoSuffixed(run.at)}'),
      ],
      actions: StatePill(hue: s.hue, icon: s.icon, label: s.label),
    );
  }
}

class _OpenButton extends StatelessWidget {
  const _OpenButton({required this.tooltip, required this.onTap});

  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        iconSize: 15,
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        icon: Icon(LucideIcons.externalLink, color: AppColors.inkFaint),
      ),
    );
  }
}

/// Small bordered empty-state box (`.gd-empty`) shared by the Development
/// summary and the not-connected Deployment prompt.
class GitEmptyBox extends StatelessWidget {
  const GitEmptyBox({
    super.key,
    required this.icon,
    required this.child,
    this.action,
  });

  final IconData icon;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.canvas2,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 18, color: AppColors.inkSoft),
          ),
          const SizedBox(height: 8),
          DefaultTextStyle.merge(
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppColors.inkSoft,
            ),
            child: child,
          ),
          if (action != null) ...[const SizedBox(height: 10), action!],
        ],
      ),
    );
  }
}

class _GhostAction extends StatelessWidget {
  const _GhostAction({required this.label, required this.onTap, this.icon});

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: AppColors.ink,
        ),
        icon: icon == null
            ? const SizedBox.shrink()
            : Icon(icon, size: 13, color: AppColors.ink),
        label: Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
