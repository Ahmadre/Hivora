import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality, LiquidRoundedSuperellipse;

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/hex_mark.dart';
import '../../core/widgets/hive_widgets.dart';
import '../search/search_tokens.dart';
import 'board_filter.dart';

const double _kCompactBreakpoint = 610;

/// Opens the board filter as a liquid-glass popover anchored to the filter
/// button (read from [anchorKey]). Mirrors the global-search palette: a search
/// field, scope chips (one per filter criterion) and a searchable, multi-select
/// option list. Every toggle applies live through [onChanged].
Future<void> openBoardFilter(
  BuildContext context, {
  required GlobalKey anchorKey,
  required BoardFilter filter,
  required BoardFilterOptions options,
  required Map<String, String> names,
  Map<String, String> avatars = const {},
  Map<String, String> pronouns = const {},
  required Map<String, String> sprintNames,
  Map<String, String> epicNames = const {},
  required ValueChanged<BoardFilter> onChanged,
}) {
  final box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  final Rect anchorRect = (box != null && box.hasSize)
      ? (box.localToGlobal(Offset.zero) & box.size)
      : Rect.zero;

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => _BoardFilterDialog(
      anchorRect: anchorRect,
      initial: filter,
      options: options,
      names: names,
      avatars: avatars,
      pronouns: pronouns,
      sprintNames: sprintNames,
      epicNames: epicNames,
      onChanged: onChanged,
    ),
    transitionBuilder: (_, _, _, child) => child,
  );
}

/// One selectable option within a scope.
class _Opt {
  const _Opt({required this.value, required this.label, required this.leading});
  final String value;
  final String label;
  final Widget leading;
}

class _BoardFilterDialog extends StatefulWidget {
  const _BoardFilterDialog({
    required this.anchorRect,
    required this.initial,
    required this.options,
    required this.names,
    required this.avatars,
    required this.pronouns,
    required this.sprintNames,
    required this.epicNames,
    required this.onChanged,
  });

  final Rect anchorRect;
  final BoardFilter initial;
  final BoardFilterOptions options;
  final Map<String, String> names;
  final Map<String, String> avatars;
  final Map<String, String> pronouns;
  final Map<String, String> sprintNames;
  final Map<String, String> epicNames;
  final ValueChanged<BoardFilter> onChanged;

  @override
  State<_BoardFilterDialog> createState() => _BoardFilterDialogState();
}

class _BoardFilterDialogState extends State<_BoardFilterDialog> {
  late BoardFilter _filter = widget.initial;
  BoardFilterFacet _scope = BoardFilterFacet.state;
  String _query = '';

  /// The scopes shown as chips, in the order the user requested.
  static const _facets = [
    BoardFilterFacet.state,
    BoardFilterFacet.assignee,
    BoardFilterFacet.priority,
    BoardFilterFacet.type,
    BoardFilterFacet.epic,
    BoardFilterFacet.sprint,
    BoardFilterFacet.author,
    BoardFilterFacet.label,
  ];

  void _toggle(String value) {
    setState(() => _filter = _filter.toggle(_scope, value));
    widget.onChanged(_filter);
  }

  void _clear() {
    if (_filter.isEmpty) return;
    setState(() => _filter = BoardFilter.empty);
    widget.onChanged(_filter);
  }

  void _close() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  String _scopeLabel(BoardFilterFacet f) => switch (f) {
    BoardFilterFacet.state => context.t('board.filterSection.status'),
    BoardFilterFacet.assignee => context.t('board.filterSection.assignee'),
    BoardFilterFacet.priority => context.t('board.filterSection.priority'),
    BoardFilterFacet.type => context.t('board.filterSection.type'),
    BoardFilterFacet.epic => context.t('board.filterSection.epic'),
    BoardFilterFacet.sprint => context.t('board.filterSection.sprint'),
    BoardFilterFacet.author => context.t('board.filterSection.author'),
    BoardFilterFacet.label => context.t('board.filterSection.label'),
  };

  IconData _scopeIcon(BoardFilterFacet f) => switch (f) {
    BoardFilterFacet.state => LucideIcons.circleDot,
    BoardFilterFacet.assignee => LucideIcons.user,
    BoardFilterFacet.priority => LucideIcons.flag,
    BoardFilterFacet.type => LucideIcons.shapes,
    BoardFilterFacet.epic => LucideIcons.zap,
    BoardFilterFacet.sprint => LucideIcons.zap,
    BoardFilterFacet.author => LucideIcons.penLine,
    BoardFilterFacet.label => LucideIcons.tag,
  };

