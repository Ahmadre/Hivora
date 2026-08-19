import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/work_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_popup_menu.dart';
import '../../../core/widgets/hive_widgets.dart';
import '../../search/search_tokens.dart';
import '../../sprint/modals/glass_modal.dart'
    show
        kGlassPopoverBreakpoint,
        showGlassAnchoredPopover,
        showGlassBottomSheet;
import 'issue_watch_cubit.dart';

/// Everything the issue's watch popover needs: the cubit holding the roster,
/// who is asking, and how to resolve the people on it.
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

  /// Subscribes or unsubscribes the caller. The host owns the outcome: the flip
  /// here is optimistic, so only it can say the server actually took it.
  final VoidCallback onToggle;

  final String? Function(String userId) nameFor;
  final String? Function(String userId) avatarFor;

  /// The signed-in user, or null while the session is still resolving — taken
  /// from the cubit so the roster and the toggle can never disagree on who
  /// "you" is.
  String? get meId => cubit.userId;

  /// Why the toggle can read "start watching" while mail already arrives:
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

/// The "Watch" row in the issue's "…" menu. A door, not a switch — it opens
/// [showIssueWatchPopover], which is where the subscription and the roster
/// live, hence the chevron. The glyph still carries the current state so the
/// menu answers "am I watching this?" without being opened twice.
GlassMenuItem<T> issueWatchMenuItem<T>(
  BuildContext context, {
  required T value,
  required bool watching,
  required bool enabled,
}) => GlassMenuItem<T>(
  value: value,
  label: context.t('issues.watch.title'),
  enabled: enabled,
  leading: Icon(
    watching ? LucideIcons.eye : LucideIcons.eyeOff,
    size: 16,
    color: watching ? AppColors.accentStrong : AppColors.inkSoft,
  ),
  trailing: Icon(LucideIcons.chevronRight, size: 15, color: AppColors.inkFaint),
);

/// Opens the watch panel as a glass overlay of its own: anchored under the "…"
/// button on tablet/desktop (where the menu it came from stood), a bottom sheet
/// on phones — the same split every other picker in the app uses.
Future<void> showIssueWatchPopover(
  BuildContext context, {
  required Rect anchorRect,
  required IssueWatchMenuData data,
}) {
  Widget builder(BuildContext _) => IssueWatchPanel(data: data);
  if (MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint) {
    return showGlassAnchoredPopover<void>(
      context,
      anchorRect: anchorRect,
      width: 320,
      maxHeight: 440,
      builder: builder,
    );
  }
  return showGlassBottomSheet<void>(context, builder: builder);
}

/// Body of the watch popover: the subscribe/unsubscribe action, the note that
/// says why mail may already arrive without it, and who else is watching.
///
/// It stays open across a toggle on purpose — the panel *is* the feedback: the
/// action's verb flips and you appear in (or vanish from) the list under it.
class IssueWatchPanel extends StatelessWidget {
  const IssueWatchPanel({super.key, required this.data});

  final IssueWatchMenuData data;

  @override
  Widget build(BuildContext context) {
    final tokens = SearchTokens.of(Theme.of(context).brightness);
    return BlocBuilder<IssueWatchCubit, IssueWatchState>(
      bloc: data.cubit,
      builder: (context, state) {
        final me = data.meId;
        final watching = state.isWatchedBy(me);
        final hintKey = data.implicitHintKey;
        // "You" first, then everyone else in server order.
        final ordered = [
          if (me != null && state.watcherIds.contains(me)) me,
          for (final id in state.watcherIds)
            if (id != me) id,
        ];
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 2),
              child: _ToggleRow(
                tokens: tokens,
                watching: watching,
                // Nobody to subscribe before the session resolves. Not disabled
                // while a call is out: the optimistic flip already reads as
                // done, and the cubit drops a second tap mid-flight.
                onTap: me == null ? null : data.onToggle,
              ),
            ),
            if (hintKey != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 2, 14, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(LucideIcons.info, size: 13, color: tokens.inkFaint),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        context.t(hintKey),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: tokens.inkFaint,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              height: 1,
              margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              color: tokens.hairline,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
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
            if (ordered.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                child: Text(
                  context.t('issues.watch.noWatchers'),
                  style: TextStyle(fontSize: 12.5, color: tokens.inkFaint),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 10),
                  itemCount: ordered.length,
                  itemBuilder: (context, i) {
                    final id = ordered[i];
                    return _WatcherRow(
                      tokens: tokens,
                      // Watchers are the one group the detail aggregate does
                      // not ship users for, so the directory may not have
                      // resolved them (yet, or ever, for a deactivated
                      // account). An id is not a name — the avatar still takes
                      // it, where it renders as a neutral glyph.
                      name: data.nameFor(id),
                      avatarUrl: data.avatarFor(id),
                      isMe: id == me,
                      fallbackSeed: id,
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The panel's one action, shaped like the menu row it was opened from: a
/// single verb saying what the tap does.
class _ToggleRow extends StatefulWidget {
  const _ToggleRow({
    required this.tokens,
    required this.watching,
    required this.onTap,
  });

  final SearchTokens tokens;
  final bool watching;
  final VoidCallback? onTap;

  @override
  State<_ToggleRow> createState() => _ToggleRowState();
}

class _ToggleRowState extends State<_ToggleRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final disabled = widget.onTap == null;
    final row = GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: _hover && !disabled ? t.rowHover : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Center(
                child: Icon(
                  widget.watching ? LucideIcons.eye : LucideIcons.eyeOff,
                  size: 17,
                  color: widget.watching
                      ? AppColors.accentStrong
                      : t.ink.withValues(alpha: disabled ? 0.4 : 1),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.t(
                  widget.watching ? 'issues.watch.stop' : 'issues.watch.start',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: t.ink.withValues(alpha: disabled ? 0.4 : 1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (disabled) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: row,
    );
  }
}

/// One person on the roster, aligned with the action above it (the avatar sits
/// in the same slot its glyph does).
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
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
      child: Row(
        children: [
          HiveAvatar(name: name ?? fallbackSeed, imageUrl: avatarUrl, size: 26),
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
                fontSize: 13.5,
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
