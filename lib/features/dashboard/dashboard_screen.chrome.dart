part of 'dashboard_screen.dart';

// ══════════════════════════ Card header ════════════════════════════════════

class _CardHead extends StatelessWidget {
  const _CardHead({
    required this.title,
    this.subLabel,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subLabel;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
              color: AppColors.ink,
            ),
          ),
        ),
        if (subLabel != null)
          Text(
            subLabel!,
            style: TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 12,
              color: AppColors.inkFaint,
            ),
          ),
        if (actionLabel != null && onAction != null)
          GestureDetector(
            onTap: onAction,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  actionLabel!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accentStrong,
                  ),
                ),
                const SizedBox(width: 3),
                const Icon(
                  LucideIcons.arrowRight,
                  size: 13,
                  color: AppColors.accentStrong,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ══════════════════════ Customize (edit mode) ══════════════════════════════

/// The header toggle. Desktop/tablet show icon + label; mobile shows the icon
/// only. In edit mode it turns amber and becomes a "Done" (save) action.
class _CustomizeButton extends StatelessWidget {
  const _CustomizeButton({
    required this.editing,
    required this.saving,
    required this.compact,
    required this.onPressed,
  });

  final bool editing;
  final bool saving;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final label = context.t(
      editing ? 'dashboard.done_editing' : 'dashboard.customize',
    );
    final icon = editing ? LucideIcons.check : LucideIcons.settings2;
    final bg = editing
        ? AppColors.accent
        : (dark
              ? Colors.white.withValues(alpha: .09)
              : Colors.white.withValues(alpha: .6));
    final fg = editing ? const Color(0xFF2A2410) : AppColors.ink;
    final border = editing
        ? Colors.transparent
        : (dark
              ? Colors.white.withValues(alpha: .14)
              : Colors.white.withValues(alpha: .7));

    final Widget content = saving
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        : (compact
              ? Icon(icon, size: 18, color: fg)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: fg),
                    const SizedBox(width: 7),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ],
                ));

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: saving ? null : onPressed,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 40,
            width: compact ? 40 : null,
            alignment: Alignment.center,
            padding: compact
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 15),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Wraps a card in edit mode: dims it when hidden, blocks its own interactions,
/// and overlays a show/hide eye toggle.
class _HideableCard extends StatelessWidget {
  const _HideableCard({
    required this.hidden,
    required this.onToggle,
    required this.child,
  });

  final bool hidden;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // The card is inert while editing — no accidental navigation.
        IgnorePointer(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: hidden ? 0.4 : 1,
            child: child,
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: _EyeToggle(hidden: hidden, onTap: onToggle),
        ),
      ],
    );
  }
}

class _EyeToggle extends StatelessWidget {
  const _EyeToggle({required this.hidden, required this.onTap});

  final bool hidden;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark
          ? const Color(0xFF232140).withValues(alpha: .82)
          : Colors.white.withValues(alpha: .9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(
            hidden ? LucideIcons.eyeOff : LucideIcons.eye,
            size: 16,
            color: hidden ? AppColors.inkSoft : AppColors.accentStrong,
          ),
        ),
      ),
    );
  }
}

// ══════════════════════ Edit toolbar + pickers ═════════════════════════════

/// The inline edit controls: hero-board picker, data scope and team-ranking
/// scope. Every change flows out through [onChanged] (which re-fetches).
class _EditToolbar extends StatelessWidget {
  const _EditToolbar({
    required this.boards,
    required this.draft,
    required this.projects,
    required this.teams,
    required this.onChanged,
  });

  final List<DashboardBoardOption> boards;
  final DashboardPrefs draft;
  final List<Project> projects;
  final List<Team> teams;
  final ValueChanged<DashboardPrefs> onChanged;

