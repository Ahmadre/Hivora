import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/work_models.dart';
import '../../../core/repositories/issue_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/hive_widgets.dart';
import '../../../core/widgets/soft_card.dart';
import '../../sprint/modals/glass_modal.dart'
    show
        kGlassPopoverBreakpoint,
        showGlassAnchoredPopover,
        showGlassBottomSheet,
        showGlassErrorToast;
import 'issue_watch_cubit.dart';

/// The "watch this issue" control in the issue detail's details column.
///
/// Three things in one card, because they only make sense together: the toggle
/// itself, the hint that says the toggle is *already* effectively on when you
/// are the assignee or the reporter (without it, an off switch on an issue you
/// do get mail about reads as a bug), and the watcher list — visible to every
/// project member, opened as a glass overlay rather than rendered inline.
class IssueWatchCard extends StatefulWidget {
  const IssueWatchCard({
    super.key,
    required this.issue,
    required this.currentUserId,
    this.names = const {},
    this.avatars = const {},
    this.onWatchersChanged,
  });

  final Issue issue;

  /// The signed-in user; null while the session is still resolving.
  final String? currentUserId;

  /// User id → display name / avatar URL, as the detail sheet already resolved
  /// them for assignees and comment authors.
  final Map<String, String> names;
  final Map<String, String> avatars;

  /// Fires with the committed watcher list so the host can keep its own [Issue]
  /// copy in sync (the toggle is the only thing that changes it here).
  final ValueChanged<List<String>>? onWatchersChanged;

  @override
  State<IssueWatchCard> createState() => _IssueWatchCardState();
}

class _IssueWatchCardState extends State<IssueWatchCard> {
  late final IssueRepository _repo;
  late IssueWatchCubit _cubit;

  @override
  void initState() {
    super.initState();
    // Safe in initState (no inherited-widget dependency is registered) and the
    // same way the other repository-backed screens reach theirs.
    _repo = context.read<IssueRepository>();
    _cubit = _create();
  }

  IssueWatchCubit _create() => IssueWatchCubit(
    repository: _repo,
    issueId: widget.issue.id,
    userId: widget.currentUserId,
    watcherIds: widget.issue.watcherIds,
  );

