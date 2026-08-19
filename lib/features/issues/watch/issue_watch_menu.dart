import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/work_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_popup_menu.dart';
import '../../../core/widgets/hive_widgets.dart';
import '../../search/search_tokens.dart';
import 'issue_watch_cubit.dart';

/// Everything the issue's "…" overflow menu needs to draw its watch section:
/// the cubit holding the roster, who is asking, and how to resolve the people
/// on it.
///
/// The lookups are functions rather than snapshots on purpose. The detail
/// aggregate ships only the users an issue *references* — watchers are hydrated
/// with the rest of the directory after first paint, and a map captured when
/// the top bar was built would leave the roster showing raw ids.
class IssueWatchMenuData {
  const IssueWatchMenuData({
    required this.cubit,
    required this.issue,
    required this.onToggle,
    required this.nameFor,
    required this.avatarFor,
  });

  final IssueWatchCubit cubit;

  /// The issue being watched — read for the implicit-notification hint below.
  final Issue issue;

  /// Subscribes or unsubscribes the caller. The host owns the outcome: the row
  /// that triggers this closes the menu on tap, so it has to say out loud what
  /// happened instead of flipping a control the user can still see.
  final VoidCallback onToggle;

  final String? Function(String userId) nameFor;
  final String? Function(String userId) avatarFor;

  /// The signed-in user, or null while the session is still resolving — taken
  /// from the cubit so the roster and the toggle can never disagree on who
  /// "you" is.
  String? get meId => cubit.userId;

  /// Why the row can read "start watching" while mail already arrives:
  /// assignees and the reporter are notified without ever subscribing.
  String? get implicitHintKey {
    final me = meId;
    if (me == null) return null;
    if (issue.assigneeIds.contains(me) || issue.assigneeId == me) {
      return 'issues.watch.implicitAssignee';
    }
    if (issue.reporterId == me) return 'issues.watch.implicitReporter';
    return null;
  }
}

/// The watch row for the "…" menu: one verb saying what the tap does, the way
/// Jira's watch action reads. Disabled rather than hidden while the session is
/// still resolving — there is nobody to subscribe yet.
GlassMenuItem<T> issueWatchMenuItem<T>(
  BuildContext context, {
  required T value,
  required bool watching,
  required bool enabled,
}) => GlassMenuItem<T>(
  value: value,
  label: context.t(watching ? 'issues.watch.stop' : 'issues.watch.start'),
  enabled: enabled,
  leading: Icon(
    watching ? LucideIcons.eye : LucideIcons.eyeOff,
    size: 16,
    color: watching ? AppColors.accentStrong : AppColors.inkSoft,
  ),
);

/// The watcher roster under the menu's actions — the block Jira shows beneath
/// its watch action, moved into the same popover so the top bar keeps a single
/// button. Listens to the cubit, so a toggle made from the other top bar (the
/// sheet and the route share one) is reflected without reopening.
class IssueWatchMenuFooter extends StatelessWidget {
  const IssueWatchMenuFooter({super.key, required this.data});

  final IssueWatchMenuData data;

  @override
  Widget build(BuildContext context) {
    final tokens = SearchTokens.of(Theme.of(context).brightness);
    return BlocBuilder<IssueWatchCubit, IssueWatchState>(
      bloc: data.cubit,
      builder: (context, state) {
        final me = data.meId;
        // "You" first, then everyone else in server order.
        final ordered = [
          if (me != null && state.watcherIds.contains(me)) me,
          for (final id in state.watcherIds)
            if (id != me) id,
        ];
        final hintKey = data.implicitHintKey;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              color: tokens.hairline,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 3, 10, 5),
              child: Text(
                context.t('issues.watch.watchersTitle'),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  color: tokens.inkFaint,
                ),
              ),
            ),
            if (hintKey != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(LucideIcons.info, size: 12, color: tokens.inkFaint),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        context.t(hintKey),
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: tokens.inkFaint,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (ordered.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                child: Text(
                  context.t('issues.watch.noWatchers'),
                  style: TextStyle(fontSize: 12, color: tokens.inkFaint),
                ),
              )
            else
              for (final id in ordered)
                _WatcherRow(
                  tokens: tokens,
                  // Watchers are the one group the detail aggregate does not
                  // ship users for, so the directory may not have resolved them
                  // (yet, or ever, for a deactivated account). An id is not a
                  // name — the avatar still takes it, where it renders as a
                  // neutral glyph.
                  name: data.nameFor(id),
                  avatarUrl: data.avatarFor(id),
                  isMe: id == me,
                  fallbackSeed: id,
                ),
          ],
        );
      },
    );
  }
}

/// One person on the roster, aligned with the action rows above it (the avatar
/// sits in the same 22dp slot their glyphs do).
class _WatcherRow extends StatelessWidget {
  const _WatcherRow({
    required this.tokens,
    required this.name,
    required this.avatarUrl,
    required this.isMe,
    required this.fallbackSeed,
  });

  final SearchTokens tokens;
  final String? name;
  final String? avatarUrl;
  final bool isMe;
  final String fallbackSeed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: [
          HiveAvatar(name: name ?? fallbackSeed, imageUrl: avatarUrl, size: 22),
          const SizedBox(width: 10),
          // Name and "you" marker share one line so the row can only ever
          // ellipsise, never overflow — the popover is narrow and a display
          // name has no length limit.
          Expanded(
            child: Text.rich(
              TextSpan(
                text: name ?? context.t('issues.watch.unknownWatcher'),
                children: [
                  if (isMe)
                    TextSpan(
                      text: ' · ${context.t('issues.watch.you')}',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: tokens.inkFaint,
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tokens.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
