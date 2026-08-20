import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality, LiquidRoundedSuperellipse;

import '../../../core/i18n/i18n.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/hive_widgets.dart';
import '../../search/search_tokens.dart';

part 'glass_modal.fields.dart';

/// Phone breakpoint for the sprint modals (matches the app's φ-stepped phone bp
/// used by the search palette).
const double _kPhoneBreakpoint = 610;

/// Opens a Liquid-Glass sprint modal over a dimmed, blurred app — the shared
/// material for Create / Start / Complete / Estimate (mirrors `sprint.css`
/// "LIQUID-GLASS SPRINT MODALS": radius 26, blurred scrim, spring entrance).
///
/// Honours `prefers-reduced-motion`: cross-fade only, no spring/blur ramp.
Future<T?> showGlassModal<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double width = 540,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    useRootNavigator: true,
    transitionDuration: const Duration(milliseconds: 380),
    pageBuilder: (_, _, _) =>
        _GlassModalScaffold(width: width, builder: builder),
    transitionBuilder: (_, _, _, child) => child,
  );
}

/// A Liquid-Glass confirmation dialog — the shared replacement for Material's
/// [AlertDialog]. Renders an amber (or danger-tinted) icon tile, a title and a
/// message on the app's glass material, with Cancel / confirm actions.
///
/// Resolves to `true` when confirmed, `false`/`null` when dismissed.
Future<bool?> showGlassConfirm(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
  IconData confirmIcon = LucideIcons.check,
}) {
  return showGlassModal<bool>(
    context,
    width: 420,
    builder: (modalContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _GlassConfirmHeader(icon: icon, title: title, destructive: destructive),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
          child: Text(
            message,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: AppColors.inkSoft,
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: confirmLabel,
          confirmIcon: confirmIcon,
          confirmColor: destructive ? AppColors.danger : null,
          onConfirm: () => Navigator.of(modalContext).pop(true),
        ),
      ],
    ),
  );
}

/// Header for [showGlassConfirm]: icon tile + title + close button (no
/// subtitle line, unlike [GlassModalHeader]).
class _GlassConfirmHeader extends StatelessWidget {
  const _GlassConfirmHeader({
    required this.icon,
    required this.title,
    required this.destructive,
  });

  final IconData icon;
  final String title;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final tileBg = destructive
        ? AppColors.danger.withValues(alpha: 0.14)
        : AppColors.accentSoft;
    final glyph = destructive ? AppColors.danger : AppColors.accentStrong;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 14, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tileBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: glyph),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: AppTheme.fontBrand,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: context.t('common.cancel'),
            icon: Icon(LucideIcons.x, size: 20, color: AppColors.inkSoft),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

/// Opens a Liquid-Glass bottom sheet — the shared replacement for Material's
/// [showModalBottomSheet]. Renders [builder]'s content on the app's signature
/// glass panel (transparent transport, blurred glassFill, grab handle), riding
/// above the on-screen keyboard. Mirrors the action sheet in
/// `upload_source_sheet.dart`.
///
/// The [builder] should return its own content directly (a `Column`/list); the
/// helper supplies the surface, the grab handle, side insets and `SafeArea`, so
/// content must NOT add its own — see [showUploadSourceSheet] for the original.
Future<T?> showGlassBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool showHandle = true,
  double radius = 24,
  double maxWidth = 560,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (sheetContext) => _GlassBottomSheet(
      radius: radius,
      showHandle: showHandle,
      maxWidth: maxWidth,
      builder: builder,
    ),
  );
}

class _GlassBottomSheet extends StatelessWidget {
  const _GlassBottomSheet({
    required this.radius,
    required this.showHandle,
    required this.maxWidth,
    required this.builder,
  });

  final double radius;
  final bool showHandle;
  final double maxWidth;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final tokens = SearchTokens.of(Theme.of(context).brightness);
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Ride above the keyboard: subscribing rebuilds the sheet as it animates.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final size = MediaQuery.sizeOf(context);
    // Never grow past the space above the keyboard; the body scrolls within.
    final maxH = (size.height - 80 - keyboard).clamp(160.0, size.height);

    final panel = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxH),
      child: GlassPanelShadow(
        radius: BorderRadius.circular(radius),
        shadows: tokens.panelShadow,
        child: GlassContainer(
          useOwnLayer: true,
          quality: GlassQuality.premium,
          clipBehavior: Clip.antiAlias,
          shape: LiquidRoundedSuperellipse(borderRadius: radius),
          settings: liquidGlassPanelSettings(
            glassFill: tokens.glassFill,
            dark: dark,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showHandle) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: tokens.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
                Flexible(child: builder(context)),
              ],
            ),
          ),
        ),
      ),
    );

    // With `isScrollControlled`, the bottom-sheet body stretches to the full
    // screen height, so the `Align` leaves a tall transparent gap above the
    // panel that belongs to the sheet — not the modal barrier. Without an
    // explicit handler, taps in that gap (or the side gutters) fall on the
    // sheet and do nothing instead of dismissing. Catch them here; the panel
    // wraps its own taps so its content stays interactive.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).maybePop(),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(10, 0, 10, 10 + keyboard),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(onTap: () {}, child: panel),
          ),
        ),
      ),
    );
  }
}

