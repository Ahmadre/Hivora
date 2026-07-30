import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality, LiquidRoundedSuperellipse;

import '../../core/repositories/search_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/storage/app_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/hex_mark.dart';
import '../../core/widgets/hive_widgets.dart';
import 'global_search_controller.dart';
import 'search_models.dart';
import 'search_tokens.dart';

part 'global_search_dialog.results.dart';
part 'global_search_dialog.pieces.dart';

/// Phone breakpoint — below this the palette becomes a full-screen sheet that
/// slides down from the top (matches the app's phone breakpoint, §3.5).
const double _kPhoneBreakpoint = 610;

/// Opens the global search / command palette over a dimmed, blurred app.
///
/// Uses [showGeneralDialog] so we own the scrim, blur and spring (§3.1). The
/// enter/exit motion lives inside [GlobalSearchDialog], driven by the route
/// animation, so it can branch between the desktop spring and the mobile sheet.
Future<void> openGlobalSearch(BuildContext context) {
  final controller = GlobalSearchController(
    repository: context.read<SearchRepository>(),
    storage: context.read<AppStorage>(),
  );
  // Localise command labels against the launching context, then load async.
  controller.load(t: (key) => context.t(key));

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent, // we paint our own scrim
    transitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (_, _, _) => GlobalSearchDialog(controller: controller),
    // Motion is handled inside the dialog (reads the route animation), so the
    // transition builder is a pass-through.
    transitionBuilder: (_, _, _, child) => child,
  ).whenComplete(controller.dispose);
}

class GlobalSearchDialog extends StatefulWidget {
  const GlobalSearchDialog({super.key, required this.controller});

  final GlobalSearchController controller;

  @override
  State<GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<GlobalSearchDialog> {
  GlobalSearchController get _c => widget.controller;

  final _text = TextEditingController();
  late final FocusNode _fieldNode;
  final _scroll = ScrollController();
  final _rowKeys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _fieldNode = FocusNode(onKeyEvent: _onKey);
    _c.addListener(_onControllerChange);
  }

