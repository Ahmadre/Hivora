import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_popup_menu.dart';
import 'data/knowledge_models.dart';
import 'data/knowledge_repository.dart';
import 'knowledge_tokens.dart';

/// Re-parent callback: move [id] under [parentId] (null = space root) within
/// [spaceId].
typedef ArticleMove =
    void Function(String id, {String? parentId, required String spaceId});

/// Space switcher + nested, folder-style article tree. Pages can be dragged onto
/// one another to nest (Confluence-style), dropped on the root zone to un-nest,
/// and each row offers add-sub-page / move-to-root / delete. Rendered in the
/// reader's left sidebar (≥ 720 px) and inside the phone drawer.
class KnowledgeTree extends StatelessWidget {
  const KnowledgeTree({
    super.key,
    required this.repo,
    required this.spaceId,
    required this.selectedId,
    required this.onSelect,
    required this.onSpaceChange,
    required this.onNewChild,
    required this.onMove,
    required this.onDelete,
  });

  final KnowledgeRepository repo;
  final String spaceId;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onSpaceChange;

  /// Create a new sub-page under [parentId].
  final ValueChanged<String> onNewChild;
  final ArticleMove onMove;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final inSpace = repo.articlesInSpace(spaceId);
    final roots = inSpace.where((a) => a.parentId == null).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassPopupMenu<String>(
            value: spaceId,
            onSelected: onSpaceChange,
            items: [
              for (final s in repo.spaces)
                GlassMenuItem(
                  value: s.id,
                  label: s.name,
                  leading: Icon(
                    lucideIcon(s.icon),
                    size: 16,
                    color: KbTokens.accent,
                  ),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(KbTokens.radiusControl),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      repo.spaceById(spaceId)?.name ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    lucideIcon('chevron-down'),
                    size: 16,
                    color: AppColors.inkFaint,
                  ),
                ],
              ),
            ),
          ),
        ),
        // Root drop zone — drop a page here to move it to the top level.
        _RootDropZone(spaceId: spaceId, repo: repo, onMove: onMove),
        for (final root in roots)
          _TreeBranch(
            repo: repo,
            article: root,
            inSpace: inSpace,
            depth: 0,
            selectedId: selectedId,
            onSelect: onSelect,
            onNewChild: onNewChild,
            onMove: onMove,
            onDelete: onDelete,
          ),
      ],
    );
  }
}

class _RootDropZone extends StatefulWidget {
  const _RootDropZone({
    required this.spaceId,
    required this.repo,
    required this.onMove,
  });

  final String spaceId;
  final KnowledgeRepository repo;
  final ArticleMove onMove;

  @override
  State<_RootDropZone> createState() => _RootDropZoneState();
}

class _RootDropZoneState extends State<_RootDropZone> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) {
        final article = widget.repo.articleById(d.data);
        // Only meaningful if it isn't already a root in this space.
        final already =
            article?.parentId == null && article?.spaceId == widget.spaceId;
        if (!already) setState(() => _hover = true);
        return !already;
      },
      onLeave: (_) => setState(() => _hover = false),
      onAcceptWithDetails: (d) {
        setState(() => _hover = false);
        widget.onMove(d.data, parentId: null, spaceId: widget.spaceId);
      },
      builder: (context, candidate, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: _hover ? 30 : 8,
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: _hover ? AppColors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: _hover ? Border.all(color: AppColors.accentLine) : null,
        ),
        alignment: Alignment.center,
        child: _hover
            ? Text(
                context.t('knowledge.moveToTopLevel'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: KbTokens.accent,
                ),
              )
            : null,
      ),
    );
  }
}

class _TreeBranch extends StatefulWidget {
  const _TreeBranch({
    required this.repo,
    required this.article,
    required this.inSpace,
    required this.depth,
    required this.selectedId,
    required this.onSelect,
    required this.onNewChild,
    required this.onMove,
    required this.onDelete,
  });

  final KnowledgeRepository repo;
  final KbArticle article;
  final List<KbArticle> inSpace;
  final int depth;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onNewChild;
  final ArticleMove onMove;
  final ValueChanged<String> onDelete;

  @override
  State<_TreeBranch> createState() => _TreeBranchState();
}

class _TreeBranchState extends State<_TreeBranch> {
  bool _open = true;