/// Width at/above which glass pickers anchor as a dropdown popover (tablet /
/// desktop) instead of sliding up as a bottom sheet (phone). Shared by
/// [showGlassOptions] and callers of [showGlassAnchoredPopover] so the
/// sheet-vs-popover decision stays consistent across field editors.
const double kGlassPopoverBreakpoint = 760;

/// A single choice for [showGlassOptions]: a [value] and the [child] widget that
/// renders it (a status dot, a priority flag, a plain label…).
typedef GlassOption<T> = ({T value, Widget child});

/// Responsive single-choice picker on the glass material — the shared pattern
/// for the issue-detail field pickers (status / priority / type / sprint…).
///
/// On wide screens, when an [anchorRect] (the global rect of the tapped row) is
/// supplied, it opens as an **anchored dropdown popover** beside the field so it
/// reads as an inline editor rather than a detached sheet. On phones (or without
/// an anchor) it slides up via [showGlassBottomSheet]. Resolves to the chosen
/// value, or `null` if dismissed.
Future<T?> showGlassOptions<T>(
  BuildContext context, {
  required String title,
  required List<GlassOption<T>> options,
  Rect? anchorRect,
}) {
  final wide = MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint;
  if (wide && anchorRect != null) {
    return showGlassAnchoredPopover<T>(
      context,
      anchorRect: anchorRect,
      builder: (popoverContext) => ListView(
        padding: const EdgeInsets.symmetric(vertical: 6),
        shrinkWrap: true,
        children: [
          for (final o in options)
            InkWell(
              onTap: () => Navigator.of(popoverContext).pop(o.value),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 11,
                ),
                child: Align(alignment: Alignment.centerLeft, child: o.child),
              ),
            ),
        ],
      ),
    );
  }
  return showGlassBottomSheet<T>(
    context,
    builder: (sheetContext) => _OptionsList<T>(title: title, options: options),
  );
}

/// Opens [builder] as a Liquid-Glass dropdown popover anchored beside
/// [anchorRect] — the wide-screen counterpart to [showGlassBottomSheet] for
/// inline field editors that need richer content than [showGlassOptions]'s flat
/// list (e.g. a searchable people picker). Placement mirrors [showGlassOptions]:
/// below the anchor, flipping above when space is tight and clamped on-screen.
///
/// The popover sizes itself between [minHeight] and [maxHeight]; [builder]'s
/// content should be self-scrolling (a `Column` with a `Flexible` list, or a
/// `ListView`). Callers decide *when* to use this vs. the bottom sheet — it does
/// not branch on width itself. Resolves to the value popped from the route.
Future<T?> showGlassAnchoredPopover<T>(
  BuildContext context, {
  required Rect anchorRect,
  required WidgetBuilder builder,
  double width = 300,
  double minHeight = 140,
  double maxHeight = 460,
}) {
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, _, _) => _AnchoredPanel(
      anchorRect: anchorRect,
      width: width,
      minHeight: minHeight,
      maxHeightCap: maxHeight,
      child: Builder(builder: builder),
    ),
    transitionBuilder: (_, _, _, child) => child,
  );
}

/// Bottom-sheet body for [showGlassOptions] on phones: a title and a tap-to-pick
/// list, sized to its content.
class _OptionsList<T> extends StatelessWidget {
  const _OptionsList({required this.title, required this.options});

