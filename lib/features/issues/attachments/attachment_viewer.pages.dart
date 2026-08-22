part of 'attachment_viewer.dart';

// ═══════════════════════════ Content fetching ═════════════════════════════

/// Byte-bounded LRU cache for viewer content, keyed by the API download path.
/// `PageView.builder` disposes off-screen pages, so without this, swiping
/// A→B→A would re-download A's full-resolution file (spinner + wasted mobile
/// data) every revisit. A plain map literal keeps insertion order, so
/// `keys.first` is the least-recently-used entry.
final Map<String, Uint8List> _bytesCache = {};
int _bytesCacheSize = 0;
const int _kBytesCacheMaxBytes = 48 * 1024 * 1024;

/// Fetches an attachment's raw bytes through the authenticated [ApiClient] from
/// the server's `/download` endpoint, caching them so paging back to an already
/// viewed item is instant. The object store is internal-only, so the client
/// never talks to it directly; [ViewerItem.url] holds the relative API download
/// path, not a storage URL.
Future<Uint8List> _fetchBytes(BuildContext context, String path) async {
  final cached = _bytesCache.remove(path);
  if (cached != null) {
    _bytesCache[path] = cached; // move to most-recently-used
    return cached;
  }
  final res = await context.read<ApiClient>().getBytes(path);
  final bytes = Uint8List.fromList(res?.bytes ?? const []);
  if (bytes.isNotEmpty) {
    _bytesCache[path] = bytes;
    _bytesCacheSize += bytes.lengthInBytes;
    while (_bytesCacheSize > _kBytesCacheMaxBytes && _bytesCache.length > 1) {
      final oldest = _bytesCache.keys.first;
      if (oldest == path) break;
      final removed = _bytesCache.remove(oldest);
      if (removed != null) _bytesCacheSize -= removed.lengthInBytes;
    }
  }
  return bytes;
}

/// The bytes the PDF stage hands to the rasterizer: the downloaded file, with
/// its annotations drawn into the pages where the platform would otherwise drop
/// them ([PdfAnnotations] — Apple only, a pass-through everywhere else).
///
/// Deliberately *not* folded into [_fetchBytes]: that cache is what a second
/// look at the same attachment is served from, and what it holds must stay the
/// file the server sent. Only this stage wants a redrawn copy of it, and only
/// for as long as it is on screen — which is also why the copy is not cached
/// itself. Keeping it would mean a second document in memory for every PDF the
/// viewer has passed, and the redrawn one is the bigger of the two: a form
/// comes back around three times its size. What a swipe back costs instead is
/// one redraw of a document that carries visible annotations at all — a
/// millisecond or so for the forms this is for.
Future<Uint8List> _fetchPdfBytes(BuildContext context, String path) =>
    _fetchBytes(context, path).then(PdfAnnotations.flatten);

/// Forgets a memoized download, so the next [_fetchBytes] really goes back to
/// the server. What "retry" has to mean: re-awaiting the same future — or
/// handing back the same LRU entry — would replay the exact bytes that just
/// failed to render, and the retry would be theatre.
void _dropCachedBytes(String path) {
  final removed = _bytesCache.remove(path);
  if (removed != null) _bytesCacheSize -= removed.lengthInBytes;
}

// ═══════════════════════════ Text preparation ═════════════════════════════

/// A decoded text file: the whole thing (what "copy" puts on the clipboard),
/// split into display rows with the source line number each row belongs to
/// (`0` marks the continuation of a hard-split over-long line), plus the
/// longest row — the one the unwrapped view measures to size its scroll.
typedef _TextDoc = ({
  String text,
  List<String> rows,
  List<int> numbers,
  String widest,
});

/// Rows longer than this are hard-split. One 5 MB line (a minified payload)
/// would otherwise be laid out as a single paragraph and freeze the frame; the
/// text itself is never dropped, only wrapped into further rows.
const int _kMaxRowChars = 2000;

/// Decodes text-preview [bytes] and, for JSON, pretty-prints them. Runs in a
/// background isolate via [compute] so a multi-MB file doesn't stall the UI
/// isolate; must stay a top-level function for [compute] to send it.
///
/// Returns null when the bytes are not text after all — which is how an
/// unknown type gets sent back to the type card.
_TextDoc? _prepareText(({Uint8List bytes, bool isJson}) msg) {
  if (msg.bytes.isEmpty) return null;
  // Always look at the bytes, not just at the declared type: a `.txt` that is
  // really a binary blob must not be splattered across the screen as mojibake.
  if (!looksLikeText(msg.bytes)) return null;

  // allowMalformed so a stray byte doesn't blow up the whole preview.
  var text = utf8.decode(msg.bytes, allowMalformed: true);
  if (text.startsWith('﻿')) text = text.substring(1); // BOM
  if (msg.isJson) {
    try {
      text = const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
    } catch (_) {
      // Not valid JSON — show it verbatim.
    }
  }
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  final lines = text.split('\n');
  final rows = <String>[];
  final numbers = <int>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.length <= _kMaxRowChars) {
      rows.add(line);
      numbers.add(i + 1);
      continue;
    }
    for (var at = 0; at < line.length; at += _kMaxRowChars) {
      final end = math.min(at + _kMaxRowChars, line.length);
      rows.add(line.substring(at, end));
      numbers.add(at == 0 ? i + 1 : 0);
    }
  }
  // Found here, on the isolate that already walked every row, rather than in
  // build(): a 100k-line log must not be scanned again on every zoom step.
  var widest = '';
  for (final row in rows) {
    if (row.length > widest.length) widest = row;
  }
  return (text: text, rows: rows, numbers: numbers, widest: widest);
}

