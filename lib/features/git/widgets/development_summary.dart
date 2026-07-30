import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_client.dart';
import '../../../core/repositories/git_repository.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/git_connection.dart';
import '../../../core/models/git_dev_info.dart';
import '../../../core/models/work_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../sprint/modals/glass_modal.dart'
    show GlassToastKind, showGlassToast;
import '../git_tokens.dart';
import 'dev_rows.dart';

/// Issue main-column summary: the auto-linked git activity for the issue,
/// categorised into Branches · Commits · Pull/Merge requests · Builds. Fetches
/// its own [DevInfo]; PR/MR merge & ready actions run real optimistic
/// transitions reconciled against the server (which applies the project's
/// automation rules).
class DevelopmentSummary extends StatefulWidget {
  const DevelopmentSummary({
    super.key,
    required this.issue,
    required this.project,
    required this.names,
    required this.avatars,
    required this.onIssueChanged,
  });

  final Issue issue;
  final Project project;
  final Map<String, String> names;
  final Map<String, String> avatars;
  final ValueChanged<Issue> onIssueChanged;

  @override
  State<DevelopmentSummary> createState() => _DevelopmentSummaryState();
}

class _DevelopmentSummaryState extends State<DevelopmentSummary> {
  DevInfo? _info;
  bool _loading = true;
  bool _busy = false;
  String? _openKey;

  GitRepository get _repo => context.read<GitRepository>();
  GitProvider get _prov =>
      gitProviderFrom(widget.project.git?.provider) ?? GitProvider.github;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(DevelopmentSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.issue.readableId != widget.issue.readableId) _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final info = await _repo.gitDevInfo(widget.issue.readableId);
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
        _openKey = _firstOpenKey(info);
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _firstOpenKey(DevInfo i) {
    for (final g in _group(i)) {
      if (g.branches.isNotEmpty) return '${g.key}/branches';
      if (g.commits.isNotEmpty) return '${g.key}/commits';
      if (g.prs.isNotEmpty) return '${g.key}/prs';
      if (g.builds.isNotEmpty) return '${g.key}/builds';
    }
    return null;
  }

  /// Splits the issue's dev info into one group per source repository, using the
  /// per-item `provider`/`repo` attribution (multi-repo). Items without
  /// attribution (legacy dev info) fall back to the project's primary repo.
  List<_RepoGroup> _group(DevInfo info) {
    final map = <String, _RepoGroup>{};
    final order = <String>[];
    final git = widget.project.git;
    final fallbackRepo = git == null ? '' : '${git.owner}/${git.repo}';
    _RepoGroup groupFor(String? provId, String? repo) {
      final prov = gitProviderFrom(provId) ?? _prov;
      final slug = (repo == null || repo.isEmpty) ? fallbackRepo : repo;
      final key = '${prov.id}|$slug';
      return map.putIfAbsent(key, () {
        order.add(key);
        return _RepoGroup(prov, slug);
      });
    }

    for (final b in info.branches) {
      groupFor(b.provider, b.repo).branches.add(b);
    }
    for (final c in info.commits) {
      groupFor(c.provider, c.repo).commits.add(c);
    }
    for (final p in info.prs) {
      groupFor(p.provider, p.repo).prs.add(p);
    }
    for (final b in info.builds) {
      groupFor(b.provider, b.repo).builds.add(b);
    }
    return [for (final k in order) map[k]!];
  }

