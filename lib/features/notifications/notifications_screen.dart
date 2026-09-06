import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/repositories/notification_repository.dart';
import '../../core/blocs/paged_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/content_models.dart';
import '../../core/notifications/notification_swipe.dart';
import '../../core/notifications/notification_visuals.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/soft_card.dart';
import '../../core/widgets/status_widgets.dart';
import '../../core/widgets/hive_widgets.dart' show forwardChevron;

/// Full notification centre: the paged feed grouped into time buckets
/// (today / yesterday / this week / …), rendered as iOS-style inset grouped
/// cards with per-type icon chips and unread accents.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final NotificationRepository _repo;
  late final PagedCubit<AppNotification> _cubit;
  final ScrollController _scroll = ScrollController();
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    _repo = context.read<NotificationRepository>();
    _cubit = PagedCubit<AppNotification>(
      (page, size) => _repo.notificationsPage(page: page, size: size),
      pageSize: 25,
      keyOf: (n) => n.id,
    )..load();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _cubit.close();
    super.dispose();
  }

  /// Infinite scroll: pull the next page as the user nears the bottom.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 480) {
      _cubit.loadMore();
    }
  }

  Future<void> _markAllRead(List<AppNotification> items) async {
    final hasUnread = items.any((n) => !n.read);
    if (!hasUnread || _markingAll) return;
    setState(() => _markingAll = true);
    try {
      await _repo.markAllNotificationsRead();
    } catch (_) {
      // Non-critical; the reload below reflects server truth.
    }
    await _cubit.load();
    if (mounted) setState(() => _markingAll = false);
  }

  Future<void> _delete(AppNotification notification) async {
    try {
      await _repo.deleteNotification(notification.id);
    } catch (_) {
      // Non-critical; the reload below reflects server truth.
    }
    await _cubit.load();
  }

  Future<void> _toggleRead(AppNotification notification) async {
    try {
      if (notification.read) {
        await _repo.markNotificationUnread(notification.id);
      } else {
        await _repo.markNotificationRead(notification.id);
      }
    } catch (_) {
      // Non-critical; the reload below reflects server truth.
    }
    await _cubit.load();
  }

  Future<void> _open(AppNotification notification) async {
    if (!notification.read) {
      try {
        await _repo.markNotificationRead(notification.id);
      } catch (_) {
        // Non-critical; the list refresh below reflects server truth.
      }
      _cubit.load();
    }
    // Every notification type carries a relative in-app route in `link`
    // (issues, teams, admin approvals, …) — the same field pushed via FCM and
    // rendered as the email CTA, so this is not limited to issue mentions.
    final link = notification.link;
    if (link != null && link.isNotEmpty && link.startsWith('/') && mounted) {
      context.go(link);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<
      PagedCubit<AppNotification>,
      PagedState<AppNotification>
    >(
      bloc: _cubit,
      builder: (context, state) {
        return RefreshIndicator(
          onRefresh: _cubit.load,
          child: AsyncView(
            isLoading: state.isLoading,
            hasData: state.hasData,
            errorKey: state.errorKey,
            onRetry: _cubit.load,
            builder: (context) {
              final notifications = state.items;
              final unreadCount = notifications.where((n) => !n.read).length;
              final groups = _groupByBucket(notifications);
              final showEmpty = notifications.isEmpty;
              final showLoader = state.isLoadingMore;
              // Lazy builder instead of a concrete children list: the feed paginates
              // (infinite scroll), so as pages accumulate only the on-screen group
              // cards should be built, not every past group up-front.
              final itemCount =
                  1 +
                  (showEmpty ? 1 : 0) +
                  groups.length +
                  (showLoader ? 1 : 0);
              return ListView.builder(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: context.pagePadding,
                itemCount: itemCount,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SectionHeader(
                          title: context.t('notifications.title'),
                          actionLabel: unreadCount > 0 && !_markingAll
                              ? context.t('notifications.markAllRead')
                              : null,
                          onAction: () => _markAllRead(notifications),
                        ),
                        if (unreadCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              context.t(
                                'notifications.unreadCount',
                                variables: {'count': '$unreadCount'},
                              ),
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.accentStrong,
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                      ],
                    );
                  }
                  var i = index - 1;
                  if (showEmpty) {
                    if (i == 0) {
                      return HiveEmptyState(
                        title: context.t('notifications.title'),
                        message: context.t('notifications.empty'),
                      );
                    }
                    i -= 1;
                  }
                  if (i < groups.length) {
                    final group = groups[i];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _GroupLabel(
                          label: context.t(
                            'notifications.group.${group.bucket.key}',
                          ),
                        ),
                        SoftCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              for (var j = 0; j < group.items.length; j++) ...[
                                if (j > 0)
                                  Divider(
                                    height: 1,
                                    indent: 62,
                                    color: AppColors.hairline2,
                                  ),
                                NotificationSwipe(
                                  notification: group.items[j],
                                  onDelete: _delete,
                                  onToggleRead: _toggleRead,
                                  child: _NotificationTile(
                                    notification: group.items[j],
                                    onTap: () => _open(group.items[j]),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                    );
                  }
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: HiveLoader(size: 30)),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

// ───────────────────────────── time bucketing ─────────────────────────────

enum _Bucket {
  today('today'),
  yesterday('yesterday'),
  thisWeek('thisWeek'),
  thisMonth('thisMonth'),
  earlier('earlier');

  const _Bucket(this.key);
  final String key;
}

_Bucket _bucketOf(DateTime? createdAt, DateTime now) {
  if (createdAt == null) return _Bucket.earlier;
  final local = createdAt.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  if (!day.isBefore(today)) return _Bucket.today;
  if (!day.isBefore(today.subtract(const Duration(days: 1)))) {
    return _Bucket.yesterday;
  }
  // Calendar week starting Monday, matching the local convention.
  final weekStart = today.subtract(Duration(days: today.weekday - 1));
  if (!day.isBefore(weekStart)) return _Bucket.thisWeek;
  if (day.year == today.year && day.month == today.month) {
    return _Bucket.thisMonth;
  }
  return _Bucket.earlier;
}

class _NotificationGroup {
  const _NotificationGroup(this.bucket, this.items);
  final _Bucket bucket;
  final List<AppNotification> items;
}

/// Splits the (already newest-first) feed into contiguous time buckets,
/// preserving order inside each group.
List<_NotificationGroup> _groupByBucket(List<AppNotification> items) {
  final now = DateTime.now();
  final groups = <_NotificationGroup>[];
  for (final n in items) {
    final bucket = _bucketOf(n.createdAt, now);
    if (groups.isNotEmpty && groups.last.bucket == bucket) {
      groups.last.items.add(n);
    } else {
      groups.add(_NotificationGroup(bucket, [n]));
    }
  }
  return groups;
}

// ─────────────────────────────── widgets ──────────────────────────────────

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppColors.inkSoft,
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = !notification.read;
    final (icon, tint) = notificationVisual(notification.type);
    final ago = notificationTimeAgo(notification.createdAt);
    return Material(
      color: unread ? AppColors.accentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppColors.surfaceMuted,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.soft(tint),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 17, color: tint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.35,
                              color: AppColors.ink,
                              fontWeight: unread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (ago != null) ...[
                          const SizedBox(width: 10),
                          Text(
                            ago,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.inkFaint,
                            ),
                          ),
                        ],
                        if (unread) ...[
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.accentStrong,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if ((notification.body ?? '').isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        notification.body!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Icon(
                  forwardChevron(context),
                  size: 15,
                  color: AppColors.inkFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