  DashboardBoardOption? get _selectedBoard {
    for (final b in boards) {
      if (b.id == draft.boardId) return b;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final boardLabel =
        _selectedBoard?.name ?? context.t('dashboard.heroBoardAuto');
    final projectsLabel = draft.projectIds.isEmpty
        ? context.t('dashboard.scopeAllProjects')
        : context.t(
            'dashboard.scopeProjectsCount',
            variables: {'count': '${draft.projectIds.length}'},
          );
    final teamsLabel = draft.teamIds.isEmpty
        ? context.t('dashboard.scopeAllTeams')
        : context.t(
            'dashboard.scopeTeamsCount',
            variables: {'count': '${draft.teamIds.length}'},
          );

    return _GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.sparkles,
                size: 15,
                color: AppColors.accentStrong,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.t('dashboard.editHint'),
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) {
              final fields = <Widget>[
                _PickerField(
                  icon: LucideIcons.layoutDashboard,
                  label: context.t('dashboard.heroBoard'),
                  value: boardLabel,
                  onTap: (rect) => _pickBoard(context, rect),
                ),
                _PickerField(
                  icon: LucideIcons.folderKanban,
                  label: context.t('dashboard.dataScope'),
                  value: projectsLabel,
                  onTap: (rect) => _pickProjects(context, rect),
                ),
                _PickerField(
                  icon: LucideIcons.usersRound,
                  label: context.t('dashboard.teamScope'),
                  value: teamsLabel,
                  onTap: (rect) => _pickTeams(context, rect),
                ),
              ];
              // Compact fixed-width fields (matching the popover width) that wrap
              // instead of stretching across the whole toolbar.
              const gap = 12.0;
              final width = c.maxWidth < _kPickerWidth
                  ? c.maxWidth
                  : _kPickerWidth;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final f in fields) SizedBox(width: width, child: f),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _pickBoard(BuildContext context, Rect anchor) async {
    final result = await showGlassAnchoredPopover<String>(
      context,
      anchorRect: anchor,
      width: _kPickerWidth,
      builder: (_) =>
          _BoardPickerSheet(boards: boards, selected: draft.boardId),
    );
    if (result == null) return; // dismissed
    onChanged(
      draft.copyWith(
        boardId: result.isEmpty ? null : result,
        clearBoard: result.isEmpty,
      ),
    );
  }

  Future<void> _pickProjects(BuildContext context, Rect anchor) async {
    final result = await showGlassAnchoredPopover<List<String>>(
      context,
      anchorRect: anchor,
      width: _kPickerWidth,
      builder: (_) => _ScopePickerSheet(
        title: context.t('dashboard.dataScope'),
        icon: LucideIcons.folderKanban,
        allLabel: context.t('dashboard.scopeAllProjects'),
        items: [for (final p in projects) (id: p.id, name: p.name)],
        selected: draft.projectIds.toSet(),
      ),
    );
    if (result == null) return;
    onChanged(draft.copyWith(projectIds: result));
  }

  Future<void> _pickTeams(BuildContext context, Rect anchor) async {
    final result = await showGlassAnchoredPopover<List<String>>(
      context,
      anchorRect: anchor,
      width: _kPickerWidth,
      builder: (_) => _ScopePickerSheet(
        title: context.t('dashboard.teamScope'),
        icon: LucideIcons.usersRound,
        allLabel: context.t('dashboard.scopeAllTeams'),
        items: [for (final t in teams) (id: t.id, name: t.name)],
        selected: draft.teamIds.toSet(),
      ),
    );
    if (result == null) return;
    onChanged(draft.copyWith(teamIds: result));
  }
}

/// A labelled, dropdown-like field that opens a picker anchored to itself on
/// tap (reports its own global rect so the popover attaches to the field).
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final ValueChanged<Rect> onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          final box = context.findRenderObject() as RenderBox?;
          final rect = box != null && box.hasSize
              ? box.localToGlobal(Offset.zero) & box.size
              : Rect.zero;
          onTap(rect);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: dark
                ? Colors.white.withValues(alpha: .05)
                : Colors.white.withValues(alpha: .55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: dark
                  ? Colors.white.withValues(alpha: .1)
                  : Colors.white.withValues(alpha: .7),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: AppColors.accentStrong),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                        color: AppColors.inkSoft,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(LucideIcons.chevronDown, size: 15, color: AppColors.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single-select list of the caller's boards (plus "Automatic"). Pops the
/// chosen board id, an empty string for automatic, or null on cancel.
class _BoardPickerSheet extends StatelessWidget {
  const _BoardPickerSheet({required this.boards, required this.selected});

  final List<DashboardBoardOption> boards;
  final String? selected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.layoutDashboard,
          title: context.t('dashboard.heroBoard'),
          subtitle: context.t('dashboard.editHint'),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            children: [
              _ChoiceRow(
                icon: LucideIcons.sparkles,
                label: context.t('dashboard.heroBoardAuto'),
                selected: selected == null,
                onTap: () => Navigator.of(context).pop(''),
              ),
              for (final b in boards)
                _ChoiceRow(
                  icon: b.isScrum ? LucideIcons.zap : LucideIcons.columns3,
                  label: b.name,
                  selected: b.id == selected,
                  onTap: () => Navigator.of(context).pop(b.id),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Multi-select scope list with an "All" reset row. Pops the selected ids
/// (empty ⇒ all), or null on cancel.
class _ScopePickerSheet extends StatefulWidget {
  const _ScopePickerSheet({
    required this.title,
    required this.icon,
    required this.allLabel,
    required this.items,
    required this.selected,
  });

  final String title;
  final IconData icon;
  final String allLabel;
  final List<({String id, String name})> items;
  final Set<String> selected;

  @override
  State<_ScopePickerSheet> createState() => _ScopePickerSheetState();
}

class _ScopePickerSheetState extends State<_ScopePickerSheet> {
  late final Set<String> _sel = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: widget.icon,
          title: widget.title,
          subtitle: context.t('dashboard.editHint'),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            children: [
              _ChoiceRow(
                icon: LucideIcons.layoutGrid,
                label: widget.allLabel,
                selected: _sel.isEmpty,
                onTap: () => setState(_sel.clear),
              ),
              for (final it in widget.items)
                _ChoiceRow(
                  icon: LucideIcons.check,
                  showIcon: false,
                  label: it.name,
                  selected: _sel.contains(it.id),
                  onTap: () => setState(
                    () => _sel.contains(it.id)
                        ? _sel.remove(it.id)
                        : _sel.add(it.id),
                  ),
                ),
            ],
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('common.apply'),
          onConfirm: () => Navigator.of(context).pop(_sel.toList()),
        ),
      ],
    );
  }
}

/// A selectable row for the pickers: leading glyph, label, trailing check.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.showIcon = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppColors.accent.withValues(alpha: .5)
                  : AppColors.hairline,
            ),
          ),
          child: Row(
            children: [
              if (showIcon && icon != null) ...[
                Icon(
                  icon,
                  size: 16,
                  color: selected ? AppColors.accentStrong : AppColors.inkSoft,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  LucideIcons.check,
                  size: 16,
                  color: AppColors.accentStrong,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