  /// Builds the option list for the active scope.
  List<_Opt> _optionsFor(BoardFilterFacet f) {
    String name(String id) => widget.names[id] ?? id;
    String? avatar(String id) => widget.avatars[id];
    String? saidPronouns(String id) => widget.pronouns[id];
    switch (f) {
      case BoardFilterFacet.state:
        return [
          for (final s in widget.options.states)
            _Opt(
              value: s,
              label: stateLabel(s),
              leading: _StateDot(state: s),
            ),
        ];
      case BoardFilterFacet.type:
        return [
          for (final t in widget.options.types)
            _Opt(
              value: t,
              label: _facetLabel(context, 'type', t),
              leading: TypeGlyph(type: t, size: 18),
            ),
        ];
      case BoardFilterFacet.priority:
        return [
          for (final p in widget.options.priorities)
            _Opt(
              value: p,
              label: _facetLabel(context, 'priority', p),
              leading: SizedBox(
                width: 18,
                child: Center(child: PriorityFlag(priority: p)),
              ),
            ),
        ];
      case BoardFilterFacet.assignee:
        return [
          for (final id in widget.options.assignees)
            _Opt(
              value: id,
              label: name(id),
              leading: HiveAvatar(
                name: name(id),
                imageUrl: avatar(id),
                pronouns: saidPronouns(id),
                size: 20,
              ),
            ),
        ];
      case BoardFilterFacet.author:
        return [
          for (final id in widget.options.authors)
            _Opt(
              value: id,
              label: name(id),
              leading: HiveAvatar(
                name: name(id),
                imageUrl: avatar(id),
                pronouns: saidPronouns(id),
                size: 20,
              ),
            ),
        ];
      case BoardFilterFacet.sprint:
        return [
          _Opt(
            value: BoardFilter.noSprint,
            label: context.t('issues.noSprint'),
            leading: Icon(LucideIcons.ban, size: 18, color: AppColors.inkFaint),
          ),
          for (final id in widget.options.sprints)
            _Opt(
              value: id,
              label: widget.sprintNames[id] ?? id,
              leading: const Icon(
                LucideIcons.zap,
                size: 18,
                color: AppColors.accentStrong,
              ),
            ),
        ];
      case BoardFilterFacet.label:
        return [
          for (final l in widget.options.labels)
            _Opt(
              value: l,
              label: l,
              leading: Icon(
                LucideIcons.tag,
                size: 16,
                color: AppColors.inkFaint,
              ),
            ),
        ];
      case BoardFilterFacet.epic:
        return [
          for (final id in widget.options.epics)
            _Opt(
              value: id,
              label: widget.epicNames[id] ?? id,
              leading: const TypeGlyph(type: 'EPIC', size: 18),
            ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SearchTokens.of(Theme.of(context).brightness);
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final compact = size.width < _kCompactBreakpoint;
    final anim = ModalRoute.of(context)!.animation!;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    const margin = 12.0;
    final panelWidth = compact
        ? math.min(380.0, size.width - margin * 2)
        : 360.0;

    final anchor = widget.anchorRect;
    double left = anchor.right - panelWidth;
    left = left.clamp(
      margin,
      math.max(margin, size.width - panelWidth - margin),
    );

    final belowTop = anchor.bottom + 8;
    final roomBelow = size.height - belowTop - margin - pad.bottom;
    final roomAbove = anchor.top - 8 - margin - pad.top;
    final placeAbove = roomBelow < 280 && roomAbove > roomBelow;
    final maxHeight = (placeAbove ? roomAbove : roomBelow).clamp(220.0, 560.0);
    final top = placeAbove ? null : belowTop;
    final bottom = placeAbove ? (size.height - anchor.top + 8) : null;

    final panel = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: panelWidth, maxHeight: maxHeight),
      child: _shadowed(tokens, BorderRadius.circular(20), _glassPanel(tokens)),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          bottom: bottom,
          width: panelWidth,
          child: AnimatedBuilder(
            animation: anim,
            builder: (_, child) {
              if (reduceMotion) {
                return Opacity(opacity: anim.value, child: child);
              }
              final t = const Cubic(
                0.34,
                1.3,
                0.64,
                1,
              ).transform(anim.value.clamp(0.0, 1.0));
              return Opacity(
                opacity: (anim.value / 0.6).clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.92 + 0.08 * t,
                  alignment: placeAbove
                      ? Alignment.bottomRight
                      : Alignment.topRight,
                  child: child,
                ),
              );
            },
            child: panel,
          ),
        ),
      ],
    );
  }

  Widget _shadowed(SearchTokens tokens, BorderRadius radius, Widget child) =>
      GlassPanelShadow(
        radius: radius,
        shadows: tokens.panelShadow,
        child: child,
      );

  Widget _glassPanel(SearchTokens tokens) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final content = Stack(
      children: [
        Material(type: MaterialType.transparency, child: _column(tokens)),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _RimPainter(
                radius: 20,
                edge: tokens.edge,
                edgeSoft: tokens.edgeSoft,
              ),
            ),
          ),
        ),
      ],
    );
    return GlassContainer(
      useOwnLayer: true,
      quality: GlassQuality.premium,
      clipBehavior: Clip.antiAlias,
      shape: const LiquidRoundedSuperellipse(borderRadius: 20),
      settings: liquidGlassPanelSettings(
        glassFill: tokens.glassFill,
        dark: dark,
      ),
      child: content,
    );
  }

  Widget _column(SearchTokens tokens) {
    final all = _optionsFor(_scope);
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? all
        : all.where((o) => o.label.toLowerCase().contains(q)).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _field(tokens),
        _scopes(tokens),
        Flexible(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: shown.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 28,
                      horizontal: 18,
                    ),
                    child: Container(
                      alignment: Alignment.center,
                      height: 72,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 10,
                        children: [
                          /// The amber Hinata hex-mark with a small "x" badge
                          /// stacked at its top-right corner, signalling that
                          /// there is nothing left to filter here.
                          HexMark(size: 34, color: tokens.inkFaint),
                          Text(
                            context.t('board.filterNoOptions'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: tokens.inkFaint,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 8,
                    ),
                    shrinkWrap: true,
                    itemCount: shown.length,
                    itemBuilder: (_, i) {
                      final o = shown[i];
                      return _OptionRow(
                        tokens: tokens,
                        option: o,
                        selected: _filter.facet(_scope).contains(o.value),
                        onTap: () => _toggle(o.value),
                      );
                    },
                  ),
          ),
        ),
        _footer(tokens),
      ],
    );
  }

  Widget _field(SearchTokens tokens) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.hairline)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.search, size: 18, color: tokens.inkSoft),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              autofocus: false,
              textInputAction: TextInputAction.search,
              cursorColor: tokens.ink,
              onChanged: (v) => setState(() => _query = v),
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                color: tokens.ink,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                filled: false,
                errorBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: context.t(
                  'board.filterSearch',
                  variables: {'scope': _scopeLabel(_scope)},
                ),
                hintStyle: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w400,
                  color: tokens.inkFaint,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scopes(SearchTokens tokens) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.hairline)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            for (final f in _facets) ...[
              _ScopeChip(
                tokens: tokens,
                icon: _scopeIcon(f),
                label: _scopeLabel(f),
                count: _filter.facet(f).length,
                active: _scope == f,
                onTap: () => setState(() {
                  _scope = f;
                  _query = '';
                }),
              ),
              const SizedBox(width: 7),
            ],
          ],
        ),
      ),
    );
  }

  Widget _footer(SearchTokens tokens) {
    final count = _filter.activeCount;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      decoration: BoxDecoration(
        color: tokens.field,
        border: Border(top: BorderSide(color: tokens.hairline)),
      ),
      child: Row(
        children: [
          Text(
            context.t('board.activeFilters', variables: {'count': '$count'}),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: tokens.inkSoft,
            ),
          ),
          const Spacer(),
          if (count > 0)
            TextButton(
              onPressed: _clear,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accentStrong,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(context.t('board.clearFilters')),
            ),
        ],
      ),
    );
  }
}