// ═══════════════════════════════ Stage ════════════════════════════════════

/// One page of the viewer's pager: picks the renderer for [item] and hands it
/// the shared zoom + chrome plumbing.
class _StagePage extends StatelessWidget {
  const _StagePage({
    required this.item,
    required this.active,
    required this.zoom,
    required this.insets,
    required this.wrapText,
    required this.lineNumbers,
    required this.onTap,
    required this.onTextLoaded,
    required this.onDismissDrag,
    required this.onDismissEnd,
  });

  final ViewerItem item;

  /// Whether this is the page on screen. Only the active page writes the shared
  /// zoom and reports its text to the chrome.
  final bool active;
  final ValueNotifier<double> zoom;

  /// Space the floating chrome occupies at the top/bottom — scrollable content
  /// pads by it so its first and last lines aren't parked under a glass bar.
  final EdgeInsets insets;
  final bool wrapText;
  final bool lineNumbers;
  final VoidCallback onTap;
  final void Function(String id, String? text) onTextLoaded;
  final void Function(Offset delta) onDismissDrag;
  final void Function(Velocity velocity) onDismissEnd;

  @override
  Widget build(BuildContext context) {
    switch (item.preview) {
      case AttachmentPreviewKind.image:
        return _ImagePage(
          item: item,
          active: active,
          zoom: zoom,
          onTap: onTap,
          onDismissDrag: onDismissDrag,
          onDismissEnd: onDismissEnd,
        );
      case AttachmentPreviewKind.pdf:
        return _PdfPage(item: item, zoom: zoom, insets: insets, onTap: onTap);
      case AttachmentPreviewKind.text:
      case AttachmentPreviewKind.maybeText:
        return _TextPage(
          item: item,
          active: active,
          zoom: zoom,
          insets: insets,
          wrap: wrapText,
          lineNumbers: lineNumbers,
          onTap: onTap,
          onLoaded: onTextLoaded,
        );
      case AttachmentPreviewKind.none:
        return _DismissibleTapArea(
          onTap: onTap,
          onDismissDrag: onDismissDrag,
          onDismissEnd: onDismissEnd,
          child: Center(child: _FileCard(item: item)),
        );
    }
  }
}

/// Tap-to-toggle-chrome plus swipe-down-to-close, for the stages that have
/// nothing scrollable of their own to fight over the vertical drag.
class _DismissibleTapArea extends StatelessWidget {
  const _DismissibleTapArea({
    required this.child,
    required this.onTap,
    required this.onDismissDrag,
    required this.onDismissEnd,
  });

  final Widget child;
  final VoidCallback onTap;
  final void Function(Offset delta) onDismissDrag;
  final void Function(Velocity velocity) onDismissEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onVerticalDragUpdate: (d) => onDismissDrag(Offset(0, d.delta.dy)),
      onVerticalDragEnd: (d) => onDismissEnd(d.velocity),
      onVerticalDragCancel: () => onDismissEnd(Velocity.zero),
      child: child,
    );
  }
}

// ═══════════════════════════════ Image ════════════════════════════════════

/// Full-bleed, zoomable picture: pinch and trackpad-pinch, mouse wheel,
/// double-tap and the toolbar/keyboard all drive the same transform.
class _ImagePage extends StatefulWidget {
  const _ImagePage({
    required this.item,
    required this.active,
    required this.zoom,
    required this.onTap,
    required this.onDismissDrag,
    required this.onDismissEnd,
  });

  final ViewerItem item;
  final bool active;
  final ValueNotifier<double> zoom;
  final VoidCallback onTap;
  final void Function(Offset delta) onDismissDrag;
  final void Function(Velocity velocity) onDismissEnd;