  final String title;
  final List<GlassOption<T>> options;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        for (final o in options)
          InkWell(
            onTap: () => Navigator.of(context).pop(o.value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Align(alignment: Alignment.centerLeft, child: o.child),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Wide-screen body for anchored glass popovers ([showGlassOptions] and
/// [showGlassAnchoredPopover]): a glass panel anchored to [anchorRect], placed
/// below the field (flips above when space is tight) and clamped on-screen —
/// mirrors the placement logic of `GlassPopupMenu`. Hosts an arbitrary [child].
class _AnchoredPanel extends StatelessWidget {
  const _AnchoredPanel({
    required this.anchorRect,
    required this.child,
    this.width = 300,
    this.minHeight = 140,
    this.maxHeightCap = 460,
  });

  final Rect anchorRect;
  final Widget child;
  final double width;
  final double minHeight;
  final double maxHeightCap;

  static const double _margin = 12;
  static const double _radius = 20;
  static const double _gap = 6;

  @override
  Widget build(BuildContext context) {
    final tokens = SearchTokens.of(Theme.of(context).brightness);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final anim = ModalRoute.of(context)!.animation!;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final panelWidth = math.min(width, size.width - _margin * 2);
    final double left = anchorRect.left
        .clamp(_margin, math.max(_margin, size.width - panelWidth - _margin))
        .toDouble();
    final belowTop = anchorRect.bottom + _gap;
    final roomBelow = size.height - belowTop - _margin - pad.bottom;
    final roomAbove = anchorRect.top - _gap - _margin - pad.top;
    final placeAbove = roomBelow < 220 && roomAbove > roomBelow;
    final maxHeight = (placeAbove ? roomAbove : roomBelow).clamp(
      minHeight,
      maxHeightCap,
    );
    final top = placeAbove ? null : belowTop;
    final bottom = placeAbove ? (size.height - anchorRect.top + _gap) : null;

    final panel = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: panelWidth, maxHeight: maxHeight),
      child: GlassPanelShadow(
        radius: BorderRadius.circular(_radius),
        shadows: tokens.panelShadow,
        child: GlassContainer(
          useOwnLayer: true,
          quality: GlassQuality.premium,
          clipBehavior: Clip.antiAlias,
          shape: const LiquidRoundedSuperellipse(borderRadius: _radius),
          settings: liquidGlassPanelSettings(
            glassFill: tokens.glassFill,
            dark: dark,
          ),
          child: Stack(
            children: [
              // The panel's own base, under everything it shows.
              //
              // The lens alone is a light wash — 0.42 — which is legible over
              // a page and not over what a dropdown actually lands on: the
              // dark hero card, a coloured chip, an image. Whatever was behind
              // came through at half strength and the ink sat on a mid-tone
              // that changed from row to row. The base tint is the token that
              // exists for this, and it leaves the refraction and the rim,
              // which is where the glass reads from, untouched at the edges.
              Positioned.fill(
                child: IgnorePointer(child: ColoredBox(color: tokens.tint)),
              ),
              Material(type: MaterialType.transparency, child: child),
              // The specular rim: the edge that separates the panel from what
              // it floats over. Every other glass surface in the app draws one
              // — this one never did, so it ended where its shadow did.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: GlassRimPainter(
                      radius: _radius,
                      edge: tokens.edge,
                      edgeSoft: tokens.edgeSoft,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Stack(
      children: [
        // A dropdown is an inline editor, not a modal, so this is a fraction
        // of the palette's dim: enough to settle the page behind the panel,
        // not enough to read as "the rest of the screen is gone".
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: anim,
              builder: (_, _) => ColoredBox(
                color: tokens.popoverScrim.withValues(
                  alpha: tokens.popoverScrim.a * anim.value.clamp(0.0, 1.0),
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
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
                      ? Alignment.bottomLeft
                      : Alignment.topLeft,
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
}

/// A Liquid-Glass date picker — the shared replacement for Material's
/// [showDatePicker]. Renders Material's [CalendarDatePicker] (robust month/year
/// logic) on the app's glass modal, themed with the navy/amber accents, with the
/// chosen day echoed in the header and a Cancel / OK footer.
///
/// Resolves to the picked [DateTime], or `null` if dismissed.
///
/// Pass [onClear] where the field being edited may hold no date at all: the
/// footer then offers a "clear" action that fires it and closes. Without it the
/// picker can only confirm or cancel, as before.
Future<DateTime?> showGlassDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  required String title,
  VoidCallback? onClear,
}) {
  return showGlassModal<DateTime>(
    context,
    width: 360,
    builder: (modalContext) => _GlassDatePicker(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      title: title,
      onClear: onClear,
    ),
  );
}

/// The same calendar, anchored beside the control that opened it instead of
/// centred on a scrim — for inline field editors where a full modal is heavier
/// than the edit it performs (the board's quick-create composer).
///
/// Picking a day commits immediately and closes, the way a dropdown does; there
/// is no OK. [onClear] adds a "clear" row for fields that may hold no date.
///
/// Wide screens only — callers decide, mirroring [showGlassOptions]: on a phone
/// use [showGlassDatePicker], whose sheet-sized modal fits the small screen.
/// Resolves to the picked date, or null when dismissed or cleared.
Future<DateTime?> showGlassDatePopover(
  BuildContext context, {
  required Rect anchorRect,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  required String title,
  VoidCallback? onClear,
}) {
  return showGlassAnchoredPopover<DateTime>(
    context,
    anchorRect: anchorRect,
    width: 330,
    minHeight: 260,
    maxHeight: 460,
    builder: (popoverContext) => _GlassDatePopoverBody(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      title: title,
      onClear: onClear,
    ),
  );
}

/// Themes Material's [CalendarDatePicker] onto the app's glass: no opaque
/// dialog surface of its own, navy selection, amber "today". Shared so the
/// anchored popover and the modal picker render the same calendar.
ThemeData _glassCalendarTheme(BuildContext context) {
  final base = Theme.of(context);
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.navy,
      onPrimary: Colors.white,
      surface: Colors.transparent,
      onSurface: AppColors.ink,
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      todayForegroundColor: WidgetStateProperty.all(AppColors.accentStrong),
      todayBorder: const BorderSide(color: AppColors.accent),
    ),
  );
}

class _GlassDatePopoverBody extends StatelessWidget {
  const _GlassDatePopoverBody({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.title,
    this.onClear,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Theme(
            data: _glassCalendarTheme(context),
            child: SizedBox(
              // The calendar needs a bounded height; the panel scrolls when it
              // has less room than this.
              height: 312,
              child: CalendarDatePicker(
                initialDate: initialDate,
                firstDate: firstDate,
                lastDate: lastDate,
                // A popover commits on pick — no OK button to hunt for.
                onDateChanged: (d) => Navigator.of(context).pop(d),
              ),
            ),
          ),
          if (onClear != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    onClear!();
                    Navigator.of(context).pop();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.inkSoft,
                  ),
                  icon: const Icon(LucideIcons.x, size: 15),
                  label: Text(context.t('common.clear')),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GlassDatePicker extends StatefulWidget {
  const _GlassDatePicker({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.title,
    this.onClear,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;

  /// When set, the footer offers clearing the field the picker is editing.
  final VoidCallback? onClear;

  @override
  State<_GlassDatePicker> createState() => _GlassDatePickerState();
}

class _GlassDatePickerState extends State<_GlassDatePicker> {
  late DateTime _selected = widget.initialDate;

  @override
  Widget build(BuildContext context) {
    // Theme the Material calendar to the app's surface-free, navy/amber palette
    // so it reads on the glass instead of painting its own opaque dialog.
    final themed = _glassCalendarTheme(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.calendar,
          title: widget.title,
          subtitle: MaterialLocalizations.of(context).formatFullDate(_selected),
        ),
        Theme(
          data: themed,
          child: SizedBox(
            height: 340,
            child: CalendarDatePicker(
              initialDate: _selected,
              firstDate: widget.firstDate,
              lastDate: widget.lastDate,
              onDateChanged: (d) => setState(() => _selected = d),
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: MaterialLocalizations.of(context).okButtonLabel,
          onConfirm: () => Navigator.of(context).pop(_selected),
          // Clearing closes without a value, so it rides the footer's left
          // hint slot rather than competing with OK.
          hint: widget.onClear == null
              ? null
              : Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      widget.onClear!();
                      Navigator.of(context).pop();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.inkSoft,
                    ),
                    icon: const Icon(LucideIcons.x, size: 15),
                    label: Text(context.t('common.clear')),
                  ),
                ),
        ),
      ],
    );
  }
}

/// A Liquid-Glass **date-range** picker — the shared replacement for Material's
/// fullscreen [showDateRangePicker], which looks out of place on desktop/tablet.
/// Renders a custom vertically-scrolling month calendar (the layout kept from the
/// phone experience) on the app's compact glass modal, so it reads as a small
/// floating panel on wide screens and a near-full-width sheet on phones.
///
/// [initialRange] pre-selects a range and scrolls it into view; otherwise the
/// today's month is anchored. Resolves to the picked [DateTimeRange], or `null`
/// if dismissed. Selection is inclusive of both endpoints.
Future<DateTimeRange?> showGlassDateRangePicker(
  BuildContext context, {
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialRange,
  required String title,
}) {
  return showGlassModal<DateTimeRange>(
    context,
    width: 400,
    builder: (modalContext) => _GlassDateRangePicker(
      firstDate: DateUtils.dateOnly(firstDate),
      lastDate: DateUtils.dateOnly(lastDate),
      initialRange: initialRange,
      title: title,
    ),
  );
}

class _GlassDateRangePicker extends StatefulWidget {
  const _GlassDateRangePicker({
    required this.firstDate,
    required this.lastDate,
    required this.initialRange,
    required this.title,
  });

  final DateTime firstDate;
  final DateTime lastDate;
  final DateTimeRange? initialRange;
  final String title;

  @override
  State<_GlassDateRangePicker> createState() => _GlassDateRangePickerState();
}

class _GlassDateRangePickerState extends State<_GlassDateRangePicker> {
  DateTime? _start;
  DateTime? _end;
  final _scroll = ScrollController();
  bool _jumped = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialRange != null) {
      _start = DateUtils.dateOnly(widget.initialRange!.start);
      _end = DateUtils.dateOnly(widget.initialRange!.end);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Number of months rendered, from [widget.firstDate]'s month through
  /// [widget.lastDate]'s month (inclusive).
  int get _monthCount =>
      DateUtils.monthDelta(widget.firstDate, widget.lastDate) + 1;

  DateTime _monthAt(int index) =>
      DateUtils.addMonthsToMonthDate(widget.firstDate, index);

  /// Height of month [index] for a given day-[cell] size — a fixed label band
  /// plus one row per week. Summed to compute the initial scroll offset so the
  /// active range (or today) lands in view.
  double _monthHeight(int index, double cell) {
    final m = _monthAt(index);
    final days = DateUtils.getDaysInMonth(m.year, m.month);
    final offset = DateUtils.firstDayOffset(
      m.year,
      m.month,
      MaterialLocalizations.of(context),
    );
    final weeks = ((offset + days) / 7).ceil();
    return _kMonthLabelHeight + weeks * cell;
  }

  void _onTapDay(DateTime day) {
    setState(() {
      // First tap, or a fresh start after a complete range — begin anew.
      if (_start == null || _end != null) {
        _start = day;
        _end = null;
      } else if (day.isBefore(_start!)) {
        // Second tap before the start flips the anchor so start ≤ end.
        _end = _start;
        _start = day;
      } else {
        _end = day;
      }
    });
  }

  String _subtitle(BuildContext context) {
    final l = MaterialLocalizations.of(context);
    if (_start == null) return context.t('issues.time.rangePrompt');
    if (_end == null) {
      return '${l.formatShortDate(_start!)}  ·  ${context.t('issues.time.pickEnd')}';
    }
    return '${l.formatShortDate(_start!)} – ${l.formatShortDate(_end!)}';
  }

  @override
  Widget build(BuildContext context) {
    final l = MaterialLocalizations.of(context);
    // Weekday header labels, ordered from the locale's first weekday.
    final first = l.firstDayOfWeekIndex;
    final weekdayLabels = [
      for (var i = 0; i < 7; i++) l.narrowWeekdays[(first + i) % 7],
    ];
    // Keep the scrolling calendar to a compact band inside the modal; the modal
    // scaffold itself caps overall height, so this only bounds the day grid.
    final gridHeight = math.min(
      MediaQuery.sizeOf(context).height * 0.52,
      408.0,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.calendarRange,
          title: widget.title,
          subtitle: _subtitle(context),
        ),
        // Weekday header row, aligned to the day grid below.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(
            children: [
              for (final label in weekdayLabels)
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(height: 1, color: AppColors.hairline.withValues(alpha: 0.6)),
        // Flexible + a max-height cap: prefers [gridHeight] but shrinks so the
        // header/footer chrome always fits inside short (small-window) modals.
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: gridHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cell = constraints.maxWidth / 7;
                  // One-shot jump so the active range (or today) is on screen.
                  if (!_jumped) {
                    _jumped = true;
                    final anchor = _start ?? DateUtils.dateOnly(DateTime.now());
                    final clamped = anchor.isBefore(widget.firstDate)
                        ? widget.firstDate
                        : (anchor.isAfter(widget.lastDate)
                              ? widget.lastDate
                              : anchor);
                    final anchorIndex = DateUtils.monthDelta(
                      widget.firstDate,
                      clamped,
                    );
                    var offset = 0.0;
                    for (var i = 0; i < anchorIndex; i++) {
                      offset += _monthHeight(i, cell);
                    }
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_scroll.hasClients) {
                        _scroll.jumpTo(
                          offset.clamp(0.0, _scroll.position.maxScrollExtent),
                        );
                      }
                    });
                  }
                  return ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: _monthCount,
                    itemBuilder: (context, index) => _MonthGrid(
                      month: _monthAt(index),
                      cell: cell,
                      firstDate: widget.firstDate,
                      lastDate: widget.lastDate,
                      start: _start,
                      end: _end,
                      onTap: _onTapDay,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: l.okButtonLabel,
          onConfirm: _start == null
              ? null
              : () => Navigator.of(
                  context,
                ).pop(DateTimeRange(start: _start!, end: _end ?? _start!)),
        ),
      ],
    );
  }
}

/// Fixed vertical space each month reserves for its "July 2026" label (label +
/// surrounding padding), used both for layout and for the scroll-offset maths.
const double _kMonthLabelHeight = 44;

/// A single month's day grid inside [_GlassDateRangePicker]. Draws the month
/// label, then a 7-column grid of day cells with the selected range painted as a
/// continuous amber band and navy endpoint discs.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.cell,
    required this.firstDate,
    required this.lastDate,
    required this.start,
    required this.end,
    required this.onTap,
  });

  final DateTime month;
  final double cell;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime? start;
  final DateTime? end;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final l = MaterialLocalizations.of(context);
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final offset = DateUtils.firstDayOffset(month.year, month.month, l);
    final today = DateUtils.dateOnly(DateTime.now());

    // Total cells rounded up to whole weeks, so the grid stays rectangular.
    final cellCount = ((offset + days) / 7).ceil() * 7;
    final cells = <Widget>[];
    for (var i = 0; i < cellCount; i++) {
      final dayNum = i - offset + 1;
      if (dayNum < 1 || dayNum > days) {
        cells.add(SizedBox(width: cell, height: cell));
        continue;
      }
      final date = DateTime(month.year, month.month, dayNum);
      final disabled = date.isBefore(firstDate) || date.isAfter(lastDate);
      // A "real" (multi-day) range is needed before any connecting band shows;
      // a single-day selection just draws its endpoint disc.
      final hasRange = start != null && end != null && start != end;
      final isStart = start != null && date == start;
      final isEnd = end != null && date == end;
      final inRange = hasRange && date.isAfter(start!) && date.isBefore(end!);
      cells.add(
        _DayCell(
          size: cell,
          label: '$dayNum',
          disabled: disabled,
          isToday: date == today,
          isStart: isStart,
          isEnd: isEnd,
          // The band reaches only toward the other endpoint: the start caps its
          // right half, the end its left half, interior days fill fully.
          bandLeft: inRange || (hasRange && isEnd),
          bandRight: inRange || (hasRange && isStart),
          onTap: disabled ? null : () => onTap(date),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _kMonthLabelHeight,
          child: Padding(
            padding: const EdgeInsets.only(left: 2, top: 16, bottom: 8),
            child: Text(
              l.formatMonthYear(month),
              style: const TextStyle(
                fontFamily: AppTheme.fontBrand,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
        for (var row = 0; row < cellCount ~/ 7; row++)
          Row(children: cells.sublist(row * 7, row * 7 + 7)),
      ],
    );
  }
}

/// One day cell: an optional range band (right/left/full depending on where the
/// day sits in the selection) with an optional navy endpoint disc and today ring.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.size,
    required this.label,
    required this.disabled,
    required this.isToday,
    required this.isStart,
    required this.isEnd,
    required this.bandLeft,
    required this.bandRight,
    required this.onTap,
  });

  final double size;
  final String label;
  final bool disabled;
  final bool isToday;
  final bool isStart;
  final bool isEnd;
  final bool bandLeft;
  final bool bandRight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isEndpoint = isStart || isEnd;

    Widget? band;
    if (bandLeft || bandRight) {
      band = Row(
        children: [
          Expanded(
            child: ColoredBox(
              color: bandLeft ? AppColors.accentSoft : Colors.transparent,
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: bandRight ? AppColors.accentSoft : Colors.transparent,
            ),
          ),
        ],
      );
    }

    final Color textColor;
    if (disabled) {
      textColor = AppColors.inkFaint.withValues(alpha: 0.5);
    } else if (isEndpoint) {
      textColor = Colors.white;
    } else if (isToday) {
      textColor = AppColors.accentStrong;
    } else {
      textColor = AppColors.ink;
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (band != null) Positioned.fill(child: band),
            Container(
              width: size - 8,
              height: size - 8,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isEndpoint ? AppColors.navy : null,
                border: isToday && !isEndpoint
                    ? Border.all(color: AppColors.accent, width: 1.5)
                    : null,
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isEndpoint ? FontWeight.w700 : FontWeight.w500,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A `WoltModalSheet.pageContentDecorator` that re-skins the sheet's surface as
/// the app's liquid glass. Pair it with a transparent page `backgroundColor`
/// (and `surfaceTintColor`) so Wolt's underlying Material stops painting a solid
/// fill and this glass panel shows through instead. Wolt keeps owning layout,
/// the top bar, drag and the sticky action bar — only the surface changes.
Widget glassWoltSurface(Widget pageContent) {
  return Builder(
    builder: (context) {
      final tokens = SearchTokens.of(Theme.of(context).brightness);
      final dark = Theme.of(context).brightness == Brightness.dark;
      return GlassPanelShadow(
        radius: BorderRadius.circular(26),
        shadows: tokens.panelShadow,
        child: GlassContainer(
          useOwnLayer: true,
          quality: GlassQuality.premium,
          clipBehavior: Clip.antiAlias,
          shape: const LiquidRoundedSuperellipse(borderRadius: 26),
          settings: liquidGlassPanelSettings(
            glassFill: tokens.glassFill,
            dark: dark,
          ),
          // Large editing sheets carry dense content over the busy app behind,
          // so float it on a *thick* near-opaque warm-canvas wash (iOS "thick
          // material") for legibility — the thin `glassFill` alone leaves text
          // muddy here. The glass rim, soft translucency and floating shadow
          // keep the liquid-glass identity; small popovers keep the thin fill.
          child: ColoredBox(
            color: AppColors.canvas.withValues(alpha: dark ? 0.84 : 0.88),
            child: pageContent,
          ),
        ),
      );
    },
  );
}

class _GlassModalScaffold extends StatelessWidget {
  const _GlassModalScaffold({required this.width, required this.builder});

  final double width;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // The on-screen keyboard's height. Subscribing rebuilds the modal as the
    // keyboard animates in/out so the panel rides above it and its scrollable
    // body can reveal the focused field.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final mobile = size.width < _kPhoneBreakpoint;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final tokens = SearchTokens.of(Theme.of(context).brightness);
    final anim = ModalRoute.of(context)!.animation!;
    final maxW = mobile ? size.width - 32 : width;
    // Cap the panel to the space left above the keyboard so it never hides
    // behind it; the body scrolls within whatever height remains.
    final maxH = (size.height - (mobile ? 120 : 96) - keyboard).clamp(
      160.0,
      size.height,
    );

    final panel = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
      child: GlassPanelShadow(
        radius: BorderRadius.circular(26),
        shadows: tokens.panelShadow,
        child: GlassContainer(
          useOwnLayer: true,
          quality: GlassQuality.premium,
          clipBehavior: Clip.antiAlias,
          shape: const LiquidRoundedSuperellipse(borderRadius: 26),
          settings: liquidGlassPanelSettings(
            glassFill: tokens.glassFill,
            dark: Theme.of(context).brightness == Brightness.dark,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: builder(context),
          ),
        ),
      ),
    );

    return Stack(
      children: [
        // Scrim: dim + blur the app behind.
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
                onTap: () => Navigator.of(context).maybePop(),
                child: scrim,
              ),
            );
          },
        ),
        Positioned.fill(
          child: SafeArea(
            // Shrink the centring box by the keyboard height so the panel
            // re-centres in the visible area above it instead of being clipped.
            child: Padding(
              padding: EdgeInsets.only(bottom: keyboard),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: AnimatedBuilder(
                    animation: anim,
                    builder: (_, child) {
                      if (reduceMotion) {
                        return Opacity(opacity: anim.value, child: child);
                      }
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
                            child: child,
                          ),
                        ),
                      );
                    },
                    // Absorb taps so they don't fall through to the scrim.
                    child: GestureDetector(
                      onTap: () {},
                      behavior: HitTestBehavior.opaque,
                      child: panel,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Semantic flavours for [showGlassToast]. Each kind carries its default
/// Lucide glyph and tint; pass a custom [showGlassToast.icon] to override the
/// glyph while keeping the kind's tint.
enum GlassToastKind {
  /// Neutral notice (default) — amber accent, info glyph.
  info(LucideIcons.info, AppColors.accentStrong),

  /// Positive confirmation ("saved", "copied", "sent").
  success(LucideIcons.circleCheck, AppColors.success),

  /// Recoverable problem or missing input the user should act on.
  warning(LucideIcons.triangleAlert, AppColors.warning),

  /// Failed operation (API errors, rejected uploads).
  error(LucideIcons.circleAlert, AppColors.danger);

  const GlassToastKind(this.icon, this.tint);

  final IconData icon;
  final Color tint;
}

/// The single live toast — showing a new one replaces it instead of stacking.
OverlayEntry? _activeGlassToast;

/// Handle returned by [showGlassToast] to programmatically dismiss the toast
/// (e.g. from a custom [showGlassToast.trailing] widget or once a background
/// operation finishes). Safe to call at any time — closing an already
/// dismissed/replaced toast is a no-op.
class GlassToastController {
  _GlassToastState? _state;

  /// Whether this toast is still on screen (and not already animating out).
  bool get isShowing => _state != null && !_state!._closing;

  /// Dismisses the toast with its exit animation. No-op if already gone.
  void close() => _state?._close();
}

/// Shows a transient Liquid-Glass toast pill — the app-wide replacement for
/// Material's [SnackBar]. Inserted into the ROOT overlay, so it renders above
/// every open glass modal/sheet and its blurred scrim (a Scaffold [SnackBar]
/// would be buried underneath) and rides above the on-screen keyboard.
///
/// It anchors bottom-centre on compact layouts (thumb's reach, the phone
/// convention) and top-centre on every wider one: on a desktop-sized window the
/// bottom edge is far outside where the user is looking and the toast goes
/// unnoticed there. Either way it clears the chrome the mounted shell published
/// to [ShellInsets] — the floating nav, the top bar — and the keyboard.
///
/// [kind] picks the semantic glyph + tint ([GlassToastKind.info] by default);
/// [icon] overrides the glyph only. [actionLabel]/[onAction] add a tappable
/// action chip (e.g. "Undo", "Retry"); [trailing] instead mounts an arbitrary
/// widget (e.g. an [IconButton]) in the action slot — its handlers may freely
/// call [showGlassToast] again or [GlassToastController.close]. With either
/// the toast stays longer and accepts taps, and a tap anywhere on the pill
/// dismisses it (an interactive toast covers what is under it, so there has to
/// be a way past it that is not "do the thing"); without it never intercepts
/// input. Errors and actionable toasts default to 5 s, everything else to
/// 3.2 s; only one toast is visible at a time (a new one replaces the
/// current). The returned [GlassToastController] dismisses it early.
///
/// [brightness] pins the pill's material to a room instead of to the app.
/// Leave it null — every ordinary toast should follow the app theme. It exists
/// for the one caller whose *own* surface does not: a screen that is dark in
/// both app themes (the attachment viewer) raises its toast into the ROOT
/// overlay, above its own route, so the toast's context sits outside whatever
/// `Theme` that screen installed and resolves light glass onto a near-black
/// stage. Passing `Brightness.dark` there is what keeps the confirmation as
/// legible as the surface that asked for it.
GlassToastController showGlassToast(
  BuildContext context,
  String message, {
  GlassToastKind kind = GlassToastKind.info,
  IconData? icon,
  Duration? duration,
  String? actionLabel,
  VoidCallback? onAction,
  Widget? trailing,
  Brightness? brightness,
}) => showGlassToastIn(
  Overlay.of(context, rootOverlay: true),
  message,
  kind: kind,
  icon: icon,
  duration: duration,
  actionLabel: actionLabel,
  onAction: onAction,
  trailing: trailing,
  brightness: brightness,
);

/// The same toast, raised into an overlay the caller already holds.
///
/// For app-level callers that have no widget of their own — a bloc listener, a
/// platform callback. All they have is the root navigator, and its own context
/// sits *above* the overlay that navigator owns, so [Overlay.of] looks upwards
/// and finds nothing at all. `navigatorKey.currentState?.overlay` is that
/// overlay; pass it here.
///
/// Same pill and same rules as [showGlassToast], including tap-to-dismiss on
/// the interactive variants.
GlassToastController showGlassToastIn(
  OverlayState overlay,
  String message, {
  GlassToastKind kind = GlassToastKind.info,
  IconData? icon,
  Duration? duration,
  String? actionLabel,
  VoidCallback? onAction,
  Widget? trailing,
  Brightness? brightness,
}) {
  assert(
    trailing == null || actionLabel == null,
    'Pass either actionLabel/onAction or a custom trailing widget, not both.',
  );
  if (_activeGlassToast?.mounted ?? false) _activeGlassToast!.remove();
  _activeGlassToast = null;
  final hasAction = actionLabel != null && onAction != null;
  final interactive = hasAction || trailing != null;
  final effectiveDuration =
      duration ??
      (interactive || kind == GlassToastKind.error
          ? const Duration(milliseconds: 5000)
          : const Duration(milliseconds: 3200));
  final controller = GlassToastController();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _GlassToast(
      controller: controller,
      message: message,
      icon: icon ?? kind.icon,
      tint: kind.tint,
      duration: effectiveDuration,
      actionLabel: hasAction ? actionLabel : null,
      onAction: hasAction ? onAction : null,
      trailing: trailing,
      brightness: brightness,
      onDone: () {
        // A replacement toast (possibly shown from within our own action
        // handler) may already have removed this entry — never remove twice.
        if (entry.mounted) entry.remove();
        if (identical(_activeGlassToast, entry)) _activeGlassToast = null;
      },
    ),
  );
  _activeGlassToast = entry;
  overlay.insert(entry);
  return controller;
}

/// Error-kind shorthand for the ubiquitous `context.t(failure.message)` case.
void showGlassErrorToast(BuildContext context, String message) =>
    showGlassToast(context, message, kind: GlassToastKind.error);

class _GlassToast extends StatefulWidget {
  const _GlassToast({
    required this.controller,
    required this.message,
    required this.icon,
    required this.tint,
    required this.duration,
    required this.onDone,
    this.actionLabel,
    this.onAction,
    this.trailing,
    this.brightness,
  });

  final GlassToastController controller;
  final String message;
  final IconData icon;
  final Color tint;
  final Duration duration;
  final VoidCallback onDone;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  /// The room this pill is lit for. Null (the default) follows the ambient
  /// [Theme] — see [showGlassToast.brightness] for the one caller that doesn't.
  final Brightness? brightness;

  @override
  State<_GlassToast> createState() => _GlassToastState();
}

class _GlassToastState extends State<_GlassToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  Timer? _dismissTimer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
    _controller.forward();
    _dismissTimer = Timer(widget.duration, _close);
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    _dismissTimer?.cancel();
    await _controller.reverse();
    if (mounted) widget.onDone();
  }

  void _handleAction() {
    widget.onAction?.call();
    _close();
  }

  @override
  void dispose() {
    if (identical(widget.controller._state, this)) {
      widget.controller._state = null;
    }
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Every colour on the pill comes off this one brightness — the glass fill
    // *and* the ink that sits on it. Resolving those two from different places
    // is exactly how a pill ends up dark with dark text on it.
    final brightness = widget.brightness ?? Theme.of(context).brightness;
    final tokens = SearchTokens.of(brightness);
    final dark = brightness == Brightness.dark;
    // On anything wider than a phone the bottom edge of the window is nowhere
    // near where the user is looking, so the toast drops in from the top
    // instead of surfacing in a corner nobody watches. Compact keeps the phone
    // convention: bottom, in thumb's reach, riding above the keyboard so
    // field-validation notices stay visible.
    final atTop = !context.isCompact;
    return ValueListenableBuilder<double>(
      // Clears whatever chrome the mounted shell put on that edge — the wide
      // top bar, the floating nav — and hugs the edge itself where there is
      // none: an immersive page, or the screens with no shell at all (auth,
      // server picker), where this stays 0.
      valueListenable: atTop ? ShellInsets.top : ShellInsets.bottom,
      builder: (context, shellInset, child) {
        // Both system insets come from the overlay's own MediaQuery: the
        // status bar up top, and below either the safe area or — with the
        // keyboard up, which lifts the nav with it — the keyboard.
        final padding = MediaQuery.paddingOf(context);
        return Positioned(
          left: 16,
          right: 16,
          // The top bar sits *below* the status bar, so its footprint stacks
          // on that inset.
          top: atTop ? padding.top + shellInset + 16 : null,
          // The floating nav, in contrast, hovers *over* the safe area rather
          // than above it — its published footprint is measured from the
          // window edge and already spans that inset. Stacking the two would
          // leave a home-indicator-sized hole between toast and nav, so
          // whichever reaches higher wins. The keyboard lifts both.
          bottom: atTop
              ? null
              : math.max(shellInset, padding.bottom) +
                    MediaQuery.viewInsetsOf(context).bottom +
                    16,
          child: child!,
        );
      },
      child: IgnorePointer(
        // Without an action the toast is purely informational and must never
        // swallow taps meant for the UI underneath it.
        ignoring: widget.actionLabel == null && widget.trailing == null,
        child: FadeTransition(
          opacity: CurvedAnimation(
            parent: _controller,
            curve: Curves.easeOutCubic,
          ),
          child: SlideTransition(
            // Slide in from whichever edge it is anchored to.
            position:
                Tween<Offset>(
                  begin: Offset(0, atTop ? -0.25 : 0.25),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: _controller,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: Center(
              // Tap the pill to send it away. Only reachable when it is
              // interactive in the first place — an informational toast ignores
              // pointers entirely — and that is exactly the case that needs it:
              // an action chip keeps the pill hit-testable for its whole
              // duration, and on a window narrower than the compact breakpoint
              // it hangs from the *bottom* edge, over the primary button of
              // whatever is underneath. Without this, the only way out of a
              // long actionable toast is to do the thing it offers. The
              // action's own InkWell sits deeper in the tree, so it wins the
              // gesture arena and a tap on the label still acts.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: Material(
                  color: Colors.transparent,
                  shadowColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: GlassPanelShadow(
                      radius: BorderRadius.circular(16),
                      shadows: tokens.panelShadow,
                      child: GlassContainer(
                        useOwnLayer: true,
                        quality: GlassQuality.premium,
                        clipBehavior: Clip.antiAlias,
                        shape: const LiquidRoundedSuperellipse(
                          borderRadius: 16,
                        ),
                        settings: liquidGlassPanelSettings(
                          glassFill: tokens.glassFill,
                          dark: dark,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(widget.icon, size: 16, color: widget.tint),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  widget.message,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    height: 1.35,
                                    // The glass tokens', not `AppColors.ink`:
                                    // that one reads a global written from the
                                    // *app* theme, which no [brightness] here
                                    // could ever override.
                                    color: tokens.ink,
                                  ),
                                ),
                              ),
                              if (widget.trailing != null) ...[
                                const SizedBox(width: 12),
                                widget.trailing!,
                              ],
                              if (widget.actionLabel != null) ...[
                                const SizedBox(width: 12),
                                InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: _handleAction,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    child: Text(
                                      widget.actionLabel!,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.accentStrong,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
