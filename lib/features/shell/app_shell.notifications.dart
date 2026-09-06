part of 'app_shell.dart';

// ─────────────────────────── Notification bell + popover ──────────────────

/// Bell action with an unread dot and an anchored popover listing the 10 most
/// recent notifications. The popover footer links to the full list.
class _NotificationBell extends StatefulWidget {
  const _NotificationBell({
    required this.active,
    this.dark = false,
    this.frosted = false,
  });

  final bool frosted;
  final bool active;

  /// When true the trigger is a standalone iOS-26 [_FrostedCircleButton]
  /// (mobile top bar); otherwise the desktop ghost [_TopIconButton].
  final bool dark;

  @override
  State<_NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<_NotificationBell> {
  /// The bell preview is capped at 5 entries — full history lives on the
  /// notifications page, and a smaller page keeps the popover build cheap.
  static const _previewCount = 5;

  late final FetchCubit<List<AppNotification>> _cubit;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _cubit = FetchCubit(
      () async =>
          (await context.read<NotificationRepository>().notificationsPage(
            size: _previewCount,
          )).items,
    )..load();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  Future<void> _markAllRead(List<AppNotification> items) async {
    if (!items.any((n) => !n.read)) return;
    try {
      await context.read<NotificationRepository>().markAllNotificationsRead();
    } catch (_) {
      // Non-critical; the reload below reflects server truth.
    }
    await _cubit.load();
  }

  Future<void> _deleteNotification(AppNotification notification) async {
    try {
      await context.read<NotificationRepository>().deleteNotification(
        notification.id,
      );
    } catch (_) {
      // Non-critical; the reload below reflects server truth.
    }
    await _cubit.load();
  }

  Future<void> _toggleNotificationRead(AppNotification notification) async {
    final repository = context.read<NotificationRepository>();
    try {
      if (notification.read) {
        await repository.markNotificationUnread(notification.id);
      } else {
        await repository.markNotificationRead(notification.id);
      }
    } catch (_) {
      // Non-critical; the reload below reflects server truth.
    }
    await _cubit.load();
  }

  Future<void> _openNotification(AppNotification notification) async {
    final repository = context.read<NotificationRepository>();
    if (!notification.read) {
      try {
        await repository.markNotificationRead(notification.id);
      } catch (_) {}
      _cubit.load();
    }
    final link = notification.link;
    // Any in-app route (issues, projects, teams, admin …), not just issues, so
    // every notification type is tappable from the bell like it is in the feed.
    if (link != null && link.startsWith('/') && mounted) {
      context.go(link);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child:
          BlocBuilder<
            FetchCubit<List<AppNotification>>,
            FetchState<List<AppNotification>>
          >(
            builder: (context, state) {
              final items = state.data ?? const <AppNotification>[];
              final hasUnread = items.any((n) => !n.read);
              final showDot = hasUnread && !_open;
              final media = MediaQuery.of(context);
              final tokens = SearchTokens.of(Theme.of(context).brightness);
              final dark = Theme.of(context).brightness == Brightness.dark;
              // A touch more opaque than the shared search glass so
              // notification text reads clearly over busy backgrounds.
              final glassFill = tokens.glassFill.withValues(
                alpha: (tokens.glassFill.a + 0.22).clamp(0.0, 0.92),
              );
              Widget buildTrigger(VoidCallback toggle) => widget.frosted
                  ? _FrostedCircleButton(
                      icon: LucideIcons.bell,
                      tooltip: context.t('nav.notifications'),
                      active: widget.active || _open,
                      onTap: toggle,
                      overlay: showDot
                          ? const Positioned(
                              top: 8,
                              right: 9,
                              child: _UnreadDot(),
                            )
                          : null,
                    )
                  : _TopIconButton(
                      icon: LucideIcons.bell,
                      tooltip: context.t('nav.notifications'),
                      active: widget.active || _open,
                      onTap: toggle,
                      child: showDot
                          ? const Positioned(
                              top: 7,
                              right: 8,
                              child: _UnreadDot(),
                            )
                          : null,
                    );
              Widget buildNativeButton(VoidCallback toggle) => GlassButton(
                icon: const Icon(LucideIcons.bell),
                onTap: toggle,
                width: 42,
                height: 42,
                iconSize: 18,
                useOwnLayer: true,
                settings: widget.dark ? kNavGlassDark : kNavGlassLight,
                iconColor: widget.dark ? AppColors.inkDark : AppColors.ink,
                glowColor: AppColors.accent,

                // Keep the tactile press-scale but damp the liquid drag-follow so the
                // isolated button doesn't over-stretch on tap.
                stretch: 0.15,
              );
              Widget buildMobileTrigger(VoidCallback toggle) => Tooltip(
                message: context.t('nav.notifications'),
                child: Badge(
                  backgroundColor: AppColors.accent,
                  smallSize: 10.5,
                  isLabelVisible: showDot,
                  child: buildNativeButton(toggle),
                ),
              );
              // iOS-26 liquid morph: the popover grows out of the bell trigger
              // (same dual-blob metaball pattern as the comment sort button).
              // GlassPopover ramps the backdrop blur in over the morph
              // (blurRampDuration) instead of paying its full raster cost from
              // frame one — the perf fix that used to live in MorphBlurPopover.
              return GlassPopover(
                popoverWidth: (media.size.width - 24).clamp(0.0, 340.0),
                popoverBorderRadius: AppTheme.radiusCard,
                settings: liquidGlassPanelSettings(
                  glassFill: glassFill,
                  dark: dark,
                ),
                quality: GlassQuality.standard,
                onOpen: () {
                  _cubit.load(); // refresh contents whenever it opens
                  setState(() => _open = true);
                },
                onClose: () => setState(() => _open = false),
                // The glass pill is the phone's chrome, where the bell sits on
                // a translucent bar and needs its own ground to be legible. On a
                // desktop window the header is opaque already, so the same pill
                // reads as a milky disc around an icon that needs no disc — the
                // wide shell's plain icon button is what belongs there.
                triggerBuilder: (context, toggle) =>
                    isNativeApp && context.isCompact
                    ? buildMobileTrigger(toggle)
                    : buildTrigger(toggle),
                contentBuilder: (context, close) => _NotifPopoverCard(
                  items: items,
                  onMarkAllRead: () => _markAllRead(items),
                  onDelete: _deleteNotification,
                  onToggleRead: _toggleNotificationRead,
                  onTapNotification: (n) {
                    close();
                    _openNotification(n);
                  },
                  onViewAll: () {
                    close();
                    context.go('/notifications');
                  },
                ),
              );
            },
          ),
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: AppColors.accentStrong,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.canvas, width: 2),
      ),
    );
  }
}