  /// Glass action menu for a tree row: move-to-root + delete.
  Widget _rowMenu(BuildContext context, bool canDelete) {
    return GlassPopupMenu<String>(
      value: '',
      width: 240,
      onSelected: (v) {
        if (v == 'root') {
          widget.onMove(
            widget.article.id,
            parentId: null,
            spaceId: widget.article.spaceId,
          );
        } else if (v == 'delete' && canDelete) {
          widget.onDelete(widget.article.id);
        }
      },
      items: [
        if (widget.article.parentId != null)
          GlassMenuItem(
            value: 'root',
            label: context.t('knowledge.moveToTopLevel'),
            leading: Icon(
              lucideIcon('panel-left'),
              size: 16,
              color: AppColors.inkSoft,
            ),
          ),
        GlassMenuItem(
          value: 'delete',
          label: canDelete
              ? context.t('knowledge.delete')
              : context.t('knowledge.deleteHasChildren'),
          enabled: canDelete,
          color: AppColors.danger,
          dividerAbove: widget.article.parentId != null,
          leading: Icon(
            lucideIcon('trash-2'),
            size: 16,
            color: AppColors.danger,
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          lucideIcon('ellipsis'),
          size: 15,
          color: AppColors.inkFaint,
        ),
      ),
    );
  }

  bool _hover = false;
  bool _dropHover = false;

  @override
  Widget build(BuildContext context) {
    final kids = widget.inSpace
        .where((a) => a.parentId == widget.article.id)
        .toList();
    final selected = widget.selectedId == widget.article.id;

    final row = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: _dropHover
            ? AppColors.accentSoft
            : selected
            ? AppColors.accentSoft
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => widget.onSelect(widget.article.id),
          child: Container(
            decoration: _dropHover
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.accentLine),
                  )
                : null,
            padding: EdgeInsets.fromLTRB(8 + widget.depth * 14, 5, 4, 5),
            child: Row(
              children: [
                if (kids.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(() => _open = !_open),
                    child: Icon(
                      lucideIcon(_open ? 'chevron-down' : 'chevron-right'),
                      size: 15,
                      color: AppColors.inkFaint,
                    ),
                  )
                else
                  const SizedBox(width: 15),
                const SizedBox(width: 6),
                Icon(
                  lucideIcon(widget.article.icon),
                  size: 15,
                  color: selected ? KbTokens.accent : AppColors.inkSoft,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.article.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? AppColors.ink : AppColors.inkSoft,
                    ),
                  ),
                ),
                // Row actions (reveal on hover; always present for touch).
                if (_hover) ...[
                  _RowAction(
                    icon: 'plus',
                    tooltip: context.t('knowledge.addSubPage'),
                    onTap: () => widget.onNewChild(widget.article.id),
                  ),
                  _rowMenu(context, kids.isEmpty),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    // Drag the page; drop another page onto it to nest.
    final draggable = Draggable<String>(
      data: widget.article.id,
      dragAnchorStrategy: childDragAnchorStrategy,
      feedback: _DragChip(
        title: widget.article.title,
        icon: widget.article.icon,
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: row),
      child: DragTarget<String>(
        onWillAcceptWithDetails: (d) {
          // Reject self / moving a page into its own subtree.
          final ok =
              d.data != widget.article.id &&
              !widget.repo.isSelfOrAncestor(d.data, widget.article.id);
          if (ok) setState(() => _dropHover = true);
          return ok;
        },
        onLeave: (_) => setState(() => _dropHover = false),
        onAcceptWithDetails: (d) {
          setState(() => _dropHover = false);
          widget.onMove(
            d.data,
            parentId: widget.article.id,
            spaceId: widget.article.spaceId,
          );
        },
        builder: (context, _, _) => row,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        draggable,
        if (_open)
          for (final c in kids)
            _TreeBranch(
              repo: widget.repo,
              article: c,
              inSpace: widget.inSpace,
              depth: widget.depth + 1,
              selectedId: widget.selectedId,
              onSelect: widget.onSelect,
              onNewChild: widget.onNewChild,
              onMove: widget.onMove,
              onDelete: widget.onDelete,
            ),
      ],
    );
  }
}

class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final String icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(lucideIcon(icon), size: 15, color: AppColors.inkFaint),
        ),
      ),
    );
  }
}

class _DragChip extends StatelessWidget {
  const _DragChip({required this.title, required this.icon});
  final String title;
  final String icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.accentLine),
          boxShadow: [
            BoxShadow(
              color: AppColors.navyDeep.withValues(alpha: 0.2),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(lucideIcon(icon), size: 15, color: KbTokens.accent),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