  @override
  void dispose() {
    _c.removeListener(_onControllerChange);
    _text.dispose();
    _fieldNode.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onControllerChange() {
    // Sync the field when a recent search is applied programmatically.
    if (_text.text != _c.query) {
      _text.value = TextEditingValue(
        text: _c.query,
        selection: TextSelection.collapsed(offset: _c.query.length),
      );
    }
    // Keep the selected row in view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rowCtx = _rowKeys[_c.selected]?.currentContext;
      if (rowCtx != null) {
        Scrollable.ensureVisible(
          rowCtx,
          alignment: 0.12,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
        );
      }
    });
    if (mounted) setState(() {});
  }

  // ---- keyboard model (§4.5) ----
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        _close();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _c.moveSelection(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _c.moveSelection(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _activateSelected();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.tab:
        _c.cycleScope(!HardwareKeyboard.instance.isShiftPressed);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _close() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  void _activateSelected() {
    if (_c.showRecents) {
      final recent = _c.selectedRecent;
      if (recent != null) _applyRecent(recent);
      return;
    }
    final entry = _c.selectedEntry;
    if (entry != null) _activateEntry(entry);
  }

  void _applyRecent(String recent) {
    _c.setQuery(recent);
    _fieldNode.requestFocus();
  }

  void _activateEntry(SearchEntry entry) {
    final query = _c.query.trim();
    if (query.isNotEmpty) _c.pushRecent(query);
    // Navigate while the dialog (and its context) is still mounted, then
    // dismiss — the dialog sits above the shell on the root navigator.
    entry.onSelect(context);
    if (entry.closesOnSelect) _close();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final mobile = size.width < _kPhoneBreakpoint;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final tokens = SearchTokens.of(Theme.of(context).brightness);
    final anim = ModalRoute.of(context)!.animation!;

    return Stack(
      children: [
        // ---- scrim: dim + blur the app behind (§3.2) ----
        AnimatedBuilder(
          animation: anim,
          builder: (_, _) {
            final t = anim.value.clamp(0.0, 1.0);
            Widget scrim = ColoredBox(
              color: tokens.scrim.withValues(alpha: tokens.scrim.a * t),
              child: const SizedBox.expand(),
            );
            if (!reduceMotion) {
              scrim = BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 7 * t, sigmaY: 7 * t),
                child: scrim,
              );
            }
            return Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: scrim,
              ),
            );
          },
        ),
        // ---- the panel ----
        Positioned.fill(
          child: SafeArea(
            top: !mobile,
            bottom: !mobile,
            child: mobile
                ? _mobilePanel(tokens, anim, reduceMotion, size)
                : _desktopPanel(tokens, anim, reduceMotion, size),
          ),
        ),
      ],
    );
  }

  // ---- desktop: centered dialog with the spring entrance (§3.5) ----
  Widget _desktopPanel(
    SearchTokens tokens,
    Animation<double> anim,
    bool reduceMotion,
    Size size,
  ) {
    final maxW = math.min(640.0, size.width - 48);
    final maxH = math.min(620.0, size.height * 0.78);
    final panel = Padding(
      padding: EdgeInsets.fromLTRB(24, size.height * 0.11, 24, 24),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
          child: _shadowed(
            tokens,
            BorderRadius.circular(28),
            _glassPanel(tokens, radius: 28, mobile: false),
          ),
        ),
      ),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, child) {
        if (reduceMotion) return Opacity(opacity: anim.value, child: child);
        final curved = const Cubic(
          0.34,
          1.56,
          0.64,
          1,
        ).transform(anim.value.clamp(0.0, 1.0));
        final fade = (anim.value / 0.6).clamp(0.0, 1.0);
        return Opacity(
          opacity: fade,
          child: Transform.translate(
            offset: Offset(0, (1 - curved) * -14),
            child: Transform.scale(
              scale: 0.965 + 0.035 * curved,
              alignment: Alignment.topCenter,
              child: child,
            ),
          ),
        );
      },
      child: panel,
    );
  }

  // ---- mobile: full-screen sheet sliding from the top (§3.5) ----
  Widget _mobilePanel(
    SearchTokens tokens,
    Animation<double> anim,
    bool reduceMotion,
    Size size,
  ) {
    const radius = BorderRadius.vertical(bottom: Radius.circular(26));
    final panel = SizedBox.expand(
      child: _shadowed(
        tokens,
        radius,
        _glassPanel(tokens, radius: 26, mobile: true),
      ),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, child) {
        if (reduceMotion) return Opacity(opacity: anim.value, child: child);
        final eased = const Cubic(
          0.22,
          1,
          0.36,
          1,
        ).transform(anim.value.clamp(0.0, 1.0));
        return FractionalTranslation(
          translation: Offset(0, eased - 1.0),
          child: child,
        );
      },
      child: panel,
    );
  }

  /// Drop shadow behind the (transparent) glass, clipped to outside the panel
  /// so the dark blur can't bleed up through it. See [GlassPanelShadow].
  Widget _shadowed(SearchTokens tokens, BorderRadius radius, Widget child) {
    return GlassPanelShadow(
      radius: radius,
      shadows: tokens.panelShadow,
      child: child,
    );
  }

  Widget _glassPanel(
    SearchTokens tokens, {
    required double radius,
    required bool mobile,
  }) {
    final content = _PointerGlare(
      color: tokens.glare,
      enabled: !mobile,
      child: Stack(
        children: [
          // showGeneralDialog inserts no Material, so the TextField (and any
          // ink-using descendant) needs one. Transparent → keeps the glass look.
          Material(
            type: MaterialType.transparency,
            child: _column(tokens, mobile),
          ),
          // Specular rim — bright top-left → dim → bright, at 140° (§3.3).
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _RimPainter(
                  radius: radius,
                  edge: tokens.edge,
                  edgeSoft: tokens.edgeSoft,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final dark = Theme.of(context).brightness == Brightness.dark;

    // Real iOS-26 liquid glass via the package. The effect comes from
    // refraction + blur + specular highlights, NOT a tint fill — the package's
    // own default `glassColor` is fully transparent. The earlier code passed
    // `glassColor: tokens.tint` (alpha 0.62), a near-opaque warm fill that
    // buried the glass and read as a flat card. We now feed a very light tint
    // (just enough warmth + text contrast) and let the lens do the work.
    // `premium` quality enables texture capture + chromatic aberration on
    // Impeller (falls back gracefully on Skia/Web).
    final glass = GlassContainer(
      useOwnLayer: true,
      quality: GlassQuality.premium,
      clipBehavior: Clip.antiAlias,
      shape: LiquidRoundedSuperellipse(borderRadius: mobile ? 0 : radius),
      settings: liquidGlassPanelSettings(
        glassFill: tokens.glassFill,
        dark: dark,
      ),
      child: content,
    );

    if (mobile) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
        child: glass,
      );
    }
    return glass;
  }

  Widget _column(SearchTokens tokens, bool mobile) {
    final results = _Results(
      controller: _c,
      scroll: _scroll,
      tokens: tokens,
      rowKeys: _rowKeys,
      onActivateEntry: _activateEntry,
      onApplyRecent: _applyRecent,
      onHoverIndex: _c.setSelected,
    );
    // Absorb taps inside the panel so they don't fall through to the scrim.
    return GestureDetector(
      onTap: () {},
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: mobile ? MainAxisSize.max : MainAxisSize.min,
        children: [
          _field(tokens, mobile),
          _scopes(tokens),
          if (mobile) Expanded(child: results) else Flexible(child: results),
          if (!mobile) _footer(tokens),
        ],
      ),
    );
  }

  // ---- field (§3.4) ----
  Widget _field(SearchTokens tokens, bool mobile) {
    final topPad = mobile
        ? math.max(20.0, MediaQuery.viewPaddingOf(context).top + 12)
        : 18.0;
    return Container(
      padding: EdgeInsets.fromLTRB(20, topPad, 20, 18),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.hairline)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.search, size: 22, color: tokens.inkSoft),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: _text,
              focusNode: _fieldNode,
              autofocus: true,
              textInputAction: TextInputAction.search,
              cursorColor: tokens.ink,
              onChanged: _c.setQuery,
              style: TextStyle(
                fontSize: mobile ? 19 : 20,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.2,
                color: tokens.ink,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                fillColor: Colors.transparent,
                hoverColor: Colors.transparent,
                hintText: context.t('search.placeholder'),
                hintStyle: TextStyle(
                  fontSize: mobile ? 19 : 20,
                  fontWeight: FontWeight.w400,
                  color: tokens.inkFaint,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _EscPill(tokens: tokens, onTap: _close, mobile: mobile),
        ],
      ),
    );
  }

  // ---- scope chips (§3.4) ----
  Widget _scopes(SearchTokens tokens) {
    final chips = <SearchCat?>[null, ...SearchCat.values];
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.hairline)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            for (final cat in chips) ...[
              _ScopeChip(
                tokens: tokens,
                icon: cat == null
                    ? LucideIcons.sparkles
                    : kSearchCatMeta[cat]!.icon,
                label: cat == null
                    ? context.t('search.scope.all')
                    : context.t(kSearchCatMeta[cat]!.labelKey),
                count: cat == null ? null : (_c.counts[cat] ?? 0),
                active: _c.scope == cat,
                onTap: () => _c.setScope(cat),
              ),
              const SizedBox(width: 7),
            ],
          ],
        ),
      ),
    );
  }

  // ---- footer (desktop only, §3.4) ----
  Widget _footer(SearchTokens tokens) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 11, 18, 11),
      decoration: BoxDecoration(
        color: tokens.field,
        border: Border(top: BorderSide(color: tokens.hairline)),
      ),
      child: Row(
        children: [
          // Hints take the free space; if they don't fit (e.g. long labels or
          // untranslated keys) they scroll instead of overflowing the footer.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FootHint(
                    tokens: tokens,
                    caps: const ['↑', '↓'],
                    label: context.t('search.foot.navigate'),
                  ),
                  const SizedBox(width: 16),
                  _FootHint(
                    tokens: tokens,
                    caps: const ['↵'],
                    label: context.t('search.foot.open'),
                  ),
                  const SizedBox(width: 16),
                  _FootHint(
                    tokens: tokens,
                    caps: const ['tab'],
                    label: context.t('search.foot.scope'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          const HexMark(size: 15, color: AppColors.accent),
          const SizedBox(width: 7),
          Text(
            context.t('search.brand'),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: tokens.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}