  @override
  void didUpdateWidget(covariant IssueWatchCard old) {
    super.didUpdateWidget(old);
    // A different issue (or a session that only just resolved) needs a fresh
    // cubit — which is also what clears the cubit's committed own-watch state,
    // so it can never leak onto another issue. The same issue reloaded only
    // needs its watcher list adopted.
    if (old.issue.id != widget.issue.id ||
        old.currentUserId != widget.currentUserId) {
      _cubit.close();
      _cubit = _create();
      return;
    }
    _cubit.sync(widget.issue.watcherIds);
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  /// Why the toggle may sit "off" while notifications still arrive: assignees
  /// and the reporter are notified implicitly, without ever subscribing.
  String? get _implicitHintKey {
    final me = widget.currentUserId;
    if (me == null) return null;
    if (widget.issue.assigneeIds.contains(me) ||
        widget.issue.assigneeId == me) {
      return 'issues.watch.implicitAssignee';
    }
    if (widget.issue.reporterId == me) return 'issues.watch.implicitReporter';
    return null;
  }

  void _openWatchers(Rect anchor, List<String> watcherIds) {
    if (watcherIds.isEmpty) return;
    Widget builder(BuildContext _) => _WatcherList(
      watcherIds: watcherIds,
      names: widget.names,
      avatars: widget.avatars,
      meId: widget.currentUserId,
    );
    if (MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint) {
      showGlassAnchoredPopover<void>(
        context,
        anchorRect: anchor,
        width: 320,
        maxHeight: 420,
        builder: builder,
      );
      return;
    }
    showGlassBottomSheet<void>(context, builder: builder);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<IssueWatchCubit, IssueWatchState>(
      bloc: _cubit,
      listener: (context, state) {
        final error = state.errorKey;
        if (error != null) {
          // `t` is idempotent: an already-localized backend message passes
          // through, a fallback key gets translated instead of leaking.
          showGlassErrorToast(context, context.t(error));
          return;
        }
        if (!state.busy) widget.onWatchersChanged?.call(state.watcherIds);
      },
      builder: (context, state) {
        final watching = state.isWatchedBy(widget.currentUserId);
        final hintKey = _implicitHintKey;
        return SoftCard(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    watching ? LucideIcons.eye : LucideIcons.eyeOff,
                    size: 17,
                    color: watching
                        ? AppColors.accentStrong
                        : AppColors.inkFaint,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.t('issues.watch.title'),
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.t(
                            watching
                                ? 'issues.watch.subtitleOn'
                                : 'issues.watch.subtitleOff',
                          ),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  HiveSwitch(
                    value: watching,
                    // Nobody to subscribe before the session resolves. Not
                    // disabled while a call is out: CupertinoSwitch dims itself
                    // for a null handler, which is exactly the broken-control
                    // look the optimistic flip exists to avoid — the cubit
                    // already drops a second tap mid-flight.
                    onChanged: widget.currentUserId == null
                        ? null
                        : (_) => _cubit.toggle(),
                  ),
                ],
              ),
              if (hintKey != null) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(LucideIcons.info, size: 13, color: AppColors.inkFaint),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        context.t(hintKey),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: AppColors.inkFaint,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              _WatcherSummary(
                watcherIds: state.watcherIds,
                names: widget.names,
                avatars: widget.avatars,
                onTap: _openWatchers,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The tappable one-liner under the toggle: stacked avatars plus the count,
/// opening the full list in a glass overlay. No inline list — the roster can be
/// as long as the project has members.
class _WatcherSummary extends StatelessWidget {
  const _WatcherSummary({
    required this.watcherIds,
    required this.names,
    required this.avatars,
    required this.onTap,
  });

  final List<String> watcherIds;
  final Map<String, String> names;
  final Map<String, String> avatars;
  final void Function(Rect anchorRect, List<String> watcherIds) onTap;

  @override
  Widget build(BuildContext context) {
    final empty = watcherIds.isEmpty;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: empty
          ? null
          : () {
              final box = context.findRenderObject() as RenderBox?;
              final rect = (box != null && box.hasSize)
                  ? box.localToGlobal(Offset.zero) & box.size
                  : Rect.zero;
              onTap(rect, watcherIds);
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            if (!empty) ...[
              HiveAvatarStack(
                names: [for (final id in watcherIds) names[id] ?? id],
                imageUrls: [for (final id in watcherIds) avatars[id]],
                size: 22,
                max: 4,
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                empty
                    ? context.t('issues.watch.noWatchers')
                    : context.t(
                        'issues.watch.watcherCount',
                        count: watcherIds.length,
                        variables: {'count': watcherIds.length},
                      ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: empty ? AppColors.inkFaint : AppColors.inkSoft,
                ),
              ),
            ),
            if (!empty)
              Icon(
                LucideIcons.chevronRight,
                size: 15,
                color: AppColors.inkFaint,
              ),
          ],
        ),
      ),
    );
  }
}

/// Body of the watcher glass popover / sheet: who is subscribed, "you" first.
class _WatcherList extends StatelessWidget {
  const _WatcherList({
    required this.watcherIds,
    required this.names,
    required this.avatars,
    required this.meId,
  });

  final List<String> watcherIds;
  final Map<String, String> names;
  final Map<String, String> avatars;
  final String? meId;

  @override
  Widget build(BuildContext context) {
    final ordered = [
      if (meId != null && watcherIds.contains(meId)) meId!,
      for (final id in watcherIds)
        if (id != meId) id,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
          child: Text(
            context.t('issues.watch.watchersTitle'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: ordered.length,
            itemBuilder: (context, i) {
              final id = ordered[i];
              // Watchers are the one group the detail aggregate does not ship
              // users for, so the directory may not have resolved them (yet, or
              // ever, for a deactivated account). An id is not a name — the
              // avatar still takes it, where it renders as a neutral glyph.
              final name = names[id];
              return ListTile(
                dense: true,
                leading: HiveAvatar(
                  name: name ?? id,
                  imageUrl: avatars[id],
                  size: 30,
                ),
                title: Text(
                  name ?? context.t('issues.watch.unknownWatcher'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: id == meId
                    ? Text(
                        context.t('issues.watch.you'),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.inkFaint,
                        ),
                      )
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }
}
