part of 'user_management_screen.dart';

// ════════════════════════════════════════════════════════════════════════
//  Row / card / small controls
// ════════════════════════════════════════════════════════════════════════

class _UserTableRow extends StatelessWidget {
  const _UserTableRow({
    required this.user,
    required this.actions,
    required this.selected,
    required this.onToggle,
    required this.showOrigin,
    required this.isMe,
  });

  final AdminUser user;
  final UserActions actions;
  final bool selected;
  final VoidCallback onToggle;
  final bool showOrigin;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final u = user;
    final idle = isIdle(u.lastActive);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? AppColors.accentSoft.withValues(alpha: 0.4) : null,
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: [
          _Checkbox(checked: selected, mixed: false, onTap: onToggle),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: InkWell(
              onTap: () => actions.openDrawer(u),
              child: Row(
                children: [
                  UserAvatar(name: u.name, imageUrl: u.avatarUrl, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                u.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (normalizePronouns(u.pronouns) != null) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: PronounsLabel(
                                  pronouns: u.pronouns,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                            if (isMe) _YouChip(),
                          ],
                        ),
                        Text(
                          u.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: RoleBadge(u.role),
            ),
          ),
          if (showOrigin) Expanded(flex: 2, child: OriginTag(u.origin)),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusBadge(u),
                if (u.inviteExpired)
                  GestureDetector(
                    onTap: () => actions.openResend([u.id]),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            LucideIcons.send,
                            size: 11,
                            color: AppColors.accentStrong,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            context.t('admin.um.resendInvite'),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.accentStrong,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              umRelTime(context, u.lastActive),
              style: TextStyle(
                fontSize: 12.5,
                color: idle ? AppColors.inkFaint : AppColors.inkSoft,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: UserRowMenu(
              user: u,
              actions: actions,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  LucideIcons.ellipsisVertical,
                  size: 18,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.actions,
    required this.selected,
    required this.onToggle,
    required this.isMe,
  });

  final AdminUser user;
  final UserActions actions;
  final bool selected;
  final VoidCallback onToggle;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final u = user;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: selected ? AppColors.accentLine : AppColors.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Checkbox(checked: selected, mixed: false, onTap: onToggle),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => actions.openDrawer(u),
                  child: Row(
                    children: [
                      UserAvatar(name: u.name, imageUrl: u.avatarUrl, size: 40),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    u.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (normalizePronouns(u.pronouns) != null) ...[
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: PronounsLabel(
                                      pronouns: u.pronouns,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                                if (isMe) _YouChip(),
                              ],
                            ),
                            Text(
                              u.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              UserRowMenu(
                user: u,
                actions: actions,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    LucideIcons.ellipsisVertical,
                    size: 18,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [RoleBadge(u.role), StatusBadge(u), OriginTag(u.origin)],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(LucideIcons.activity, size: 13, color: AppColors.inkFaint),
              const SizedBox(width: 5),
              Text(
                umRelTime(context, u.lastActive),
                style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
              ),
              if (u.inviteExpired) ...[
                const Spacer(),
                GestureDetector(
                  onTap: () => actions.openResend([u.id]),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.send,
                        size: 12,
                        color: AppColors.accentStrong,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        context.t('admin.um.resendInvite'),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accentStrong,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _YouChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        context.t('admin.um.you'),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.accentStrong,
        ),
      ),
    ),
  );
}

class _Checkbox extends StatelessWidget {
  const _Checkbox({
    required this.checked,
    required this.mixed,
    required this.onTap,
  });
  final bool checked;
  final bool mixed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final on = checked || mixed;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppColors.navy : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: on ? AppColors.navy : AppColors.hairline,
            width: 1.5,
          ),
        ),
        child: checked
            ? const Icon(LucideIcons.check, size: 13, color: Colors.white)
            : (mixed
                  ? Container(width: 8, height: 2, color: Colors.white)
                  : null),
      ),
    );
  }
}

class _PagerButton extends StatelessWidget {
  const _PagerButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 16),
      color: AppColors.inkSoft,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _PageNumber extends StatelessWidget {
  const _PageNumber({
    required this.n,
    required this.active,
    required this.onTap,
  });
  final int n;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.navy : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: active ? null : Border.all(color: AppColors.hairline),
        ),
        child: Text(
          '$n',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : AppColors.inkSoft,
          ),
        ),
      ),
    );
  }
}
