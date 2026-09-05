part of 'issue_detail_sheet.dart';

// ─────────────────────────── Top bar ───────────────────────────────────────

/// Actions collapsed into the "…" overflow menu of the issue top bars.
enum _IssueMenuAction { watch, reply, export, clone, move, delete }

/// The delete/archive/restore affordance shared by both top bars: label,
/// icon and tint depend on the archived state and the delete permission.
({String labelKey, IconData icon, Color color}) _removalLook({
  required bool archived,
  required bool canDelete,
}) => (
  labelKey: archived
      ? 'issues.unarchive'
      : (canDelete ? 'common.delete' : 'issues.archive'),
  icon: archived
      ? LucideIcons.archiveRestore
      : (canDelete ? LucideIcons.trash2 : LucideIcons.archive),
  color: canDelete && !archived ? AppColors.danger : AppColors.accentStrong,
);

/// "…" overflow button for the issue top bars, bundling watch · reply · clone ·
/// move · delete/archive into one liquid-glass popover so the bar stays tidy.
///
/// Watching is a menu entry rather than a button of its own (or a card in the
/// details column, where it used to sit and cost the narrow right column a
/// whole block): it is a one-tap subscription, not a field of the issue. Its
/// row opens a second glass popover — the subscription, why you may already be
/// notified, and the roster are a section of their own, not three more rows in
/// a list of actions.
class _IssueActionsMenu extends StatelessWidget {
  const _IssueActionsMenu({
    required this.onExport,
    required this.onClone,
    required this.onMove,
    required this.onDelete,
    required this.canDelete,
    required this.archived,
    this.onReply,
    this.watch,
  });

  /// Opens the export submenu, which needs the anchor this menu stood at so it
  /// can appear in the same place.
  final void Function(Rect anchorRect) onExport;

  /// Opens the clone dialog. Available on archived issues too: the copy is a
  /// live issue whatever the original's state, and cloning is how a shelved
  /// ticket gets picked back up.
  final VoidCallback onClone;

  /// Opens the move-to-another-project wizard. Always available: moving is a
  /// normal member action, gated per project by the server.
  final VoidCallback onMove;
  final VoidCallback onDelete;
  final bool canDelete;
  final bool archived;

  /// Non-null only for email-sourced issues with the `emailReply` flag on.
  final VoidCallback? onReply;

  /// The watch section (toggle row + roster), or null before the body has
  /// loaded the issue — the menu's other actions are still available then.
  final IssueWatchMenuData? watch;

  @override
  Widget build(BuildContext context) {
    final watch = this.watch;
    if (watch == null) return _menu(context, watching: false);
    // Rebuilds this anchor whenever the roster changes, so the row's verb and
    // the list under it are right the next time the menu opens — including
    // after a toggle made from the *other* top bar (sheet and route share one
    // cubit, and the sheet's bar is a subtree of its own).
    return BlocBuilder<IssueWatchCubit, IssueWatchState>(
      bloc: watch.cubit,
      builder: (context, state) =>
          _menu(context, watching: state.isWatchedBy(watch.meId)),
    );
  }

