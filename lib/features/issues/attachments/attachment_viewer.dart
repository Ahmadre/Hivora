import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart' show BlurHashImage;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_image.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../sprint/modals/glass_modal.dart'
    show GlassToastKind, showGlassToast;
import 'attachment_kind.dart';

part 'attachment_viewer.pages.dart';

/// One entry shown in the viewer. [url] is the authenticated API download path
/// used to fetch the content for inline previews (images, PDFs, text); types we
/// can't preview render a type card instead.
class ViewerItem {
  const ViewerItem({
    required this.id,
    required this.name,
    required this.kind,
    required this.size,
    this.url,
    this.thumbnailUrl,
    this.blurHash,
    this.mime,
    this.subtitle,
  });

  final String id;
  final String name;
  final String kind;
  final int size;

  /// API path of the attachment's bytes. Null disables every inline preview —
  /// the stage falls back to the type card.
  final String? url;

  /// API path of the small server-side preview. Shown — sharp, at the right
  /// aspect ratio — while the full-resolution bytes are still downloading.
  final String? thumbnailUrl;

  /// BlurHash of the picture: what fills the stage in the very first frame,
  /// before either the thumbnail or the original has been requested.
  final String? blurHash;

  final String? mime;
  final String? subtitle;

  /// Which renderer this item gets on the stage.
  AttachmentPreviewKind get preview => url == null
      ? AttachmentPreviewKind.none
      : previewKindFor(kind: kind, name: name, size: size, mime: mime);
}

/// Opens the full-screen attachment viewer, paging across [items] from
/// [initialIndex].
///
/// Full-bleed on every platform, with the chrome floating over the content:
/// pinch / wheel / ⌘-+ zoom on images and PDFs, a text viewer for everything
/// text-shaped, ←/→ (or swipe, or the filmstrip) to move between files, Esc or
/// swipe-down to leave.
Future<void> showAttachmentViewer(
  BuildContext context, {
  required List<ViewerItem> items,
  required int initialIndex,
  required Future<void> Function(ViewerItem item) onDownload,
}) {
  if (items.isEmpty) return Future<void>.value();
  return showGeneralDialog<void>(
    context: context,
    // The viewer covers the screen; there is no barrier left to tap. Esc, the
    // close button, Android back and swipe-down all dismiss it.
    barrierDismissible: false,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    useRootNavigator: true,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, _, _) => _ViewerScaffold(
      items: items,
      initialIndex: initialIndex.clamp(0, items.length - 1),
      onDownload: onDownload,
    ),
    transitionBuilder: (_, _, _, child) => child,
  );
}

/// Zoom range and per-click step of the stage, per renderer. Images earn a deep
/// range (inspect a screenshot pixel by pixel); text zooms the *type size*, so
/// it needs to go below 100 % as well.
({double min, double max, double step}) _zoomRange(AttachmentPreviewKind kind) {
  return switch (kind) {
    AttachmentPreviewKind.image => (min: 1, max: 8, step: 1.5),
    AttachmentPreviewKind.pdf => (min: 1, max: 5, step: 1.4),
    AttachmentPreviewKind.text ||
    AttachmentPreviewKind.maybeText => (min: 0.7, max: 3, step: 1.15),
    AttachmentPreviewKind.none => (min: 1, max: 1, step: 1),
  };
}

class _ViewerScaffold extends StatefulWidget {
  const _ViewerScaffold({
    required this.items,
    required this.initialIndex,
    required this.onDownload,
  });

  final List<ViewerItem> items;
  final int initialIndex;
  final Future<void> Function(ViewerItem item) onDownload;

  @override
  State<_ViewerScaffold> createState() => _ViewerScaffoldState();
}

