part of 'global_search_dialog.dart';

// ─────────────────────────────── results ────────────────────────────────────

class _Results extends StatelessWidget {
  const _Results({
    required this.controller,
    required this.scroll,
    required this.tokens,
    required this.rowKeys,
    required this.onActivateEntry,
    required this.onApplyRecent,
    required this.onHoverIndex,
  });

  final GlobalSearchController controller;
  final ScrollController scroll;
  final SearchTokens tokens;
  final Map<int, GlobalKey> rowKeys;
  final void Function(SearchEntry) onActivateEntry;
  final void Function(String) onApplyRecent;
  final void Function(int) onHoverIndex;

  @override
  Widget build(BuildContext context) {
    rowKeys.clear();
    final children = <Widget>[];
    var flatIndex = 0;

    GlobalKey keyFor(int i) => rowKeys.putIfAbsent(i, () => GlobalKey());

    if (controller.showRecents) {
      children.add(
        _RecentsHead(
          tokens: tokens,
          hasItems: controller.recents.isNotEmpty,
          onClear: controller.clearRecents,
        ),
      );
      if (controller.recents.isEmpty) {
        children.add(
          _EmptyDeep(
            tokens: tokens,
            icon: null,
            title: context.t('search.empty.title'),
            subtitle: context.t('search.empty.subtitle'),
          ),
        );
      } else {
        for (final recent in controller.recents) {
          final i = flatIndex++;
          children.add(
            _RecentRow(
              key: keyFor(i),
              tokens: tokens,
              text: recent,
              selected: controller.selected == i,
              onTap: () => onApplyRecent(recent),
              onHover: () => onHoverIndex(i),
            ),
          );
        }
      }
    } else if (controller.flatLength == 0) {
      // Only surface "no matches" for a real query — a blank scoped query just
      // awaits its suggestions (don't flash an empty-state).
      if (controller.query.trim().isNotEmpty) {
        children.add(
          _EmptyDeep(
            tokens: tokens,
            icon: LucideIcons.searchX,
            title: context.t(
              'search.noMatch',
              variables: {'q': controller.query.trim()},
            ),
            subtitle: context.t('search.noMatchSub'),
          ),
        );
      }
    } else {
      for (final group in controller.groups) {
        children.add(
          _GroupLabel(
            tokens: tokens,
            icon: kSearchCatMeta[group.cat]!.icon,
            label: context.t(kSearchCatMeta[group.cat]!.labelKey),
          ),
        );
        for (final entry in group.items) {
          final i = flatIndex++;
          children.add(
            _ResultRow(
              key: keyFor(i),
              tokens: tokens,
              entry: entry,
              query: controller.query,
              selected: controller.selected == i,
              onTap: () => onActivateEntry(entry),
              onHover: () => onHoverIndex(i),
            ),
          );
        }
      }
    }

    return Scrollbar(
      controller: scroll,
      child: SingleChildScrollView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

// ─────────────────────────────── rows ───────────────────────────────────────

/// Shared selectable lozenge: hover/selected tint, inset highlight, the 3px
/// accent bar on the left edge and the trailing `↵` reveal on selection.
class _RowShell extends StatelessWidget {
  const _RowShell({
    required this.tokens,
    required this.selected,
    required this.onTap,
    required this.onHover,
    required this.children,
  });

  final SearchTokens tokens;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? tokens.selTint : Colors.transparent,
                borderRadius: BorderRadius.circular(15),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: tokens.selEdge,
                          offset: const Offset(0, 1),
                          blurRadius: 0,
                          spreadRadius: -0.5,
                        ),
                      ]
                    : null,
              ),
              child: Row(children: children),
            ),
            if (selected)
              Container(
                width: 3,
                height: 18,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    super.key,
    required this.tokens,
    required this.entry,
    required this.query,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final SearchTokens tokens;
  final SearchEntry entry;
  final String query;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      tokens: tokens,
      selected: selected,
      onTap: onTap,
      onHover: onHover,
      children: [
        _leading(),
        const SizedBox(width: 13),
        Expanded(child: _body(context)),
        const SizedBox(width: 8),
        _trailing(),
      ],
    );
  }

  Widget _leading() {
    switch (entry.cat) {
      case SearchCat.issues:
        return TypeGlyph(type: entry.issueType ?? 'TASK', size: 34);
      case SearchCat.projects:
        return _HexChip(
          text: entry.keyChipText ?? '',
          color: entry.keyChipColor ?? AppColors.stBacklog,
        );
      case SearchCat.people:
        return HiveAvatar(
          name: entry.avatarName ?? entry.title,
          imageUrl: entry.avatarUrl,
          size: 34,
        );
      case SearchCat.commands:
      case SearchCat.boards:
      case SearchCat.docs:
        return _IconTile(
          tokens: tokens,
          icon: entry.leadingIcon ?? LucideIcons.zap,
        );
    }
  }

  Widget _body(BuildContext context) {
    Widget title = Text.rich(
      TextSpan(
        children: _highlightSpans(
          entry.title,
          query,
          TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: tokens.ink,
            letterSpacing: -0.1,
          ),
          tokens.markBg,
        ),
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (entry.archived) {
      // Archive-keyword hits: badge the row so a soft-deleted issue/project is
      // never mistaken for an active one.
      title = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: title),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  LucideIcons.archive,
                  size: 10,
                  color: AppColors.accentStrong,
                ),
                const SizedBox(width: 4),
                Text(
                  context.t('issues.filterArchived'),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accentStrong,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (entry.cat == SearchCat.issues) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          title,
          const SizedBox(height: 2),
          Row(
            children: [
              Flexible(
                child: Text(
                  entry.mono ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    fontFamily: AppTheme.fontMono,
                    fontSize: 11,
                    color: tokens.inkSoft,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: entry.statusColor ?? tokens.inkFaint,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  entry.statusName ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: tokens.inkSoft),
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (entry.subtitle == null) {
      return title;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        title,
        const SizedBox(height: 2),
        Text(
          entry.subtitle!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, color: tokens.inkSoft),
        ),
      ],
    );
  }

  Widget _trailing() {
    final meta = <Widget>[];
    switch (entry.cat) {
      case SearchCat.issues:
        if (entry.avatarName != null) {
          meta.add(
            HiveAvatar(
              name: entry.avatarName!,
              imageUrl: entry.avatarUrl,
              size: 22,
            ),
          );
        }
      case SearchCat.projects:
        if (entry.memberNames != null && entry.memberNames!.isNotEmpty) {
          meta.add(
            HiveAvatarStack(names: entry.memberNames!, size: 20, max: 3),
          );
        }
      case SearchCat.commands:
        if (entry.hint != null) {
          meta.add(_KbdHint(tokens: tokens, text: entry.hint!));
        }
      case SearchCat.people:
      case SearchCat.boards:
      case SearchCat.docs:
        break;
    }
    if (selected) {
      if (meta.isNotEmpty) meta.add(const SizedBox(width: 8));
      meta.add(
        Text(
          '↵',
          style: TextStyle(
            fontFamily: AppTheme.fontMono,
            fontSize: 12,
            color: tokens.inkFaint,
          ),
        ),
      );
    }
    if (meta.isEmpty) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: meta);
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({
    super.key,
    required this.tokens,
    required this.text,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final SearchTokens tokens;
  final String text;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      tokens: tokens,
      selected: selected,
      onTap: onTap,
      onHover: onHover,
      children: [
        _IconTile(tokens: tokens, icon: LucideIcons.clock),
        const SizedBox(width: 13),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: tokens.ink,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Icon(LucideIcons.arrowUpLeft, size: 15, color: tokens.inkFaint),
      ],
    );
  }
}