  @override
  State<_ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends State<_ImagePage>
    with SingleTickerProviderStateMixin {
  /// The one place the bounds live is [_zoomRange] — the toolbar and the
  /// keyboard already read them from there, and a second copy here is how a
  /// change to one of them ships half-applied.
  static final _range = _zoomRange(AttachmentPreviewKind.image);

  Future<Uint8List>? _bytes;
  final TransformationController _view = TransformationController();
  late final AnimationController _zoomAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 190),
  );
  late final CurvedAnimation _zoomCurve = CurvedAnimation(
    parent: _zoomAnim,
    curve: Curves.easeOutCubic,
  );
  Animation<Matrix4>? _zoomTween;

  /// True while *we* are pushing a value into the shared notifier, so the
  /// notifier's own listener doesn't bounce it straight back at us.
  bool _syncing = false;

  /// Same trick one level down: [_report] writes the corrected transform back
  /// into the controller it is itself listening to.
  bool _normalising = false;
  bool _zoomed = false;
  Offset? _doubleTapAt;

  @override
  void initState() {
    super.initState();
    _view.addListener(_report);
    widget.zoom.addListener(_onRequestedZoom);
    _zoomAnim.addListener(() {
      final tween = _zoomTween;
      if (tween != null) _view.value = tween.value;
    });
  }

  @override
  void didUpdateWidget(covariant _ImagePage old) {
    super.didUpdateWidget(old);
    if (old.zoom != widget.zoom) {
      old.zoom.removeListener(_onRequestedZoom);
      widget.zoom.addListener(_onRequestedZoom);
    }
    // Leaving the screen resets the picture, so paging back always lands on the
    // whole image instead of a forgotten crop. Deferred by a frame: writing the
    // transform here would notify listeners in the middle of a build.
    if (old.active && !widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _zoomAnim.stop();
        _view.value = Matrix4.identity();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bytes ??= _fetchBytes(context, widget.item.url!);
  }

  @override
  void dispose() {
    widget.zoom.removeListener(_onRequestedZoom);
    _view.removeListener(_report);
    _zoomCurve.dispose();
    _zoomAnim.dispose();
    _view.dispose();
    super.dispose();
  }

  /// Publishes the transform's real scale, whatever caused it (pinch, wheel,
  /// double-tap, buttons), so the toolbar's percentage is never a guess — and
  /// keeps a picture that fits the window sitting where a picture that fits
  /// belongs.
  ///
  /// That second job exists because the widened [boundaryMargin] below 1× is
  /// room InteractiveViewer will happily translate into: `panEnabled: false`
  /// only takes the *pan* gesture away, while the scale gesture's own
  /// `_matrixTranslate` (and the mouse wheel, which never goes through the
  /// arena at all) keeps moving the child. A pinch off to one side could
  /// therefore slide a shrunken picture halfway out of the window with no way
  /// to drag it back, and the moment the scale crossed 1.01 again the boundary
  /// collapsed onto the child and yanked it back in one frame. Correcting here
  /// — on every change, before the margin ever narrows — means there is nothing
  /// left to yank.
  void _report() {
    final matrix = _view.value;
    final scale = matrix.getMaxScaleOnAxis();
    if (widget.active && (widget.zoom.value - scale).abs() > 0.005) {
      _syncing = true;
      widget.zoom.value = scale;
      _syncing = false;
    }
    final zoomed = scale > 1.01;
    if (zoomed != _zoomed && mounted) setState(() => _zoomed = zoomed);

    // Zoomed in, the tight boundary already holds the picture; mid-animation the
    // tween owns the matrix and correcting it frame by frame would fight it.
    if (zoomed || _normalising || _zoomAnim.isAnimating || !mounted) return;
    final size = context.size;
    if (size == null || size.isEmpty) return;
    final at = matrix.getTranslation();
    final tx = zoomFitTranslation(
      scale: scale,
      extent: size.width,
      wanted: at.x,
    );
    final ty = zoomFitTranslation(
      scale: scale,
      extent: size.height,
      wanted: at.y,
    );
    if ((tx - at.x).abs() < 0.5 && (ty - at.y).abs() < 0.5) return;
    _normalising = true;
    _view.value = matrix.clone()
      ..setEntry(0, 3, tx)
      ..setEntry(1, 3, ty);
    _normalising = false;
  }

  void _onRequestedZoom() {
    if (_syncing || !widget.active || !mounted) return;
    _zoomTo(widget.zoom.value);
  }

  /// Animates to [target], keeping the scene point under [focal] (the viewport
  /// centre by default) in place — the anchor rule every zoom UI follows.
  void _zoomTo(double target, {Offset? focal}) {
    final size = context.size;
    if (size == null || size.isEmpty) return;
    final current = _view.value.getMaxScaleOnAxis();
    final scale = target.clamp(_range.min, _range.max);
    if ((scale - current).abs() < 0.001) return;

    final anchor = focal ?? Offset(size.width / 2, size.height / 2);
    final scene = _view.toScene(anchor);
    // p_screen = scale · p_scene + t  ⇒  t = anchor − scale · scene
    var tx = anchor.dx - scale * scene.dx;
    var ty = anchor.dy - scale * scene.dy;

    // The child is viewport-sized (InteractiveViewer's constrained default), so
    // the same rule [_report] uses to correct a stray pinch applies here.
    tx = zoomFitTranslation(scale: scale, extent: size.width, wanted: tx);
    ty = zoomFitTranslation(scale: scale, extent: size.height, wanted: ty);

    final matrix = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      // Z too, even though nothing here is three-dimensional: every readout
      // goes through Matrix4.getMaxScaleOnAxis, which takes the largest of the
      // three. Left at the identity's 1, it silently wins below 100 % — the
      // picture shrinks while the toolbar keeps insisting it is at 1×, and the
      // minus button greys itself out again one step later.
      ..setEntry(2, 2, scale)
      ..setEntry(0, 3, tx)
      ..setEntry(1, 3, ty);
    _zoomTween = Matrix4Tween(
      begin: _view.value.clone(),
      end: matrix,
    ).animate(_zoomCurve);
    _zoomAnim.forward(from: 0);
  }

  void _onDoubleTap() {
    final zoomedIn = _view.value.getMaxScaleOnAxis() > 1.01;
    _zoomTo(zoomedIn ? 1 : 2.5, focal: zoomedIn ? null : _doubleTapAt);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    // Decode with headroom over the screen instead of at screen size: this
    // picture can be zoomed, and a bitmap decoded for 1× turns to mush at 4×.
    // ResizeImage never upscales, so a small picture still costs its own size.
    final decodeWidth =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context) *
                2)
            .round();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
      onDoubleTap: _onDoubleTap,
      // A zoomed picture pans; at 1× the same drag closes the viewer.
      onVerticalDragUpdate: _zoomed
          ? null
          : (d) => widget.onDismissDrag(Offset(0, d.delta.dy)),
      onVerticalDragEnd: _zoomed
          ? null
          : (d) => widget.onDismissEnd(d.velocity),
      onVerticalDragCancel: _zoomed
          ? null
          : () => widget.onDismissEnd(Velocity.zero),
      child: LayoutBuilder(
        builder: (context, constraints) => InteractiveViewer(
          transformationController: _view,
          minScale: _range.min,
          maxScale: _range.max,
          // `minScale` alone does not let a pinch below 1× through. With the
          // constrained default the child is viewport-sized, so InteractiveViewer's
          // own floor — max(viewport / boundaryRect) in _matrixScale — evaluates to
          // exactly 1 and wins over minScale. Widening the boundary by the amount
          // the floor needs is what actually unlocks it: a boundary 1/min times the
          // viewport puts that floor at min.
          //
          // Only while the picture fits, though. Once it is zoomed in, the extra
          // room would be pannable emptiness, so the boundary snaps back to the
          // child and pans stay on the picture exactly as before.
          boundaryMargin: _zoomed
              ? EdgeInsets.zero
              : EdgeInsets.symmetric(
                  horizontal: constraints.maxWidth * (1 / _range.min - 1) / 2,
                  vertical: constraints.maxHeight * (1 / _range.min - 1) / 2,
                ),
          // At or below 1× the picture fits, so there is nothing to pan.
          //
          // This does *not* hand the drag to the viewer's own gestures — the
          // same scale recognizer is registered either way, so swipe-to-close
          // and paging win for reasons this flag has no say in. What it stops is
          // the path that never reaches the arena: a trackpad two-finger scroll
          // arrives as a pointer signal and, with `trackpadScrollCausesScale`
          // off, lands on the pan branch. One flick would otherwise park a
          // picture that fits off to the side of the window.
          panEnabled: _zoomed,
          child: FutureBuilder<Uint8List>(
            future: _bytes,
            builder: (context, snap) {
              final done = snap.connectionState == ConnectionState.done;
              final bytes = snap.data;
              final hasFull = bytes != null && bytes.isNotEmpty;
              if (done && !hasFull) return Center(child: _FileCard(item: item));
              return Stack(
                fit: StackFit.expand,
                children: [
                  // The blurred stand-in fills the stage from the first frame and
                  // retires the moment the real picture is up.
                  AnimatedOpacity(
                    opacity: hasFull ? 0 : 1,
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOut,
                    child: (item.blurHash?.isNotEmpty ?? false)
                        ? Image(
                            image: BlurHashImage(item.blurHash!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          )
                        : const Center(
                            child: Padding(
                              padding: EdgeInsets.all(40),
                              child: HiveLoader(),
                            ),
                          ),
                  ),
                  // The thumbnail lands in a fraction of the bytes and already has
                  // the final geometry, so the swap to the original is invisible.
                  if (!hasFull && item.thumbnailUrl != null)
                    Center(
                      child: Image(
                        image: ApiImage(
                          item.thumbnailUrl!,
                          api: context.read<ApiClient>(),
                        ),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  if (hasFull)
                    Center(
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        cacheWidth: decodeWidth,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (_, _, _) => _FileCard(item: item),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════ PDF ═════════════════════════════════════

/// Renders a PDF inline by rasterizing its pages (via the `printing` package's
/// platform renderer) into a vertically scrollable preview. Zooming re-lays the
/// pages out wider — the way a document viewer zooms — instead of magnifying
/// the viewport, so the page always uses the full width it is given.
class _PdfPage extends StatefulWidget {
  const _PdfPage({
    required this.item,
    required this.zoom,
    required this.insets,
    required this.onTap,
  });

  final ViewerItem item;
  final ValueNotifier<double> zoom;
  final EdgeInsets insets;
  final VoidCallback onTap;

  @override
  State<_PdfPage> createState() => _PdfPageState();
}

class _PdfPageState extends State<_PdfPage> {
  /// Same rule as the image stage: [_zoomRange] is where the bounds live, and a
  /// second copy here is how a change to one of them ships half-applied.
  static final _range = _zoomRange(AttachmentPreviewKind.pdf);

  /// Space between two pages, and between a page and the edge of the sheet
  /// column. Ours now — the package's own page margin went with its layout.
  static const _pageMargin = EdgeInsets.symmetric(horizontal: 10, vertical: 8);

  // Fetch once; PdfPreview's build callback can fire repeatedly on relayout.
  Future<Uint8List>? _bytes;

  /// Both scroll axes belong to this state, because the page list does: the
  /// vertical one used to live inside the package's own `ListView`, where there
  /// was no way to move it in step with a pinch.
  final _horizontal = ScrollController();
  final _vertical = ScrollController();

  bool _failed = false;

  /// Bumped on every retry (and whenever this page is handed a different file)
  /// so the preview is rebuilt from a fresh element. The package only
  /// re-rasterizes when its `build` callback changes identity, and ours must
  /// not — a new key is the honest way to ask for another attempt.
  int _attempt = 0;

  /// The zoom the pages are currently laid out at, so the next change knows how
  /// much the content grew and by how much the scroll has to follow. Seeded in
  /// [initState], never `late`: a lazy field would first be read *inside* the
  /// handler for the first zoom change, by which time it would read back the
  /// new value and the very first zoom would find nothing to do.
  double _lastZoom = 1;

  /// Where the fingers were on the pinch that is about to change the zoom.
  /// Null for the toolbar and the keyboard, which anchor at the viewport centre
  /// exactly like the image stage.
  Offset? _pinchFocal;

  /// Passed as a tear-off on purpose: the preview compares this callback with
  /// the previous one and re-rasterizes the whole document whenever it differs,
  /// and tear-offs of the same method on the same state object are equal. A
  /// closure created inside `build()` would re-render every page on every zoom
  /// step (and on every resize).
  Future<Uint8List> _buildPdf(PdfPageFormat format) => _bytes!;

  @override
  void initState() {
    super.initState();
    _lastZoom = widget.zoom.value;
    widget.zoom.addListener(_onZoom);
  }

  @override
  void didUpdateWidget(covariant _PdfPage old) {
    super.didUpdateWidget(old);
    if (old.zoom != widget.zoom) {
      old.zoom.removeListener(_onZoom);
      widget.zoom.addListener(_onZoom);
      _lastZoom = widget.zoom.value;
    }
    // Reused for a different attachment: nothing about the old one survives —
    // least of all a failure, which would otherwise show this file the previous
    // file's error card for as long as the element lives.
    if (old.item.id != widget.item.id) {
      _failed = false;
      _attempt++;
      _bytes = _fetchPdfBytes(context, widget.item.url!);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bytes ??= _fetchPdfBytes(context, widget.item.url!);
  }

  @override
  void dispose() {
    widget.zoom.removeListener(_onZoom);
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  // ── Zoom ──────────────────────────────────────────────────────────────────
  /// Moves both scroll axes so the spot the zoom was aimed at stays put.
  ///
  /// The pages re-lay out on the same notification, so the new scroll extents
  /// only exist after that frame — reading them now would clamp against the old
  /// document height and drop the anchor a screen short.
  void _onZoom() {
    final from = _lastZoom;
    final to = widget.zoom.value;
    final focal = _pinchFocal;
    _pinchFocal = null;
    if (from <= 0 || (to - from).abs() < 0.0001) return;
    _lastZoom = to;
    final factor = to / from;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = context.size;
      if (size == null || size.isEmpty) return;
      final at = focal ?? Offset(size.width / 2, size.height / 2);
      _anchor(_horizontal, at.dx, factor);
      _anchor(_vertical, at.dy, factor);
    });
  }

  void _anchor(ScrollController controller, double focal, double factor) {
    // An axis with nothing to scroll has no position to move: below 1× the
    // pages are narrower than the window and belong centred, which the layout
    // already does, and pinning such an axis to 0 would be a no-op at best.
    if (!controller.hasClients) return;
    final position = controller.position;
    if (position.maxScrollExtent <= 0) return;
    final target = zoomAnchoredOffset(
      offset: position.pixels,
      focal: focal,
      factor: factor,
      maxExtent: position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 0.5) return;
    controller.jumpTo(target);
  }

  // ── Failure ───────────────────────────────────────────────────────────────
  /// Drops everything this attempt produced — the memoized future, the bytes in
  /// the LRU, the preview element — and starts over.
  void _retry() {
    final url = widget.item.url;
    if (url == null) return;
    _dropCachedBytes(url);
    setState(() {
      _failed = false;
      _attempt++;
      _bytes = _fetchPdfBytes(context, url);
    });
  }

  Widget _errorCard(BuildContext context) => Center(
    child: _FileCard(
      item: widget.item,
      // Not "no preview for this type" — we *do* preview PDFs, and telling the
      // user their file is unsupported when the render failed sends them off
      // to find another viewer instead of pressing the button below.
      note: context.t('issues.attachments.viewer.renderFailed'),
      action: _CardAction(
        icon: LucideIcons.rotateCcw,
        label: context.t('issues.attachments.viewer.retry'),
        onTap: _retry,
      ),
    ),
  );

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_failed) return _errorCard(context);
    return _PinchZoom(
      zoom: widget.zoom,
      range: _range,
      onTap: widget.onTap,
      onFocal: (focal) => _pinchFocal = focal,
      child: PdfPreview.builder(
        key: ValueKey(_attempt),
        build: _buildPdf,
        // We lay the pages out ourselves. Not for the looks — for the two
        // things the package's own layout takes away:
        //  • every page is wrapped in a GestureDetector whose double-tap swaps
        //    the document for a single page inside the package's *own*
        //    InteractiveViewer. Two zoom systems then fight over the same
        //    document, and ours (which widens the pages) slides the other one's
        //    centred page off to the side. `pagesBuilder` is consulted before
        //    those detectors are ever built, so that mode becomes unreachable.
        //  • the scroll controllers were the package's, so a pinch could not
        //    move the document under the fingers.
        pagesBuilder: _buildPages,
        // Deliberately no `maxPageWidth`. It reads as a layout constraint but
        // also feeds the raster *resolution* (`dpi = min(window − 16,
        // maxPageWidth) · dpr / pageWidth · inch`), and while a change to it
        // does not re-raster on its own, any MediaQuery change does — so a
        // document zoomed to 25 % would come back at a quarter of the DPI after
        // the next resize and stay a blur for the rest of the session. Leaving
        // it null pins the raster to the window, and the zoomed width comes from
        // our own layout below.
        useActions: false,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        allowPrinting: false,
        allowSharing: false,
        // Rasterizing a PDF locally takes a moment; the server already
        // rendered its first page once, so the blur of that page
        // stands in meanwhile.
        loadingWidget: (widget.item.blurHash?.isNotEmpty ?? false)
            ? Image(
                image: BlurHashImage(widget.item.blurHash!),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Padding(
                  padding: EdgeInsets.all(40),
                  child: HiveLoader(),
                ),
              )
            : const Padding(padding: EdgeInsets.all(40), child: HiveLoader()),
        onError: (context, error) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _failed = true);
          });
          return _errorCard(context);
        },
      ),
    );
  }

  /// The whole document: a column of sheets, as wide as the zoom asks for, in
  /// a viewport we own on both axes.
  Widget _buildPages(BuildContext context, List<PdfPreviewPageData> pages) {
    return SizedBox.expand(
      child: LayoutBuilder(
        builder: (context, constraints) => ValueListenableBuilder<double>(
          valueListenable: widget.zoom,
          builder: (context, zoom, _) {
            // Zooming a document means the page gets bigger, not that the
            // window magnifies — so the width is the whole of the zoom, and
            // below 1× the pages are simply narrower than the window.
            final pageWidth = constraints.maxWidth * zoom;
            final columnWidth = math.max(constraints.maxWidth, pageWidth);
            return SingleChildScrollView(
              controller: _horizontal,
              scrollDirection: Axis.horizontal,
              physics: zoom > 1.01
                  ? const ClampingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              child: SizedBox(
                width: columnWidth,
                child: ListView.builder(
                  controller: _vertical,
                  // The floating chrome would otherwise sit on the first and
                  // last page.
                  padding: EdgeInsets.only(
                    top: widget.insets.top,
                    bottom: widget.insets.bottom,
                  ),
                  itemCount: pages.length,
                  itemBuilder: (context, i) => Center(
                    child: SizedBox(
                      width: pageWidth,
                      child: _PdfSheet(page: pages[i], margin: _pageMargin),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One rasterized page on its white sheet — the paper the package used to draw
/// for us, minus the double-tap detector it came wrapped in.
class _PdfSheet extends StatelessWidget {
  const _PdfSheet({required this.page, required this.margin});

  final PdfPreviewPageData page;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    // A page with no height (or no width) would make AspectRatio assert and
    // take the whole viewer down with it. Portrait is the sane stand-in.
    final ratio = page.aspectRatio;
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF14122D).withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: AspectRatio(
        aspectRatio: ratio > 0 && ratio.isFinite ? ratio : 1 / math.sqrt2,
        child: Image(
          image: page.image,
          fit: BoxFit.cover,
          // The raster is made for the window's width; zoomed past that it is
          // being upscaled, and nearest-neighbour turns type into stairsteps.
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

// ════════════════════════════════ Text ════════════════════════════════════

/// Fetches a text file and renders it as selectable, monospace rows: line
/// numbers, wrap on/off, pinch/⌘-± type scaling and copy — the "read it and
/// grab a snippet" case attachments are usually opened for.
///
/// Content is rendered as **plain text only**, never as markup or a document:
/// an attached `.html` or `.svg` shows its source, so nothing an uploader wrote
/// can execute or phish here.
class _TextPage extends StatefulWidget {
  const _TextPage({
    required this.item,
    required this.active,
    required this.zoom,
    required this.insets,
    required this.wrap,
    required this.lineNumbers,
    required this.onTap,
    required this.onLoaded,
  });

  final ViewerItem item;
  final bool active;
  final ValueNotifier<double> zoom;
  final EdgeInsets insets;
  final bool wrap;
  final bool lineNumbers;
  final VoidCallback onTap;
  final void Function(String id, String? text) onLoaded;

  @override
  State<_TextPage> createState() => _TextPageState();
}

class _TextPageState extends State<_TextPage> {
  static const double _baseFontSize = 13;

  Future<_TextDoc?>? _load;
  _TextDoc? _doc;
  final _vertical = ScrollController();
  final _horizontal = ScrollController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load ??= _read();
  }

  @override
  void didUpdateWidget(covariant _TextPage old) {
    super.didUpdateWidget(old);
    // Wrapping again makes the sideways scroll meaningless, but a scroll
    // position that can no longer be moved would leave the text parked off to
    // the left for good.
    if (!old.wrap && widget.wrap && _horizontal.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _horizontal.hasClients && _horizontal.offset != 0) {
          _horizontal.jumpTo(0);
        }
      });
    }
    // The chrome forgets the text on every page change, so hand it back when
    // this page returns to the screen (its bytes are already cached). After the
    // frame: this runs inside the viewer's own build, and the chrome reacts to
    // it with setState.
    if (!old.active && widget.active) {
      final doc = _doc;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onLoaded(widget.item.id, doc?.text);
      });
    }
  }

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  Future<_TextDoc?> _read() async {
    final bytes = await _fetchBytes(context, widget.item.url!);
    final name = widget.item.name.toLowerCase();
    final isJson =
        widget.item.mime?.split(';').first.trim() == 'application/json' ||
        name.endsWith('.json') ||
        name.endsWith('.geojson');
    // Decoding, sniffing and (for JSON) pretty-printing up to 2 MB is heavy
    // enough to drop frames on the UI isolate, so hand it to a background one.
    // On web compute() runs inline (no isolates), which is fine — the fetch has
    // already yielded the event loop.
    final doc = await compute(_prepareText, (bytes: bytes, isJson: isJson));
    if (mounted) {
      _doc = doc;
      if (widget.active) widget.onLoaded(widget.item.id, doc?.text);
    }
    return doc;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_TextDoc?>(
      future: _load,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: HiveLoader());
        }
        final doc = snap.data;
        if (snap.hasError || doc == null) {
          return Center(child: _FileCard(item: widget.item));
        }
        if (doc.text.trim().isEmpty) {
          return Center(
            child: _FileCard(
              item: widget.item,
              note: context.t('issues.attachments.viewer.emptyFile'),
            ),
          );
        }
        return _PinchZoom(
          zoom: widget.zoom,
          range: _zoomRange(AttachmentPreviewKind.text),
          onTap: widget.onTap,
          child: ValueListenableBuilder<double>(
            valueListenable: widget.zoom,
            builder: (context, zoom, _) => _paper(doc, zoom),
          ),
        );
      },
    );
  }

  /// Width one line of [text] really takes in [style] — one layout of one line,
  /// which is what keeps this affordable on a file with 100 000 of them.
  double _measure(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// The text sits on its own sheet, so a file's body never has to be read
  /// straight off the stage. The sheet is dark in both app themes like the rest
  /// of the viewer ([_ViewerInk]): the reader is inside a near-black lightbox
  /// either way, and a sheet of white paper punched into it — which is what the
  /// light theme used to hand out — is the one surface here that does not
  /// belong to the room it is in.
  Widget _paper(_TextDoc doc, double zoom) {
    final fontSize = _baseFontSize * zoom;
    final phone = MediaQuery.sizeOf(context).width < 610;
    final mono = TextStyle(
      fontFamily: AppTheme.fontMono,
      fontSize: fontSize,
      height: 1.5,
      color: _ViewerInk.ink,
    );
    // Wide enough for the highest line number this file can show. Measured
    // rather than guessed from an advance width: a gutter one pixel too narrow
    // wraps the number onto a second line and pushes the row out of shape.
    final gutterWidth = widget.lineNumbers
        ? math.max(
            30.0,
            _measure('8' * '${doc.numbers.length}'.length, mono) + 4,
          )
        : 0.0;

    final hPad = phone ? 10.0 : 18.0;
    // Only the rows are lazy — a 2 MB log is tens of thousands of them, and
    // laying every one out up front would freeze the frame that opens the file.
    final Widget lines = Scrollbar(
      controller: _vertical,
      child: ListView.builder(
        controller: _vertical,
        padding: EdgeInsets.fromLTRB(
          hPad,
          widget.insets.top + 14,
          hPad,
          widget.insets.bottom + 14,
        ),
        itemCount: doc.rows.length,
        // Room for drag-selection to run past the visible rows without
        // building the whole file.
        scrollCacheExtent: const ScrollCacheExtent.pixels(900),
        itemBuilder: (context, i) => _TextRow(
          text: doc.rows[i],
          number: widget.lineNumbers ? doc.numbers[i] : null,
          gutterWidth: gutterWidth,
          style: mono,
          wrap: widget.wrap,
        ),
      ),
    );

    // How far the rows reach sideways when they are not wrapped. Measured, not
    // estimated from an advance width: too narrow and the tail of the longest
    // line would sit past the end of the scroll, unreachable — and, with a
    // gutter beside it, overflow its own row. Only the longest row is laid
    // out, so this stays cheap on a huge file.
    final contentWidth = widget.wrap
        ? 0.0
        : (widget.lineNumbers ? gutterWidth + _kGutterGap : 0) +
              _measure(doc.widest, mono) +
              2 * hPad;

    // The same widget chain in both modes, on purpose: toggling wrap only
    // changes numbers, never the shape of the tree, so the list keeps its
    // element — and with it the reading position and the live selection —
    // instead of being torn down and rebuilt at the top of the file.
    //
    // The vertical scrollbar stays *inside* the horizontal viewport: a
    // Scrollbar only listens to depth-0 scroll notifications, so nesting it
    // the other way around would leave it attached to nothing.
    final Widget rows = LayoutBuilder(
      builder: (context, constraints) => Scrollbar(
        controller: _horizontal,
        child: SingleChildScrollView(
          controller: _horizontal,
          scrollDirection: Axis.horizontal,
          physics: widget.wrap
              ? const NeverScrollableScrollPhysics()
              : const ClampingScrollPhysics(),
          child: SizedBox(
            width: math.max(constraints.maxWidth, contentWidth),
            child: lines,
          ),
        ),
      ),
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: phone ? 8 : 22, vertical: 0),
          decoration: BoxDecoration(
            color: _ViewerInk.canvas,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _ViewerInk.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          // One region across every row, so a drag selects across lines and
          // ⌘C / the context menu copy exactly what is highlighted. Whole-file
          // copy lives in the toolbar, which never depends on what is built.
          child: SelectionArea(child: rows),
        ),
      ),
    );
  }
}

/// Space between the line-number gutter and the text it belongs to.
const double _kGutterGap = 12;

/// One rendered row: the source line number in a muted gutter, then the text.
class _TextRow extends StatelessWidget {
  const _TextRow({
    required this.text,
    required this.number,
    required this.gutterWidth,
    required this.style,
    required this.wrap,
  });

  final String text;

  /// Source line number, `0` for the continuation of a hard-split long line,
  /// null when the gutter is off.
  final int? number;
  final double gutterWidth;
  final TextStyle style;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final body = Text(
      // A blank row still needs a line box, otherwise paragraphs collapse.
      text.isEmpty ? ' ' : text,
      style: style,
      softWrap: wrap,
      overflow: wrap ? TextOverflow.clip : TextOverflow.visible,
      maxLines: wrap ? null : 1,
    );
    if (number == null) return body;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: gutterWidth,
          child: Text(
            number == 0 ? '' : '$number',
            textAlign: TextAlign.right,
            maxLines: 1,
            style: style.copyWith(color: _ViewerInk.faint),
          ),
        ),
        const SizedBox(width: _kGutterGap),
        // Expanded in both modes: an unwrapped row is laid out unconstrained
        // and paints past its box on purpose, and handing a Row a child wider
        // than itself is an overflow error, not a scroll.
        Expanded(child: body),
      ],
    );
  }
}

// ═════════════════════════════ Shared bits ════════════════════════════════

/// Two-finger (and trackpad) pinch mapped onto the shared zoom value, for the
/// stages that zoom by *re-laying out* rather than by transforming a bitmap.
///
/// Single-finger drags are left alone: a scale recognizer only claims one
/// pointer after the (much larger) pan slop, so the content's own scrolling
/// wins them — which is exactly what a reader expects.
class _PinchZoom extends StatefulWidget {
  const _PinchZoom({
    required this.zoom,
    required this.range,
    required this.onTap,
    required this.child,
    this.onFocal,
  });

  final ValueNotifier<double> zoom;
  final ({double min, double max, double step}) range;
  final VoidCallback onTap;
  final Widget child;

  /// Where the fingers are, in this widget's coordinates, reported immediately
  /// *before* each new zoom value — so a stage that can act on it knows which
  /// change carries a focal point and which (toolbar, keyboard) does not.
  ///
  /// Opt-in, and the text stage deliberately does not: it zooms the type size,
  /// where "the character under your fingers stays put" is not what anyone is
  /// asking for — a reader pinching a log wants more or fewer lines, and the
  /// row they were on is exactly what should stay at the top.
  final void Function(Offset focal)? onFocal;

  @override
  State<_PinchZoom> createState() => _PinchZoomState();
}

class _PinchZoomState extends State<_PinchZoom> {
  double _start = 1;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onScaleStart: (_) => _start = widget.zoom.value,
      onScaleUpdate: (d) {
        if (d.pointerCount < 2) return;
        final next = (_start * d.scale).clamp(
          widget.range.min,
          widget.range.max,
        );
        // A pinch that has run into the floor or the ceiling still updates
        // every frame; announcing a focal point for a zoom that never happens
        // would leave it waiting for the next change, which may well be a
        // toolbar tap that belongs at the centre.
        if (next == widget.zoom.value) return;
        widget.onFocal?.call(d.localFocalPoint);
        widget.zoom.value = next;
      },
      child: widget.child,
    );
  }
}

/// The "nothing to preview" card: the file's type, name and size, plus why it
/// isn't on screen.
class _FileCard extends StatelessWidget {
  const _FileCard({required this.item, this.note, this.action});

  final ViewerItem item;

  /// Overrides the default "no inline preview" line (e.g. "file is empty").
  final String? note;

  /// Something to do about it, under the reason. Only the failures the user can
  /// act on carry one — "this type has no preview" is a fact, not a setback.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final km = kindMeta(item.kind);
    // A text file that is simply too big to render says so — "no preview for
    // this type" would be a lie, and the download button is the answer.
    final reason =
        note ??
        (isTextPreviewable(item.name, item.mime) &&
                item.size > kMaxTextPreviewBytes
            ? context.t('issues.attachments.viewer.tooLarge')
            : context.t('issues.attachments.noPreview'));
    // Dark in both themes, like every other surface the viewer authors. This
    // card is not a rendering of the file — it is the viewer explaining itself,
    // the same job as the bars — and the measurements agree: on a dark card the
    // amber wash under [_CardAction] is the dark-mode pairing that clears AA
    // (5.5:1), while the light one is an opaque cream that leaves its own label
    // at 2.8:1. A card that flipped with the app would have to invent a second
    // set of accent tokens to stay legible.
    return Container(
      constraints: const BoxConstraints(maxWidth: 380),
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 30),
      decoration: BoxDecoration(
        color: _ViewerInk.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        // Outlined in [_ViewerInk.faint], not in [_ViewerInk.hairline], and
        // that is the whole reason this card is visible as a card. A hairline
        // is a seam between two surfaces; here there is no second surface —
        // a dark card sits on a darker stage at 1.07:1, so the fill draws no
        // boundary at all and the hairline over it manages 1.2:1. What located
        // the card was the saturated kind tile below, which is a *decoration*,
        // not an edge. This outline clears the 3:1 WCAG asks of a boundary
        // against both backdrops (4.7:1 over a light app's, 6.0:1 over a dark
        // one's) without a shadow, which on a near-black stage would have
        // nothing left to darken.
        border: Border.all(color: _ViewerInk.faint),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              color: km.color,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(km.icon, size: 34, color: Colors.white),
          ),
          const SizedBox(height: 14),
          Text(
            item.name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _ViewerInk.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${item.kind.toUpperCase()} · ${formatBytes(item.size)}',
            style: const TextStyle(fontSize: 12.5, color: _ViewerInk.soft),
          ),
          const SizedBox(height: 6),
          Text(
            reason,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: _ViewerInk.faint),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// The one thing to do about a card's bad news — an amber pill under the
/// reason, sized to its label.
class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        // Same token pairing as the toolbar's active state: the wash carries
        // its own opacity, so it stays a wash on dark instead of solid amber.
        color: _ViewerInk.accentSoft,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: _ViewerInk.accentLine),
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: _ViewerInk.accentInk),
                const SizedBox(width: 8),
                // Flexible, not bare: the pill shrink-wraps its label, and a
                // long translation (or a large text scale) would otherwise push
                // the row straight out of the card it sits in.
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _ViewerInk.accentInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
