import 'package:flutter/material.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/work_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../sprint_tokens.dart';

/// Story points of an issue (0 when unestimated).
int pointsOf(Issue issue) => issue.storyPoints ?? 0;

int sumPoints(Iterable<Issue> issues) =>
    issues.fold(0, (sum, i) => sum + pointsOf(i));

/// Workflow bucket used for the point-bucket pills and capacity bar. Done is
/// driven by the issue's resolved flag; the rest is split heuristically by
/// state name so it works for any project workflow.
enum WorkBucket { todo, progress, done }

WorkBucket bucketOf(Issue issue) {
  if (issue.resolved) return WorkBucket.done;
  final s = issue.state.toLowerCase();
  if (s.contains('progress') || s.contains('review') || s.contains('doing')) {
    return WorkBucket.progress;
  }
  return WorkBucket.todo;
}

({int todo, int progress, int done}) bucketPoints(Iterable<Issue> issues) {
  var todo = 0, progress = 0, done = 0;
  for (final i in issues) {
    final p = pointsOf(i);
    switch (bucketOf(i)) {
      case WorkBucket.todo:
        todo += p;
      case WorkBucket.progress:
        progress += p;
      case WorkBucket.done:
        done += p;
    }
  }
  return (todo: todo, progress: progress, done: done);
}

/// Three mono pills: Σ points in to-do / in-progress / done.
class PointBuckets extends StatelessWidget {
  const PointBuckets({super.key, required this.issues});

  final List<Issue> issues;

  @override
  Widget build(BuildContext context) {
    final b = bucketPoints(issues);
    Widget pill(int v, Color c) => Container(
      constraints: const BoxConstraints(minWidth: 26),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      alignment: Alignment.center,
      child: Text(
        '$v',
        style: const TextStyle(
          fontFamily: AppTheme.fontMono,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        pill(b.todo, SprintTokens.todo),
        const SizedBox(width: 6),
        pill(b.progress, SprintTokens.progress),
        const SizedBox(width: 6),
        pill(b.done, SprintTokens.done),
      ],
    );
  }
}

/// Capacity bar: committed (done/prog/todo) vs. capacity, flagged red when over.
class CapacityBar extends StatelessWidget {
  const CapacityBar({
    super.key,
    required this.issues,
    required this.capacity,
    this.width = 188,
  });

  final List<Issue> issues;
  final int? capacity;
  final double width;

  @override
  Widget build(BuildContext context) {
    final b = bucketPoints(issues);
    final committed = b.todo + b.progress + b.done;
    final cap = capacity ?? 0;
    final over = cap > 0 && committed > cap;
    final denom = [committed, cap, 1].reduce((a, c) => a > c ? a : c);
    int flex(int v) => denom == 0 ? 0 : ((v / denom) * 1000).round();

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                context.t('sprint.capacity'),
                style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft),
              ),
              const Spacer(),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$committed',
                      style: TextStyle(
                        fontFamily: AppTheme.fontMono,
                        fontWeight: FontWeight.w600,
                        color: over ? AppColors.danger : AppColors.ink,
                      ),
                    ),
                    TextSpan(
                      text: cap > 0 ? ' / $cap pts' : ' pts',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          // A defined pill track (surface fill + hairline border) with the
          // done/in-progress/todo segments filling it; the uncovered part is
          // the track itself, so remaining capacity reads as the empty pill
          // (mirrors `.cap-bar` in sprint.css).
          Container(
            height: 8,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              children: [
                if (b.done > 0)
                  Expanded(
                    flex: flex(b.done),
                    child: const ColoredBox(color: SprintTokens.done),
                  ),
                if (b.progress > 0)
                  Expanded(
                    flex: flex(b.progress),
                    child: const ColoredBox(color: SprintTokens.progress),
                  ),
                if (b.todo > 0)
                  Expanded(
                    flex: flex(b.todo),
                    child: ColoredBox(
                      color: over ? SprintTokens.over : SprintTokens.todo,
                    ),
                  ),
                // Remaining capacity = the empty pill track showing through.
                if (denom > committed)
                  Expanded(
                    flex: flex(denom - committed),
                    child: const SizedBox(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