  Widget _menu(BuildContext context, {required bool watching}) {
    final watch = this.watch;
    final removal = _removalLook(archived: archived, canDelete: canDelete);
    // The watch row is a group of its own at the top, so whichever action
    // comes after it opens the next group.
    final afterWatch = watch != null;

    return GlassPopupMenu<_IssueMenuAction?>(
      value: null,
      width: 260,
      items: [
        if (watch != null)
          issueWatchMenuItem(
            context,
            value: _IssueMenuAction.watch,
            watching: watching,
            enabled: watch.meId != null,
          ),
        if (onReply != null)
          GlassMenuItem(
            value: _IssueMenuAction.reply,
            label: context.t('issues.replyEmail.action'),
            leading: const Icon(
              LucideIcons.mail,
              size: 16,
              color: AppColors.accentStrong,
            ),
            dividerAbove: afterWatch,
          ),
        GlassMenuItem(
          value: _IssueMenuAction.export,
          label: context.t('issues.export.action'),
          leading: Icon(
            LucideIcons.download,
            size: 16,
            color: AppColors.inkSoft,
          ),
          trailing: Icon(
            LucideIcons.chevronRight,
            size: 15,
            color: AppColors.inkFaint,
          ),
          dividerAbove: afterWatch && onReply == null,
        ),
        GlassMenuItem(
          value: _IssueMenuAction.clone,
          label: context.t('issues.clone.action'),
          leading: Icon(LucideIcons.copy, size: 16, color: AppColors.inkSoft),
        ),
        GlassMenuItem(
          value: _IssueMenuAction.move,
          label: context.t('issues.move.action'),
          leading: Icon(
            LucideIcons.folderInput,
            size: 16,
            color: AppColors.inkSoft,
          ),
          // An archived issue is soft-deleted; restore it before relocating it.
          enabled: !archived,
          disabledReason: archived
              ? context.t('issues.move.archivedHint')
              : null,
        ),
        GlassMenuItem(
          value: _IssueMenuAction.delete,
          label: context.t(removal.labelKey),
          leading: Icon(removal.icon, size: 16, color: removal.color),
          color: canDelete && !archived ? AppColors.danger : null,
          dividerAbove: true,
        ),
      ],
      onSelected: (action) {
        switch (action) {
          case _IssueMenuAction.watch:
            if (watch != null) _openWatchPopover(context, watch);
          case _IssueMenuAction.reply:
            onReply?.call();
          case _IssueMenuAction.export:
            _openFromMenuAnchor(context, onExport);
          case _IssueMenuAction.clone:
            onClone();
          case _IssueMenuAction.move:
            onMove();
          case _IssueMenuAction.delete:
            onDelete();
          case null:
            break;
        }
      },
      child: Tooltip(
        message: context.t('issues.moreActions'),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          // Sized to sit flush with the sibling IconButtons (48dp tap target).
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: Icon(
                LucideIcons.ellipsis,
                size: 20,
                color: AppColors.inkSoft,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Runs [open] with the rect the "…" menu just stood at.
///
/// [context] is the menu button's own element, still mounted: the menu closes
/// before reporting a selection, but the top bar holding the anchor does not go
/// anywhere. A Rect.zero fallback is harmless — the panel clamps itself
/// on-screen — while a torn-down context is not, so that case bails out.
void _openFromMenuAnchor(BuildContext context, void Function(Rect) open) {
  if (!context.mounted) return;
  final box = context.findRenderObject() as RenderBox?;
  open(
    (box != null && box.hasSize)
        ? box.localToGlobal(Offset.zero) & box.size
        : Rect.zero,
  );
}

/// Opens the watch popover where the "…" menu just stood.
///
/// [context] is this button's own element, still mounted: the menu closes
/// before reporting a selection, but the top bar holding the anchor does not go
/// anywhere. A Rect.zero fallback is harmless — the panel clamps itself
/// on-screen — while a torn-down context is not, so that case bails out.
void _openWatchPopover(BuildContext context, IssueWatchMenuData watch) {
  if (!context.mounted) return;
  final box = context.findRenderObject() as RenderBox?;
  final anchor = (box != null && box.hasSize)
      ? box.localToGlobal(Offset.zero) & box.size
      : Rect.zero;
  showIssueWatchPopover(context, anchorRect: anchor, data: watch);
}

class _RouteTopBar extends StatelessWidget {
  const _RouteTopBar({
    required this.issue,
    required this.busy,
    this.stateColor,
    required this.link,
    this.onMinimize,
    required this.onDelete,
    required this.onExport,
    required this.onClone,
    required this.onMove,
    required this.onClose,
    this.onReply,
    this.watch,
    this.canDelete = false,
  });

  final Issue issue;
  final bool busy;
  final Color? stateColor;
  final String link;

  /// Shrink back to the modal sheet — only when this page was promoted from it
  /// (null for direct deep-links, which have no modal to return to).
  final VoidCallback? onMinimize;
  final VoidCallback onDelete;

  /// Opens the export submenu, anchored where the "…" menu stood.
  final void Function(Rect anchorRect) onExport;

  /// Opens the clone dialog.
  final VoidCallback onClone;

  /// Opens the move-to-another-project wizard.
  final VoidCallback onMove;
  final VoidCallback onClose;

  /// Non-null only for email-sourced issues with the `emailReply` flag enabled;
  /// opens the reply-by-email composer.
  final VoidCallback? onReply;

  /// The watch section of the "…" menu; null until the issue is loaded.
  final IssueWatchMenuData? watch;

  /// Whether the current user may hard-delete: picks the trash icon over the
  /// archive icon (regular members only archive; archived issues restore).
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kRouteTopBarHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
        child: Row(
          children: [
            IconButton(
              onPressed: onClose,
              icon: Icon(
                LucideIcons.arrowLeft,
                size: 20,
                color: AppColors.inkSoft,
              ),
            ),
            // The leading cluster consumes the free space (so the action buttons
            // stay hard-right); the state badge ellipsises inside it if tight.
            Expanded(
              child: Row(
                children: [
                  CopyLinkId(
                    type: issue.type,
                    readableId: issue.readableId,
                    link: link,
                    showGlyph: false,
                    color: AppColors.inkSoft,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: StateDotBadge(state: issue.state, color: stateColor),
                  ),
                  if (busy) ...[
                    const SizedBox(width: 10),
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: HiveLoader(
                        strokeWidth: 2,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onMinimize != null)
              IconButton(
                tooltip: context.t('issues.minimize'),
                onPressed: onMinimize,
                icon: Icon(
                  LucideIcons.minimize2,
                  size: 19,
                  color: AppColors.inkSoft,
                ),
              ),
            // Secondary actions (watch · clone · move · reply · remove) live in
            // one "…" popover so the bar keeps a fixed shape regardless of
            // which are available.
            _IssueActionsMenu(
              onReply: onReply,
              onExport: onExport,
              onClone: onClone,
              onMove: onMove,
              onDelete: onDelete,
              canDelete: canDelete,
              archived: issue.archived,
              watch: watch,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Inline title editor ───────────────────────────

/// Inline title field with a green-check (save) / red-cross (cancel) row.
class _InlineTitleEditor extends StatelessWidget {
  const _InlineTitleEditor({
    required this.controller,
    required this.onSave,
    required this.onCancel,
  });

  final TextEditingController controller;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(
            fontFamily: AppTheme.fontBrand,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
          decoration: const InputDecoration(isDense: true),
          onSubmitted: (_) => onSave(),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SquareButton(
              icon: LucideIcons.check,
              color: AppColors.success,
              onTap: onSave,
            ),
            const SizedBox(width: 8),
            _SquareButton(
              icon: LucideIcons.x,
              color: AppColors.danger,
              onTap: onCancel,
            ),
          ],
        ),
      ],
    );
  }
}

/// Small bordered square action button (✓ / ✕).
class _SquareButton extends StatelessWidget {
  const _SquareButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

// ─────────────────────────── Activity tabs + comment tile ──────────────────

/// A centered "Load earlier / Load more" control for the paginated comment and
/// activity streams; shows the standard [HiveLoader] while a page is fetching.
class _LoadMoreTile extends StatelessWidget {
  const _LoadMoreTile({
    required this.label,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: TextButton.icon(
          onPressed: loading ? null : onTap,
          icon: loading
              ? const HiveLoader(size: 14, strokeWidth: 2)
              : Icon(
                  LucideIcons.chevronDown,
                  size: 15,
                  color: AppColors.inkSoft,
                ),
          label: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.inkSoft,
            ),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }
}

enum _ActivityFilter { all, comments, history }

class _ActivityTabs extends StatelessWidget {
  const _ActivityTabs({required this.value, required this.onChanged});

  final _ActivityFilter value;
  final ValueChanged<_ActivityFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.canvas2,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg(context, _ActivityFilter.all, context.t('issues.filterAll')),
          _seg(
            context,
            _ActivityFilter.comments,
            context.t('issues.filterComments'),
          ),
          _seg(
            context,
            _ActivityFilter.history,
            context.t('issues.filterHistory'),
          ),
        ],
      ),
    );
  }

  Widget _seg(BuildContext context, _ActivityFilter filter, String label) {
    final active = value == filter;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: active ? AppColors.hairline : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? AppColors.ink : AppColors.inkSoft,
          ),
        ),
      ),
    );
  }
}

/// History row: actor avatar + "[name] changed [field]" + optional from→to.
class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.activity,
    required this.actorName,
    required this.names,
    required this.sprintNames,
    this.issueIds = const {},
  });