  /// Opens a provider web URL (branch / commit / PR) in the external browser.
  Future<void> _open(String? url) async {
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      _toast(context.t('git.couldNotOpen', variables: {'url': url}));
    }
  }

  void _toast(String message, {GlassToastKind kind = GlassToastKind.error}) {
    showGlassToast(context, message, kind: kind);
  }

  String _message(Object e) =>
      e is ApiFailure ? e.message : context.t('git.genericError');

  String _transitionNote(GitRule rule) {
    if (!rule.on || rule.toStateId == null) return '';
    for (final s in widget.project.workflowStates) {
      if (s.id == rule.toStateId) return ' → ${s.name}';
    }
    return '';
  }

  Future<void> _merge(GitPullRequest pr) => _prAction(
    pr,
    PrState.merged,
    () => _repo.gitMergePr(widget.issue.readableId, pr.number),
    _transitionNote(widget.project.git!.automation.prMerged),
    'git.prMergedToast',
  );

  Future<void> _ready(GitPullRequest pr) => _prAction(
    pr,
    PrState.open,
    () => _repo.gitReadyPr(widget.issue.readableId, pr.number),
    _transitionNote(widget.project.git!.automation.prOpened),
    'git.prReadyToast',
  );

  Future<void> _prAction(
    GitPullRequest pr,
    PrState optimistic,
    Future<({DevInfo devInfo, Issue issue})> Function() call,
    String note,
    String toastKey,
  ) async {
    final before = _info;
    if (before == null) return;
    setState(() {
      _busy = true;
      _info = before.withPr(pr.copyWith(state: optimistic));
    });
    try {
      final result = await call();
      if (!mounted) return;
      setState(() {
        _info = result.devInfo;
        _busy = false;
      });
      widget.onIssueChanged(result.issue);
      _toast(
        context.t(
          toastKey,
          variables: {
            'pr': _prov.prShort,
            'issue': widget.issue.readableId,
            'note': note,
          },
        ),
        kind: GlassToastKind.success,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _info = before;
          _busy = false;
        });
      }
      _toast(_message(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    // The sheet only mounts this when the project has a repo connected; while the
    // first fetch is in flight (or if it failed / is unconnected) render nothing.
    if (_loading && info == null) return const SizedBox.shrink();
    if (info == null || !info.connected) return const SizedBox.shrink();
    // Jira-style: the whole Development section stays hidden until there is
    // linked work (a branch, commit, PR/MR or build). No empty placeholder.
    if (!info.hasAny) return const SizedBox.shrink();

    final groups = _group(info);
    final single = groups.length == 1;
    // Owns its own leading gap so an empty (collapsed) section leaves no orphan
    // spacing in the sheet's main column.
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.t('git.development'),
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              // With one repo the chip rides in the header; with several, each
              // group gets its own chip sub-header below.
              if (single) Expanded(child: _repoChip(groups.first)),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < groups.length; i++) ...[
            if (!single) ...[
              if (i > 0) const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _repoChip(groups[i]),
                ),
              ),
            ],
            ..._categories(groups[i]),
          ],
        ],
      ),
    );
  }

  Widget _repoChip(_RepoGroup g) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: AppColors.success,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.success.withValues(alpha: 0.22),
                spreadRadius: 3,
              ),
            ],
          ),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            '${g.provider.label} · ${g.repo}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 12,
              color: AppColors.inkSoft,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _categories(_RepoGroup g) {
    final prov = g.provider;
    final cats = <Widget>[];
    void add(
      String key,
      String label,
      int hue,
      int count,
      Widget? badge,
      List<Widget> body,
    ) {
      if (count == 0) return;
      final fullKey = '${g.key}/$key';
      cats.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _DevCat(
            iconKey: key,
            label: label,
            hue: hue,
            count: count,
            badge: badge,
            open: _openKey == fullKey,
            onToggle: () =>
                setState(() => _openKey = _openKey == fullKey ? null : fullKey),
            body: body,
          ),
        ),
      );
    }

    add(
      'branches',
      context.t('git.branches'),
      kHueBranch,
      g.branches.length,
      null,
      [
        for (final b in g.branches)
          BranchRow(
            branch: b,
            names: widget.names,
            avatars: widget.avatars,
            onOpen: () => _open(gitBranchUrl(prov, g.repo, b.name)),
          ),
      ],
    );
    add(
      'commits',
      context.t('git.commits'),
      kHueCommit,
      g.commits.length,
      g.commits.isNotEmpty && g.commits.first.at != null
          ? Text(
              context.t(
                'git.latest',
                variables: {'ago': agoSuffixed(g.commits.first.at)},
              ),
              style: TextStyle(
                fontFamily: AppTheme.fontMono,
                fontSize: 11.5,
                color: AppColors.inkFaint,
              ),
            )
          : null,
      [
        for (final c in g.commits)
          CommitRow(
            commit: c,
            names: widget.names,
            avatars: widget.avatars,
            onOpen: () => _open(gitCommitUrl(prov, g.repo, c.sha)),
          ),
      ],
    );
    add(
      'prs',
      prov.prTermPlural,
      kHuePullRequest,
      g.prs.length,
      _prBadge(context, g.prs),
      [
        for (final pr in g.prs)
          PrRow(
            pr: pr,
            provider: prov,
            names: widget.names,
            avatars: widget.avatars,
            busy: _busy,
            onMerge: () => _merge(pr),
            onReady: () => _ready(pr),
            onOpen: () => _open(gitPrUrl(prov, g.repo, pr.number)),
          ),
      ],
    );
    add(
      'builds',
      context.t('git.builds'),
      kHueBuild,
      g.builds.length,
      _buildBadge(context, g.builds),
      [for (final b in g.builds) BuildRow(run: b)],
    );
    return cats;
  }

  Widget? _prBadge(BuildContext context, List<GitPullRequest> prs) {
    if (prs.isEmpty) return null;
    final s = prStateStyle(context, prs.first.state);
    return StatePill(hue: s.hue, icon: s.icon, label: s.label);
  }

  Widget? _buildBadge(BuildContext context, List<GitBuild> builds) {
    if (builds.isEmpty) return null;
    final s = checkStyle(context, builds.first.status);
    return StatePill(hue: s.hue, icon: s.icon, label: s.label);
  }
}

/// One source repository's slice of an issue's development info.
class _RepoGroup {
  _RepoGroup(this.provider, this.repo);

  final GitProvider provider;

  /// `owner/repo` slug of the source repository.
  final String repo;
  final List<GitBranch> branches = [];
  final List<GitCommit> commits = [];
  final List<GitPullRequest> prs = [];
  final List<GitBuild> builds = [];

  String get key => '${provider.id}|$repo';
}

class _DevCat extends StatelessWidget {
  const _DevCat({
    required this.iconKey,
    required this.label,
    required this.hue,
    required this.count,
    required this.badge,
    required this.open,
    required this.onToggle,
    required this.body,
  });

  /// Stable category token ('branches'|'commits'|'prs'|'builds') driving the
  /// glyph — decoupled from the (translated) [label].
  final String iconKey;
  final String label;
  final int hue;
  final int count;
  final Widget? badge;
  final bool open;
  final VoidCallback onToggle;
  final List<Widget> body;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              child: Row(
                children: [
                  DevGlyph(hue: hue, icon: categoryIcon(iconKey), size: 30),
                  const SizedBox(width: 11),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 11.5,
                      color: AppColors.inkFaint,
                    ),
                  ),
                  const Spacer(),
                  if (badge != null) ...[badge!, const SizedBox(width: 8)],
                  AnimatedRotation(
                    turns: open ? 0.25 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      LucideIcons.chevronRight,
                      size: 16,
                      color: AppColors.inkFaint,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.hairline2)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: body),
            ),
        ],
      ),
    );
  }
}
