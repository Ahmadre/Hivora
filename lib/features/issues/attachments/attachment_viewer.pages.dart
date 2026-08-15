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

// ═══════════════════════════ Text preparation ═════════════════════════════

/// A decoded text file: the whole thing (what "copy" puts on the clipboard),
/// split into display rows with the source line number each row belongs to
/// (`0` marks the continuation of a hard-split over-long line).
typedef _TextDoc = ({String text, List<String> rows, List<int> numbers});

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
  return (text: text, rows: rows, numbers: numbers);
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
  static const double _minScale = 1;
  static const double _maxScale = 8;

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
  /// double-tap, buttons), so the toolbar's percentage is never a guess.
  void _report() {
    final scale = _view.value.getMaxScaleOnAxis();
    if (widget.active && (widget.zoom.value - scale).abs() > 0.005) {
      _syncing = true;
      widget.zoom.value = scale;
      _syncing = false;
    }
    final zoomed = scale > 1.01;
    if (zoomed != _zoomed && mounted) setState(() => _zoomed = zoomed);
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
    final scale = target.clamp(_minScale, _maxScale);
    if ((scale - current).abs() < 0.001) return;

    final anchor = focal ?? Offset(size.width / 2, size.height / 2);
    final scene = _view.toScene(anchor);
    // p_screen = scale · p_scene + t  ⇒  t = anchor − scale · scene
    var tx = anchor.dx - scale * scene.dx;
    var ty = anchor.dy - scale * scene.dy;
    // The child is viewport-sized (InteractiveViewer's constrained default), so
    // the visible window at `scale` spans exactly these translations. Clamping
    // here keeps a button-driven zoom inside the same bounds a drag obeys.
    tx = tx.clamp(-(scale - 1) * size.width, 0.0);
    ty = ty.clamp(-(scale - 1) * size.height, 0.0);

    final matrix = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
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
      child: InteractiveViewer(
        transformationController: _view,
        minScale: _minScale,
        maxScale: _maxScale,
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
  // Fetch once; PdfPreview's build callback can fire repeatedly on relayout.
  Future<Uint8List>? _bytes;

  final _scroll = ScrollController();
  bool _failed = false;

  /// Passed as a tear-off on purpose: the preview compares this callback with
  /// the previous one and re-rasterizes the whole document whenever it differs,
  /// and tear-offs of the same method on the same state object are equal. A
  /// closure created inside `build()` would re-render every page on every zoom
  /// step (and on every resize).
  Future<Uint8List> _buildPdf(PdfPageFormat format) => _bytes!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bytes ??= _fetchBytes(context, widget.item.url!);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return Center(child: _FileCard(item: widget.item));
    return _PinchZoom(
      zoom: widget.zoom,
      range: _zoomRange(AttachmentPreviewKind.pdf),
      onTap: widget.onTap,
      child: LayoutBuilder(
        builder: (context, constraints) => ValueListenableBuilder<double>(
          valueListenable: widget.zoom,
          builder: (context, zoom, _) {
            final width = constraints.maxWidth * zoom;
            return SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              physics: zoom > 1.01
                  ? const ClampingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              child: SizedBox(
                width: math.max(constraints.maxWidth, width),
                child: PdfPreview(
                  build: _buildPdf,
                  maxPageWidth: width,
                  useActions: false,
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                  allowPrinting: false,
                  allowSharing: false,
                  padding: EdgeInsets.only(
                    top: widget.insets.top,
                    bottom: widget.insets.bottom,
                  ),
                  pdfPreviewPageDecoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF14122D).withValues(alpha: 0.28),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
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
                      : const Padding(
                          padding: EdgeInsets.all(40),
                          child: HiveLoader(),
                        ),
                  onError: (context, error) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _failed = true);
                    });
                    return _FileCard(item: widget.item);
                  },
                ),
              ),
            );
          },
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

  /// The text sits on its own themed sheet: the stage behind it is dark for
  /// pictures, which would make theme-coloured ink unreadable.
  Widget _paper(_TextDoc doc, double zoom) {
    final fontSize = _baseFontSize * zoom;
    final phone = MediaQuery.sizeOf(context).width < 610;
    final mono = TextStyle(
      fontFamily: AppTheme.fontMono,
      fontSize: fontSize,
      height: 1.5,
      color: AppColors.ink,
    );
    final gutterWidth = widget.lineNumbers
        ? math.max(30.0, ('${doc.numbers.length}'.length + 1) * fontSize * 0.62)
        : 0.0;

    final hPad = phone ? 10.0 : 18.0;
    // Only the rows are lazy — a 2 MB log is tens of thousands of them, and
    // laying every one out up front would freeze the frame that opens the file.
    Widget rows = Scrollbar(
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

    if (!widget.wrap) {
      // Widest row, roughly: a monospace advance is ~0.6 em. Measuring exactly
      // would mean laying out every row, and this only sets how far the
      // horizontal scroll reaches.
      final widest = doc.rows.fold<int>(0, (m, r) => math.max(m, r.length));
      final contentWidth = gutterWidth + widest * fontSize * 0.62 + 2 * hPad;
      // The vertical scrollbar stays *inside* the horizontal viewport on
      // purpose: a Scrollbar only listens to depth-0 scroll notifications, so
      // nesting it the other way around would leave it attached to nothing.
      rows = LayoutBuilder(
        builder: (context, constraints) => Scrollbar(
          controller: _horizontal,
          child: SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: math.max(constraints.maxWidth, contentWidth),
              child: rows,
            ),
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: phone ? 8 : 22, vertical: 0),
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.hairline),
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
            style: style.copyWith(color: AppColors.inkFaint),
          ),
        ),
        const SizedBox(width: 12),
        wrap ? Expanded(child: body) : body,
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
  });

  final ValueNotifier<double> zoom;
  final ({double min, double max, double step}) range;
  final VoidCallback onTap;
  final Widget child;

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
        widget.zoom.value = (_start * d.scale).clamp(
          widget.range.min,
          widget.range.max,
        );
      },
      child: widget.child,
    );
  }
}

/// The "nothing to preview" card: the file's type, name and size, plus why it
/// isn't on screen.
class _FileCard extends StatelessWidget {
  const _FileCard({required this.item, this.note});

  final ViewerItem item;

  /// Overrides the default "no inline preview" line (e.g. "file is empty").
  final String? note;

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
    return Container(
      constraints: const BoxConstraints(maxWidth: 380),
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 30),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.hairline),
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
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '${item.kind.toUpperCase()} · ${formatBytes(item.size)}',
            style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
          ),
          const SizedBox(height: 6),
          Text(
            reason,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
          ),
        ],
      ),
    );
  }
}