  final IssueActivity activity;
  final String actorName;
  final Map<String, String> names;
  final Map<String, String> sprintNames;

  /// Issue id → readable id, so a PARENT change reads as `HIV-12`, not a raw id.
  final Map<String, String> issueIds;

  // Fields where a before→after value pair is worth showing as chips.
  static const _chipFields = {
    'STATE',
    'ASSIGNEE',
    'PRIORITY',
    'TYPE',
    'SPRINT',
    'PARENT',
    'START_DATE',
    'DUE_DATE',
    'ESTIMATE',
    'TAGS',
  };

  @override
  Widget build(BuildContext context) {
    final action = activity.field == 'CREATED'
        ? context.t('issues.act.created')
        : context.t(
            'issues.act.changed',
            variables: {'field': _fieldLabel(context, activity.field)},
          );
    final showChips = _chipFields.contains(activity.field);

    final dark = AppColors.brightness == Brightness.dark;
    // System-note bubble: same rounded hairline shell as the "other" comment
    // bubble (so all three activity tabs read as one feed), just a flatter,
    // more muted fill to distinguish change events from real messages.
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.72,
      ),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1E1D29) : AppColors.surfaceMuted,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(5),
          bottomRight: Radius.circular(16),
        ),
        border: Border.all(color: AppColors.hairline),
      ),
      padding: const EdgeInsets.fromLTRB(13, 9, 13, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: actorName,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                TextSpan(text: ' $action'),
              ],
            ),
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.inkSoft,
            ),
          ),
          if (showChips) ...[const SizedBox(height: 7), _changeRow(context)],
          if (activity.createdAt != null) ...[
            const SizedBox(height: 3),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                MaterialLocalizations.of(
                  context,
                ).formatShortDate(activity.createdAt!.toLocal()),
                style: TextStyle(fontSize: 10.5, color: AppColors.inkFaint),
              ),
            ),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          HiveAvatar(
            name: actorName,
            size: 30,
            glyph: activity.actorId == null ? const HexMark(size: 18) : null,
            background: activity.actorId == null ? AppColors.accentSoft : null,
          ),
          const SizedBox(width: 9),
          Flexible(child: bubble),
        ],
      ),
    );
  }

  Widget _changeRow(BuildContext context) {
    final from = _displayValue(context, activity.fromValue);
    final to = _displayValue(context, activity.toValue);
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (from != null) _ChangeChip(from),
        if (from != null)
          Icon(LucideIcons.arrowRight, size: 14, color: AppColors.inkFaint),
        if (to != null) _ChangeChip(to),
      ],
    );
  }

  /// Humanises a raw stored value for the activity's field.
  String? _displayValue(BuildContext context, String? raw) {
    final field = activity.field;
    if (raw == null || raw.isEmpty) {
      // Assignee / sprint cleared → show an explicit "none" chip.
      return switch (field) {
        'ASSIGNEE' => context.t('issues.unassigned'),
        'SPRINT' => context.t('issues.noSprint'),
        'PARENT' => context.t('issues.noEpic'),
        _ => null,
      };
    }
    return switch (field) {
      'ASSIGNEE' => names[raw] ?? raw,
      'SPRINT' => sprintNames[raw] ?? raw,
      'PARENT' => issueIds[raw] ?? raw,
      'STATE' => stateLabel(raw),
      'PRIORITY' => context.t('priority.${raw.toLowerCase()}'),
      'TYPE' => context.t('type.${raw.toLowerCase()}'),
      'ESTIMATE' => fmtDuration(int.tryParse(raw)),
      'START_DATE' || 'DUE_DATE' => _fmtDate(context, raw),
      _ => raw,
    };
  }

  String _fmtDate(BuildContext context, String raw) {
    final parsed = DateTime.tryParse(raw);
    return parsed != null
        ? MaterialLocalizations.of(context).formatMediumDate(parsed)
        : raw;
  }

  String _fieldLabel(BuildContext context, String field) => switch (field) {
    'TITLE' => context.t('issues.field.title'),
    'DESCRIPTION' => context.t('issues.field.description'),
    'STATE' => context.t('issues.field.state'),
    'ASSIGNEE' => context.t('issues.field.assignee'),
    'PRIORITY' => context.t('issues.field.priority'),
    'TYPE' => context.t('issues.field.type'),
    'SPRINT' => context.t('issues.field.sprint'),
    'PARENT' => context.t('issues.field.parent'),
    'START_DATE' => context.t('issues.field.startDate'),
    'DUE_DATE' => context.t('issues.field.dueDate'),
    'ESTIMATE' => context.t('issues.field.estimate'),
    'TAGS' => context.t('issues.field.tags'),
    _ => field.toLowerCase(),
  };
}