class _NotifPopoverCard extends StatelessWidget {
  const _NotifPopoverCard({
    required this.items,
    required this.onMarkAllRead,
    required this.onDelete,
    required this.onToggleRead,
    required this.onTapNotification,
    required this.onViewAll,
  });

  final List<AppNotification> items;
  final VoidCallback onMarkAllRead;
  final Future<void> Function(AppNotification) onDelete;
  final Future<void> Function(AppNotification) onToggleRead;
  final void Function(AppNotification) onTapNotification;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxListHeight = media.size.height * 0.5;
    final latest = items;
    final hasUnread = items.any((n) => !n.read);

    // The surrounding GlassPopover provides the glass panel (shape, fill,
    // shadow) and the liquid morph from the bell — this is content only.
    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
            child: Row(
              children: [
                Text(
                  context.t('notifications.title'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: AppColors.ink,
                  ),
                ),
                const Spacer(),
                if (hasUnread)
                  InkWell(
                    onTap: onMarkAllRead,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        context.t('notifications.markAllRead'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accentStrong,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.hairline2),
          // List (max 10 latest)
          if (latest.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
              child: Text(
                context.t('notifications.empty'),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
              ),
            )
          else
            // Plain ConstrainedBox (no Flexible): the popover measures
            // its content with unbounded height during the morph, and
            // flex children are illegal in an unbounded column.
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxListHeight),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: latest.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: AppColors.hairline2),
                itemBuilder: (_, i) => NotificationSwipe(
                  notification: latest[i],
                  onDelete: onDelete,
                  onToggleRead: onToggleRead,
                  child: _NotifRow(
                    notification: latest[i],
                    onTap: () => onTapNotification(latest[i]),
                  ),
                ),
              ),
            ),
          Divider(height: 1, color: AppColors.hairline2),
          // Fixed footer → full notifications page
          InkWell(
            onTap: onViewAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    context.t('notifications.viewAll'),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    forwardArrow(context),
                    size: 15,
                    color: AppColors.inkSoft,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotifRow extends StatelessWidget {
  const _NotifRow({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = !notification.read;
    final (icon, tint) = notificationVisual(notification.type);
    final ago = notificationTimeAgo(notification.createdAt);
    return Material(
      // Transparent read rows let the glass panel show through; unread keep a
      // soft accent wash.
      color: unread ? AppColors.accentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppColors.surfaceMuted,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.soft(tint),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 16, color: tint),
              ),
              const SizedBox(width: 11),
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
                              fontSize: 12.5,
                              height: 1.4,
                              color: AppColors.ink,
                              fontWeight: unread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (ago != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            ago,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.inkFaint,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if ((notification.body ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        notification.body!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.inkSoft,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Icon/tint mapping and relative time live in
// core/notifications/notification_visuals.dart, shared with the full
// notifications page.