class _ViewerScaffoldState extends State<_ViewerScaffold>
    with SingleTickerProviderStateMixin {
  static const double _stripExtent = 54;
  static const double _stripGap = 8;

  late int _index = widget.initialIndex;
  late final PageController _page = PageController(initialPage: _index);
  final _focus = FocusNode(debugLabel: 'attachment-viewer');
  final _strip = ScrollController();

  /// Zoom of the active page. Owned here (the toolbar and the keyboard drive
  /// it) but written back by the pages themselves, so pinch, wheel and the
  /// buttons all end up on the same number.
  final ValueNotifier<double> _zoom = ValueNotifier<double>(1);

  /// Derived from [_zoom], but only flips when the threshold is crossed — the
  /// pager physics must not rebuild on every frame of a pinch.
  final ValueNotifier<bool> _zoomedIn = ValueNotifier<bool>(false);

  /// Swipe-to-dismiss offset of the whole stage.
  final ValueNotifier<Offset> _drag = ValueNotifier<Offset>(Offset.zero);
  late final AnimationController _snap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final CurvedAnimation _snapCurve = CurvedAnimation(
    parent: _snap,
    curve: Curves.easeOutCubic,
  );

  /// Where the snap-back animation started. Read by [_snap]'s one listener, so
  /// a long session of half-drags doesn't pile up animations on the controller.
  Tween<Offset>? _snapFrom;

  /// Chrome (bars, arrows, filmstrip) hides on tap so the content owns the
  /// screen — the way every photo viewer behaves.
  bool _chrome = true;

  // Text viewer preferences, sticky across files for as long as the viewer is
  // open.
  bool _wrapText = true;
  bool _lineNumbers = true;

  /// Text of the file on screen, once it has loaded — what "copy" copies, and
  /// what tells the toolbar that a [AttachmentPreviewKind.maybeText] file did
  /// turn out to be readable.
  String? _text;
  String? _textId;

  ViewerItem get _current => widget.items[_index];

  bool get _multi => widget.items.length > 1;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(_onZoom);
    _snap.addListener(() {
      final from = _snapFrom;
      if (from != null) _drag.value = from.evaluate(_snapCurve);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      _revealInStrip(_index);
    });
  }

  @override
  void dispose() {
    _zoom.removeListener(_onZoom);
    _zoom.dispose();
    _zoomedIn.dispose();
    _drag.dispose();
    _snapCurve.dispose();
    _snap.dispose();
    _page.dispose();
    _strip.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onZoom() {
    final zoomed = _zoom.value > 1.01;
    if (zoomed != _zoomedIn.value) _zoomedIn.value = zoomed;
  }

  // ── Paging ────────────────────────────────────────────────────────────────
  void _go(int i) {
    if (i < 0 || i >= widget.items.length || i == _index) return;
    _page.animateToPage(
      i,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPageChanged(int i) {
    if (i == _index) return;
    setState(() {
      _index = i;
      _text = null;
      _textId = null;
    });
    // Every file starts at its natural size; carrying a 4× zoom onto the next
    // picture would drop the user into a random crop of it.
    _zoom.value = 1;
    _revealInStrip(i);
  }

  /// Keeps the current filmstrip entry on screen. Entries have a fixed extent,
  /// so the target offset is arithmetic — no keys, no layout pass.
  void _revealInStrip(int i) {
    if (!_strip.hasClients || !_multi) return;
    final viewport = _strip.position.viewportDimension;
    final target =
        (i * (_stripExtent + _stripGap)) -
        (viewport - _stripExtent) / 2 +
        _stripGap;
    _strip.animateTo(
      target.clamp(0.0, math.max(0.0, _strip.position.maxScrollExtent)),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  // ── Zoom ──────────────────────────────────────────────────────────────────
  void _zoomBy(double factor) {
    final range = _zoomRange(_activeRenderer);
    if (range.max <= range.min) return;
    _zoom.value = (_zoom.value * factor).clamp(range.min, range.max);
    _showChrome();
  }

  void _resetZoom() {
    _zoom.value = 1;
    _showChrome();
  }

  /// What the stage is actually rendering right now — which is what the
  /// toolbar and the keyboard shortcuts must act on. A text file only counts as
  /// a text stage once its bytes have arrived *and* turned out to be readable;
  /// until then (and for a file that turned out to be binary) there is nothing
  /// to zoom, wrap or copy.
  AttachmentPreviewKind get _activeRenderer {
    final preview = _current.preview;
    if (preview == AttachmentPreviewKind.text ||
        preview == AttachmentPreviewKind.maybeText) {
      return _textId == _current.id && _text != null
          ? AttachmentPreviewKind.text
          : AttachmentPreviewKind.none;
    }
    return preview;
  }

  // ── Dismiss ───────────────────────────────────────────────────────────────
  void _close() => Navigator.of(context).maybePop();

  void _onDismissDrag(Offset delta) {
    _snap.stop();
    _drag.value += delta;
  }

  void _onDismissEnd(Velocity velocity) {
    final dy = _drag.value.dy;
    if (dy.abs() > 120 || velocity.pixelsPerSecond.dy.abs() > 850) {
      _close();
      return;
    }
    _snapFrom = Tween<Offset>(begin: _drag.value, end: Offset.zero);
    _snap.forward(from: 0);
  }

  /// 0 → resting, 1 → far enough that letting go dismisses.
  double _dismissProgress(Offset drag) => (drag.dy.abs() / 240).clamp(0.0, 1.0);

  // ── Chrome ────────────────────────────────────────────────────────────────
  void _toggleChrome() => setState(() => _chrome = !_chrome);

  void _showChrome() {
    if (!_chrome) setState(() => _chrome = true);
  }

  // ── Keyboard ──────────────────────────────────────────────────────────────
  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.pageDown) {
      _go(_index + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.pageUp) {
      _go(_index - 1);
      return KeyEventResult.handled;
    }
    // ⌘/Ctrl +/-/0 like every document viewer — and the bare keys too, because
    // on the web the browser eats the modified ones for its own page zoom.
    final range = _zoomRange(_activeRenderer);
    if (range.max <= range.min) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      _zoomBy(range.step);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _zoomBy(1 / range.step);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      _resetZoom();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Text actions ──────────────────────────────────────────────────────────
  void _onTextLoaded(String id, String? text) {
    if (!mounted || id != _current.id) return;
    if (_textId == id && _text == text) return;
    setState(() {
      _textId = id;
      _text = text;
    });
  }

  Future<void> _copyText() async {
    final text = _text;
    if (text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showGlassToast(
      context,
      context.t('issues.attachments.viewer.copied'),
      kind: GlassToastKind.success,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final anim = ModalRoute.of(context)!.animation!;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      // A route from showGeneralDialog has no Material of its own, and text
      // without one falls back to the framework's error style.
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Backdrop. Deliberately dark in both themes: pictures and PDF pages
            // read against a dark surround, and the text view brings its own
            // theme-coloured "paper" so it stays legible either way.
            ValueListenableBuilder<Offset>(
              valueListenable: _drag,
              builder: (context, drag, _) => AnimatedBuilder(
                animation: anim,
                builder: (context, _) => ColoredBox(
                  color:
                      (dark ? const Color(0xFF07060E) : const Color(0xFF14122A))
                          .withValues(
                            alpha:
                                (dark ? 0.97 : 0.94) *
                                anim.value.clamp(0.0, 1.0) *
                                (1 - 0.5 * _dismissProgress(drag)),
                          ),
                ),
              ),
            ),
            // Stage.
            AnimatedBuilder(
              animation: anim,
              builder: (context, child) {
                final t = anim.value.clamp(0.0, 1.0);
                if (reduceMotion) return Opacity(opacity: t, child: child);
                final curved = Curves.easeOutCubic.transform(t);
                return Opacity(
                  opacity: (t / 0.6).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.97 + 0.03 * curved,
                    child: child,
                  ),
                );
              },
              child: ValueListenableBuilder<Offset>(
                valueListenable: _drag,
                builder: (context, drag, child) {
                  final p = _dismissProgress(drag);
                  return Transform.translate(
                    offset: drag,
                    child: Transform.scale(scale: 1 - 0.08 * p, child: child),
                  );
                },
                child: _stage(),
              ),
            ),
            // Chrome — fades out with the dismiss drag so the content is alone on
            // screen while it follows the finger.
            ValueListenableBuilder<Offset>(
              valueListenable: _drag,
              builder: (context, drag, child) => IgnorePointer(
                ignoring: !_chrome || drag != Offset.zero,
                child: AnimatedOpacity(
                  opacity: _chrome ? 1 - _dismissProgress(drag) : 0,
                  duration: Duration(milliseconds: _chrome ? 160 : 120),
                  curve: Curves.easeOut,
                  child: child,
                ),
              ),
              child: FadeTransition(opacity: anim, child: _chromeLayer()),
            ),
          ],
        ),
      ),
    );
  }

  /// How much room the floating chrome takes at the top and bottom. Scrollable
  /// stages (text, PDF) pad by it so their first and last lines don't sit under
  /// a glass bar; picture stages stay full-bleed and let the bars overlap.
  EdgeInsets get _chromeInsets {
    final safe = MediaQuery.paddingOf(context);
    return EdgeInsets.only(
      top: safe.top + 68,
      bottom: safe.bottom + (_multi ? 148 : 76),
    );
  }

  Widget _stage() {
    final insets = _chromeInsets;
    return ValueListenableBuilder<bool>(
      valueListenable: _zoomedIn,
      builder: (context, zoomed, _) => PageView.builder(
        controller: _page,
        // A zoomed picture owns its horizontal drags — panning inside it must
        // not flip to the next file.
        physics: _multi && !zoomed
            ? const BouncingScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        onPageChanged: _onPageChanged,
        itemCount: widget.items.length,
        itemBuilder: (context, i) => _StagePage(
          item: widget.items[i],
          active: i == _index,
          zoom: _zoom,
          insets: insets,
          wrapText: _wrapText,
          lineNumbers: _lineNumbers,
          onTap: _toggleChrome,
          onTextLoaded: _onTextLoaded,
          onDismissDrag: _onDismissDrag,
          onDismissEnd: _onDismissEnd,
        ),
      ),
    );
  }

  Widget _chromeLayer() {
    final cur = _current;
    final phone = MediaQuery.sizeOf(context).width < 610;
    return Stack(
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                phone ? 10 : 18,
                10,
                phone ? 10 : 18,
                0,
              ),
              child: _absorbTaps(_topBar(cur, phone)),
            ),
          ),
        ),
        if (_multi) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.only(left: phone ? 8 : 18),
                child: _absorbTaps(
                  _NavButton(
                    icon: LucideIcons.chevronLeft,
                    tooltip: context.t('issues.attachments.viewer.previous'),
                    enabled: _index > 0,
                    onTap: () => _go(_index - 1),
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.only(right: phone ? 8 : 18),
                child: _absorbTaps(
                  _NavButton(
                    icon: LucideIcons.chevronRight,
                    tooltip: context.t('issues.attachments.viewer.next'),
                    enabled: _index < widget.items.length - 1,
                    onTap: () => _go(_index + 1),
                  ),
                ),
              ),
            ),
          ),
        ],
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(10, 0, 10, phone ? 10 : 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _absorbTaps(_toolbar(phone)),
                  if (_multi) ...[
                    const SizedBox(height: 10),
                    _absorbTaps(_filmstrip()),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Chrome must not fall through to the stage: a tap on the empty part of a
  /// bar would otherwise hide the very bar the user is aiming at.
  Widget _absorbTaps(Widget child) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () {},
    child: child,
  );

  Widget _topBar(ViewerItem cur, bool phone) {
    return GlassFloatingSurface(
      radius: 20,
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Row(
          children: [
            _IconAction(
              icon: LucideIcons.x,
              tooltip: context.t('issues.attachments.viewer.close'),
              onTap: _close,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    cur.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    cur.subtitle ?? formatBytes(cur.size),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
            if (_multi && !phone) ...[
              const SizedBox(width: 10),
              _Counter(label: '${_index + 1} / ${widget.items.length}'),
            ],
            const SizedBox(width: 8),
            _IconAction(
              icon: LucideIcons.download,
              tooltip: context.t('issues.attachments.download'),
              onTap: () => widget.onDownload(cur),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbar(bool phone) {
    final renderer = _activeRenderer;
    final range = _zoomRange(renderer);
    final isText = renderer == AttachmentPreviewKind.text;
    if (range.max <= range.min && !isText) return const SizedBox.shrink();

    return GlassFloatingSurface(
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
        child: ValueListenableBuilder<double>(
          valueListenable: _zoom,
          builder: (context, zoom, _) {
            final t = context.t;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _IconAction(
                  icon: LucideIcons.minus,
                  tooltip: t('issues.attachments.viewer.zoomOut'),
                  enabled: zoom > range.min + 0.001,
                  onTap: () => _zoomBy(1 / range.step),
                ),
                SizedBox(
                  width: 58,
                  child: Text(
                    '${(zoom * 100).round()}%',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
                _IconAction(
                  icon: LucideIcons.plus,
                  tooltip: t('issues.attachments.viewer.zoomIn'),
                  enabled: zoom < range.max - 0.001,
                  onTap: () => _zoomBy(range.step),
                ),
                _IconAction(
                  icon: LucideIcons.maximize,
                  tooltip: t('issues.attachments.viewer.resetZoom'),
                  enabled: (zoom - 1).abs() > 0.001,
                  onTap: _resetZoom,
                ),
                if (isText) ...[
                  _Divider(),
                  _IconAction(
                    icon: LucideIcons.wrapText,
                    tooltip: t('issues.attachments.viewer.wrap'),
                    active: _wrapText,
                    onTap: () => setState(() => _wrapText = !_wrapText),
                  ),
                  if (!phone)
                    _IconAction(
                      icon: LucideIcons.listOrdered,
                      tooltip: t('issues.attachments.viewer.lineNumbers'),
                      active: _lineNumbers,
                      onTap: () => setState(() => _lineNumbers = !_lineNumbers),
                    ),
                  _IconAction(
                    icon: LucideIcons.copy,
                    tooltip: t('issues.attachments.viewer.copy'),
                    enabled: (_text?.isNotEmpty ?? false),
                    onTap: _copyText,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _filmstrip() {
    return GlassFloatingSurface(
      radius: 20,
      child: SizedBox(
        height: _stripExtent + 14,
        child: ListView.separated(
          controller: _strip,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
          itemCount: widget.items.length,
          separatorBuilder: (_, _) => const SizedBox(width: _stripGap),
          itemBuilder: (context, i) => _StripThumb(
            item: widget.items[i],
            extent: _stripExtent,
            selected: i == _index,
            onTap: () => _go(i),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════ Chrome pieces ═══════════════════════════════

class _Counter extends StatelessWidget {
  const _Counter({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.canvas2.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTheme.fontMono,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: AppColors.inkSoft,
        ),
      ),
    );
  }
}

/// A square glass-bar button. [active] paints the accent state used by the
/// text viewer's toggles; [enabled] dims and disables it.
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool enabled;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? AppColors.inkFaint
        : active
        ? AppColors.accentInk
        : AppColors.inkSoft;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: Material(
          // The token carries its own opacity — a faint wash on dark, an
          // opaque cream on light. Overriding the alpha turned the dark
          // variant into near-solid amber, which swallowed the glyph on it.
          color: active ? AppColors.accentSoft : Colors.transparent,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: active ? AppColors.accentLine : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(11),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: enabled ? onTap : null,
            child: SizedBox(
              width: 38,
              height: 38,
              child: Icon(icon, size: 17, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 20,
    margin: const EdgeInsets.symmetric(horizontal: 5),
    color: AppColors.hairline,
  );
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: enabled ? 1 : 0,
      duration: const Duration(milliseconds: 140),
      child: IgnorePointer(
        ignoring: !enabled,
        child: Tooltip(
          message: tooltip,
          child: Semantics(
            button: true,
            label: tooltip,
            child: GlassFloatingSurface(
              radius: 24,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(icon, size: 22, color: AppColors.ink),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One entry of the bottom filmstrip: the picture's thumbnail, or the file
/// type's glyph for everything else.
class _StripThumb extends StatelessWidget {
  const _StripThumb({
    required this.item,
    required this.extent,
    required this.selected,
    required this.onTap,
  });

  final ViewerItem item;
  final double extent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final km = kindMeta(item.kind);
    final isImage = item.preview == AttachmentPreviewKind.image;
    return Tooltip(
      message: item.name,
      child: Semantics(
        button: true,
        selected: selected,
        label: item.name,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: extent,
            height: extent,
            decoration: BoxDecoration(
              color: isImage
                  ? AppColors.canvas2
                  : km.color.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.accentStrong : Colors.transparent,
                width: 2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: isImage && item.thumbnailUrl != null
                ? Image(
                    image: ApiImage(
                      item.thumbnailUrl!,
                      api: context.read<ApiClient>(),
                    ),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        Icon(km.icon, size: 18, color: AppColors.inkSoft),
                  )
                : Icon(km.icon, size: 20, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