/// Small bordered pill used for before/after values in the history.
class _ChangeChip extends StatelessWidget {
  const _ChangeChip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
    );
  }
}

// ─────────────────── "Documented in" cross-reference ───────────────────────

/// Knowledge-base backlinks: the KB articles whose body references this issue
/// (`{{issue:<readableId>}}`). Each row opens the article.
class _DocumentedIn extends StatelessWidget {
  const _DocumentedIn({
    required this.articles,
    required this.knowledge,
    required this.onOpen,
  });

  final List<KbArticle> articles;
  final KnowledgeRepository knowledge;
  final void Function(String articleId) onOpen;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(lucideIcon('link-2'), size: 16, color: KbTokens.accent),
              const SizedBox(width: 8),
              Text(
                context.t('knowledge.documentedIn'),
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Text(
                  '${articles.length}',
                  style: TextStyle(
                    fontFamily: AppTheme.fontMono,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkFaint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final a in articles) _row(a),
        ],
      ),
    );
  }

  Widget _row(KbArticle a) {
    final sp = knowledge.spaceById(a.spaceId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(KbTokens.radiusControl),
        child: InkWell(
          onTap: () => onOpen(a.id),
          borderRadius: BorderRadius.circular(KbTokens.radiusControl),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(KbTokens.radiusControl),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              children: [
                Icon(lucideIcon(a.icon), size: 17, color: KbTokens.accent),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (sp != null)
                        Text(
                          sp.name,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.inkSoft,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  lucideIcon('chevron-right'),
                  size: 16,
                  color: AppColors.inkFaint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── People picker ─────────────────────────────────

/// One person as a value: avatar + name, or [fallback] when there is nobody.
///
/// Lives here rather than on one screen because the detail view, the create
/// form and the clone dialog all render an assignee — three copies of what a
/// person looks like in a field is how they drift apart.
Widget _person(
  String? name, {
  required String fallback,
  String? imageUrl,
  String? pronouns,
}) {
  if (name == null || name.isEmpty) {
    return Text(
      fallback,
      style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
    );
  }
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      HiveAvatar(name: name, imageUrl: imageUrl, size: 22, pronouns: pronouns),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}

class _PeoplePicker extends StatefulWidget {
  const _PeoplePicker({
    required this.users,
    required this.meId,
    required this.onSelect,
    required this.onUnassign,
    required this.onAssignMe,
    this.anchored = false,
    this.multiSelect = false,
    this.initialSelected = const {},
    this.onSelectionChanged,
  });

  final List<DirectoryUser> users;
  final String? meId;
  final ValueChanged<String> onSelect;
  final VoidCallback onUnassign;
  final VoidCallback? onAssignMe;

  /// When `true`, the picker stays open and toggles a set of people (checkmarks)
  /// instead of selecting one and closing. [onSelectionChanged] fires with the
  /// full updated set after every toggle / clear / assign-me.
  final bool multiSelect;
  final Set<String> initialSelected;
  final ValueChanged<Set<String>>? onSelectionChanged;

  /// When `true`, the picker renders for a wide-screen anchored popover: no grab
  /// handle and a height that flexes to its host's constraints instead of the
  /// fixed tall sheet used on phones.
  final bool anchored;

  @override
  State<_PeoplePicker> createState() => _PeoplePickerState();
}

class _PeoplePickerState extends State<_PeoplePicker> {
  String _query = '';
  late final Set<String> _selected = {...widget.initialSelected};

  void _toggle(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
    widget.onSelectionChanged?.call(_selected);
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.users
        : widget.users
              .where(
                (u) =>
                    u.displayName.toLowerCase().contains(q) ||
                    u.username.toLowerCase().contains(q),
              )
              .toList();
    final searchField = Padding(
      padding: widget.anchored
          ? const EdgeInsets.fromLTRB(12, 12, 12, 8)
          : const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: TextField(
        autofocus: true,
        onChanged: (v) => setState(() => _query = v),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(LucideIcons.search, size: 18),
          hintText: context.t('issues.searchPeople'),
          filled: true,
          fillColor: AppColors.surfaceMuted,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            borderSide: BorderSide(color: AppColors.hairline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            borderSide: BorderSide(color: AppColors.hairline),
          ),
        ),
      ),
    );

    // Header rows (assign-to-me / unassign / divider) only show when not
    // searching; they're few and fixed, so they lead a lazily-built list of the
    // (potentially hundreds of) directory users — every user row is built
    // on demand via ListView.builder rather than eagerly on every keystroke.
    final header = <Widget>[
      if (widget.onAssignMe != null && q.isEmpty)
        ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.accentSoft,
            child: const Icon(
              LucideIcons.user,
              color: AppColors.accentStrong,
              size: 18,
            ),
          ),
          title: Text(
            context.t('issues.assignToMe'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          onTap: widget.multiSelect && widget.meId != null
              ? () {
                  if (!_selected.contains(widget.meId)) _toggle(widget.meId!);
                }
              : widget.onAssignMe,
        ),
      if (q.isEmpty)
        ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.canvas2,
            child: Icon(LucideIcons.ban, color: AppColors.inkSoft, size: 18),
          ),
          title: Text(
            context.t(
              widget.multiSelect ? 'issues.clearAssignees' : 'issues.unassign',
            ),
          ),
          onTap: widget.multiSelect
              ? () {
                  setState(_selected.clear);
                  widget.onSelectionChanged?.call(_selected);
                }
              : widget.onUnassign,
        ),
      if (q.isEmpty) const Divider(height: 1),
    ];

    final showEmpty = filtered.isEmpty;
    final list = ListView.builder(
      padding: EdgeInsets.only(bottom: widget.anchored ? 6 : 16),
      shrinkWrap: widget.anchored,
      itemCount: header.length + (showEmpty ? 1 : filtered.length),
      itemBuilder: (context, i) {
        if (i < header.length) return header[i];
        if (showEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                context.t('issues.noPeopleFound'),
                style: TextStyle(color: AppColors.inkFaint),
              ),
            ),
          );
        }
        final u = filtered[i - header.length];
        return ListTile(
          leading: HiveAvatar(
            name: u.displayName,
            imageUrl: u.avatarUrl,
            size: 34,
          ),
          title: Text(
            u.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // Picking who to hand work to is a moment to get the person right,
          // so the pronouns sit on the row rather than a hover away.
          subtitle: Text(
            [userHandle(u.username), ?normalizePronouns(u.pronouns)].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: widget.multiSelect
              ? Icon(
                  _selected.contains(u.id)
                      ? LucideIcons.checkSquare
                      : LucideIcons.square,
                  size: 20,
                  color: _selected.contains(u.id)
                      ? AppColors.accent
                      : AppColors.inkFaint,
                )
              : (u.id == widget.meId
                    ? const Icon(
                        LucideIcons.star,
                        size: 16,
                        color: AppColors.accent,
                      )
                    : null),
          onTap: widget.multiSelect
              ? () => _toggle(u.id)
              : () => widget.onSelect(u.id),
        );
      },
    );

    // Anchored popover: no grab handle, and the list flexes to the host panel's
    // constraints (the popover already sizes/clamps itself on-screen).
    if (widget.anchored) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          searchField,
          Flexible(child: list),
        ],
      );
    }

    // The glass bottom-sheet wrapper already rides above the keyboard, so this
    // picker only needs to size itself; no extra viewInsets padding.
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.62,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.hairline,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          searchField,
          Expanded(child: list),
        ],
      ),
    );
  }
}