class _OptionRow extends StatefulWidget {
  const _OptionRow({
    required this.tokens,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final SearchTokens tokens;
  final _Opt option;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_OptionRow> createState() => _OptionRowState();
}

class _OptionRowState extends State<_OptionRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: widget.selected
                ? t.selTint
                : (_hover ? t.rowHover : Colors.transparent),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              SizedBox(width: 22, child: Center(child: widget.option.leading)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                widget.selected
                    ? LucideIcons.circleCheckBig
                    : LucideIcons.circle,
                size: 18,
                color: widget.selected ? AppColors.accentStrong : t.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    required this.tokens,
    required this.icon,
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final SearchTokens tokens;
  final IconData icon;
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? AppColors.accentStrong : tokens.inkSoft;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.accentSoft : tokens.field,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          border: Border.all(
            color: active ? AppColors.accentLine : tokens.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: active ? AppColors.accentStrong : tokens.ink,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(minWidth: 16),
                height: 16,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontMono,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2A2410),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StateDot extends StatelessWidget {
  const _StateDot({required this.state});
  final String state;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: AppColors.stateColor(state.toUpperCase()),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Localised label for an enum-like [code] under [prefix] (`type`/`priority`),
/// humanising the raw code when no translation exists (e.g. legacy values).
String _facetLabel(BuildContext context, String prefix, String code) {
  final key = '$prefix.${code.toLowerCase()}';
  final value = context.t(key);
  if (value != key) return value;
  return code
      .split(RegExp(r'[_ ]'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}

/// 1px specular rim — matches the global search panel's rim.
class _RimPainter extends CustomPainter {
  _RimPainter({
    required this.radius,
    required this.edge,
    required this.edgeSoft,
  });
  final double radius;
  final Color edge;
  final Color edgeSoft;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.5),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        [edge, edgeSoft, Colors.transparent, edgeSoft],
        const [0.0, 0.28, 0.52, 1.0],
      );
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.radius != radius || old.edge != edge || old.edgeSoft != edgeSoft;
}
