import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../events/issue_events.dart';
import '../i18n/i18n.dart';
import '../models/work_models.dart';
import '../repositories/issue_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'hive_widgets.dart';

/// A compact "has sub-tasks" chip — the list-tree glyph plus a `done/total`
/// count — shown on issue-list rows and backlog rows so a parent issue is
/// recognizable at a glance. Renders nothing when the issue has no children.
///
/// The counts come from the server-enriched [Issue.subtaskCount] /
/// [Issue.subtaskDoneCount] (board + issue-list payloads), so this needs no
/// fetch of its own.
class SubtaskBadge extends StatelessWidget {
  const SubtaskBadge({super.key, required this.issue});

  final Issue issue;

  @override
  Widget build(BuildContext context) {
    if (!issue.hasSubtasks) return const SizedBox.shrink();
    final complete =
        issue.subtaskDoneCount >= issue.subtaskCount && issue.subtaskCount > 0;
    final color = complete ? AppColors.success : AppColors.inkSoft;
    return Tooltip(
      message: context.t(
        'issues.progressDone',
        variables: {
          'done': '${issue.subtaskDoneCount}',
          'total': '${issue.subtaskCount}',
        },
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.listTree, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              '${issue.subtaskDoneCount}/${issue.subtaskCount}',
              style: TextStyle(
                fontFamily: AppTheme.fontMono,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline, on-demand sub-task section for a board card (Kanban & Scrum). Shows a
/// tappable bar — list-tree glyph · "Sub-Tasks" · a `done/total` progress bar ·
/// chevron — and, when expanded, lazily fetches the parent's direct children
/// (via `GET /issues/{id}/hierarchy`) and lists them as tappable mini-rows so
/// you can jump straight to a sub-task without opening the parent first.
///
/// Renders nothing when the issue has no children. The progress bar uses the
/// already-known enriched counts, so it's correct before the list loads.
///
/// The fetched children are cached, but only until the next issue change
/// anywhere in the app ([IssueEvents]): a sub-task added, renamed, ticked off or
/// deleted in the issue detail would otherwise leave this list showing what it
/// read the first time it was opened. An expanded section re-fetches right away;
/// a collapsed one just drops its cache and re-fetches on the next open.
class SubtaskExpander extends StatefulWidget {
  const SubtaskExpander({
    super.key,
    required this.issue,
    required this.onOpenChild,
  });

  final Issue issue;

  /// Opens a child sub-task (typically the same handler the board uses for its
  /// cards) so navigation stays consistent with the rest of the board.
  final void Function(Issue child) onOpenChild;

  @override
  State<SubtaskExpander> createState() => _SubtaskExpanderState();
}

class _SubtaskExpanderState extends State<SubtaskExpander> {
  bool _expanded = false;
  bool _loading = false;
  bool _failed = false;
  List<Issue>? _children;
  StreamSubscription<void>? _issueSub;

  @override
  void initState() {
    super.initState();
    _issueSub = IssueEvents.instance.changes.listen((_) => _invalidate());
  }

  @override
  void dispose() {
    _issueSub?.cancel();
    super.dispose();
  }

  /// Drops the cached children after an issue changed elsewhere. Re-reads them
  /// immediately while open (the rows are on screen); otherwise the next expand
  /// fetches fresh.
  void _invalidate() {
    if (!mounted) return;
    if (_expanded) {
      _load(silent: _children != null);
    } else {
      setState(() {
        _children = null;
        _failed = false;
      });
    }
  }

  Future<void> _toggle() async {
    final next = !_expanded;
    setState(() => _expanded = next);
    if (next && _children == null && !_loading) {
      await _load();
    }
  }

  /// Fetches the direct children. A [silent] refresh keeps the rows already on
  /// screen in place instead of swapping them for a spinner — used when the
  /// section is open and something changed underneath it.
  Future<void> _load({bool silent = false}) async {
    setState(() {
      _loading = !silent;
      _failed = false;
    });
    try {
      final hierarchy = await context.read<IssueRepository>().issueHierarchy(
        widget.issue.id,
      );
      if (!mounted) return;
      setState(() {
        _children = hierarchy.children;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final issue = widget.issue;
    if (!issue.hasSubtasks) return const SizedBox.shrink();
    final total = issue.subtaskCount;
    final done = issue.subtaskDoneCount;
    final complete = done >= total && total > 0;
    final barColor = complete ? AppColors.success : AppColors.accent;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 1, color: AppColors.hairline),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.listTree,
                    size: 14,
                    color: AppColors.inkSoft,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    context.t('issues.subtasks'),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: HiveProgress(
                      value: total == 0 ? 0 : done / total,
                      color: barColor,
                      height: 5,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$done/$total',
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft,
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      LucideIcons.chevronDown,
                      size: 16,
                      color: AppColors.inkFaint,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _expanded
              ? _body(context)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _load,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(LucideIcons.refreshCw, size: 14),
            label: Text(context.t('common.retry')),
          ),
        ),
      );
    }
    final children = _children ?? const <Issue>[];
    if (children.isEmpty) {
      return const SizedBox(width: double.infinity);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final child in children)
            _SubtaskMiniRow(
              issue: child,
              onTap: () => widget.onOpenChild(child),
            ),
        ],
      ),
    );
  }
}

/// A single child sub-task under an expanded board card: type glyph · id ·
/// title · state dot. Tapping opens that sub-task's detail.
class _SubtaskMiniRow extends StatelessWidget {
  const _SubtaskMiniRow({required this.issue, required this.onTap});

  final Issue issue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          child: Row(
            children: [
              TypeGlyph(type: issue.type, size: 15),
              const SizedBox(width: 7),
              IdMono(issue.readableId, fontSize: 10.5),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  issue.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.stateColor(issue.state.toUpperCase()),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
