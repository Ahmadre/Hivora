/// Rendering a stored document, in hinata's design language.
library;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart' show ReadContext;
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../api/api_image.dart';
import '../repositories/media_repository.dart' show mediaThumbnailPath;
import '../i18n/i18n.dart';
import '../theme/app_colors.dart';
import '../../features/knowledge/markdown/smart_link_chip.dart';
import '../../features/knowledge/markdown/smart_link_resolver.dart';
import 'hinata_lexical.dart';
import 'hinata_theme.dart';

/// Resolves what a smart link points at, so a chip can show a live title
/// instead of the label that was denormalised into the document when it was
/// written.
///
/// Kept as a function rather than a repository so the same chip renders in the
/// knowledge base, in an issue and in a comment, each of which resolves against
/// a different source.
typedef SmartLinkTapped = void Function(SmartLinkKind kind, String targetId);

/// Builds the chip for one smart link. Returning null draws the default.
typedef SmartLinkChipBuilder =
    Widget? Function(
      BuildContext context,
      SmartLinkKind kind,
      String targetId,
      String? label,
    );

/// The block layouts hinata adds on top of the bundle's.
///
/// A callout draws its own tinted container here rather than through a
/// `BlockStyle`, because the tint depends on the node's `kind` and a block
/// style is resolved by type string alone.
/// [blockSpacing] is the rhythm between the blocks a callout holds. The
/// renderer applies a block style's spacing only at the top level, so a callout
/// with two paragraphs would otherwise render them flush against each other.
Map<String, BlockLayoutBuilder> hinataBlockLayouts({
  double blockSpacing = 0,
}) => {
  'callout': (context, element, buildChild) {
    final callout = element as CalloutNode;
    final style = calloutStyles[callout.kind]!;
    // Read the children inside this builder — it runs inside the editor's
    // read, and the widgets it returns are built later without one.
    final children = callout.children.map(buildChild).toList(growable: false);
    return _Callout(style: style, spacing: blockSpacing, children: children);
  },
};

/// A tinted block with a flavour rule down its left edge and its glyph beside
/// it.
class _Callout extends StatelessWidget {
  const _Callout({
    required this.style,
    required this.spacing,
    required this.children,
  });

  final CalloutStyle style;

  /// Space between the blocks inside the callout.
  final double spacing;

  final List<Widget> children;

  /// How round the block is. Small enough that the rule's ends read as flat:
  /// the corner curve is what clips them, and at 12 it bit eight pixels off
  /// each end and left the indicator looking like a bracket.
  static const double _radius = 8;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(_radius),
    child: ColoredBox(
      color: style.fill,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // A drawn bar, not a `Border(left:)`. A one-sided border under a
            // border radius is painted as the difference of two rounded rects,
            // so it tapers to nothing at both corners — a crescent, which is
            // exactly the rounding that had to go. A rectangle stays the width
            // it says it is.
            SizedBox(width: 3, child: ColoredBox(color: style.rule)),
            Expanded(
              child: Padding(
                // The only padding a callout has: the block style carries the
                // spacing above and below it, and nothing else, so the two do
                // not stack up into an inset twice as deep as either asks for.
                padding: const EdgeInsets.fromLTRB(11, 12, 14, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        top: 2,
                        end: 10,
                      ),
                      child: Icon(style.icon, size: 16, color: style.accent),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final (index, child) in children.indexed)
                            if (index == 0 || spacing <= 0)
                              child
                            else
                              Padding(
                                padding: EdgeInsets.only(top: spacing),
                                child: child,
                              ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Widget builders for every decorator a stored hinata document may contain.
///
/// The bundle covers images and embeds; this adds the two hinata registers
/// itself. [onTapSmartLink] and [chipBuilder] are the policies that genuinely
/// differ per surface — where a chip navigates to, and what it looks like once
/// its target is resolved.
///
/// [editable] is off by default because most surfaces that render a document
/// are readers: an article, an issue description, someone else's comment. The
/// bundle's image view offers drag handles and a caption editor when it is on,
/// and a reader who drags one edits an editor state nothing will ever save.
Map<String, DecoratorBuilder> hinataDecoratorBuilders({
  required LexicalEditor editor,
  SmartLinkTapped? onTapSmartLink,
  SmartLinkChipBuilder? chipBuilder,
  bool editable = false,
  ApiClient? api,
}) => {
  ...lexicalDecoratorBuilders(
    editor: editor,
    editable: editable,
    captionsEnabled: editable,
    imageResolver: hinataImageResolverFor(api),
    imageStyle: hinataImageStyle(),
    imagePlaceholderBuilder: hinataImagePlaceholder,
  ),
  'horizontalrule': (context, node) => const _Rule(),
  'smartlink': (context, node) {
    final link = node as SmartLinkNode;
    // Values, not the node: this builder runs inside the editor's read and the
    // widget is built later, outside one.
    final kind = link.kind;
    final targetId = link.targetId;
    final label = link.label;
    return _SmartLinkChip(
      kind: kind,
      targetId: targetId,
      label: label,
      onTap: onTapSmartLink,
      builder: chipBuilder,
    );
  },
};

/// The largest `data:` image a stored document may inline, in bytes.
///
/// A base64 payload is decoded into memory the moment the block is built, and
/// a document is written by whoever wrote it — a colleague, an inbound e-mail,
/// an agent. 512 KB is far more than a screenshot needs and far less than a
/// phone can be made to choke on.
const int hinataMaxInlineImageBytes = 512 * 1024;

/// Resolves a stored image address.
///
/// The bundle's default accepts any `http(s)` host and decodes any `data:`
/// payload. Both are reachable from a document someone else wrote, so:
///
/// * a `data:` URI larger than [hinataMaxInlineImageBytes] draws the
///   placeholder rather than being decoded, and
/// * everything else keeps the bundle's behaviour, deliberately. hinata is a
///   shared tracker whose documents legitimately link images from wikis,
///   status pages and CI — refusing unknown hosts would blank those, and the
///   only thing a request leaks is what fetching any image leaks.
/// Drawn where an image should be when it cannot be shown.
///
/// The bundle's stand-in is a grey box with the alt text in it, which reads as
/// "this is what the image is called" rather than as "this failed" — and an
/// uploaded screenshot that quietly turns into a grey rectangle is the kind of
/// thing people report as "it saved wrong". This says what happened, and keeps
/// the name so the picture is still identifiable.
Widget hinataImagePlaceholder(BuildContext context, String src) => Container(
  constraints: const BoxConstraints(minHeight: 88),
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
  decoration: BoxDecoration(
    color: AppColors.surfaceMuted,
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: AppColors.hairline),
  ),
  child: Row(
    children: [
      Icon(LucideIcons.imageOff, size: 18, color: AppColors.inkFaint),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.t('md.imageFailed'),
              style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 2),
            // The address, not the alt text: when an image will not load, what
            // is worth reading is where it was supposed to come from.
            Text(
              src,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: AppColors.inkFaint),
            ),
          ],
        ),
      ),
    ],
  ),
);

/// Opens [url] in the browser — what tapping a link does unless a host says
/// otherwise.
///
/// Refuses anything [isSafeUrl] refuses. A document is written by whoever wrote
/// it — a colleague, an inbound e-mail, an agent — so a `javascript:` or `file:`
/// address in one is a stored attack waiting for a tap, and the tap is exactly
/// where it has to be stopped.
Future<void> openHinataLink(String url) async {
  final trimmed = url.trim();
  if (trimmed.isEmpty || !isSafeUrl(trimmed)) return;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    // No handler for the scheme, or the platform refused. Silently: a reader
    // tapping a link is not a place for an error dialog about URL handlers.
  }
}

/// The resolver a surface uses, given the API client it can reach.
///
/// An uploaded image is stored behind the authenticated media proxy, so its
/// address is an app-relative path — `/api/v1/media/<uuid>` — with no host and
/// no bearer token. [defaultImageResolver] can only read that as an asset name,
/// which is why an upload that reached the server perfectly still rendered as a
/// broken box. With a client in hand the bytes are fetched properly; without
/// one — a test, a preview — everything else still resolves as before.
ImageResolver hinataImageResolverFor(ApiClient? api) => (src) {
  final trimmed = src.trim();
  if (!trimmed.startsWith('/')) return hinataImageResolver(trimmed);
  // The client from the tree when there is one, the app's own otherwise.
  //
  // The fallback is what makes this reliable rather than nearly reliable. A
  // decorator map is memoised, an `ImageProvider` outlives the build that made
  // it, and the surfaces that render documents are sheets and overlays on other
  // navigators — so "a client was in scope at the moment the resolver was
  // built" is a condition that holds *almost* always, and an image that almost
  // always loads is the bug being chased here. There is one client per process,
  // so taking it directly cannot pick the wrong one.
  final client = api ?? ApiClient.instance;
  if (client != null) {
    // With a thumbnail behind it the picture appears as soon as ~20 KB have
    // arrived and sharpens when the original does, instead of holding an empty
    // box for the whole download.
    return ApiImage(
      trimmed,
      api: client,
      previewPath: mediaThumbnailPath(trimmed),
    );
  }
  // Before `main` has built one — a test, a preview. Handing the path to
  // [hinataImageResolver] would read it as an asset name and produce a provider
  // guaranteed to fail, with no request and so no status code to explain it.
  // Null draws the placeholder at once.
  if (kDebugMode) {
    debugPrint('[media] $trimmed cannot be loaded: no ApiClient exists yet');
  }
  return null;
};

ImageProvider<Object>? hinataImageResolver(String src) {
  final trimmed = src.trim();
  if (trimmed.toLowerCase().startsWith('data:')) {
    // Measured on the encoded text, not by decoding it: decoding a payload to
    // discover it is too large is the exact allocation the cap exists to
    // prevent. Base64 spends four characters per three bytes.
    final comma = trimmed.indexOf(',');
    final encoded = comma < 0 ? 0 : trimmed.length - comma - 1;
    if (encoded * 3 ~/ 4 > hinataMaxInlineImageBytes) return null;
  }
  return defaultImageResolver(trimmed);
}

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: SizedBox(
      height: 1,
      width: double.infinity,
      child: ColoredBox(color: AppColors.hairline),
    ),
  );
}

/// The app's rich chip: resolves the target's live title and shows a hover
/// card, falling back to the label stored in the document.
///
/// Lives here as the default rather than inside the renderer so a surface with
/// no resolver in scope — a test, a preview — still gets something readable.
Widget? defaultSmartLinkChip(
  BuildContext context,
  SmartLinkKind kind,
  String targetId,
  String? label,
) {
  // The rich chip resolves its target through an ambient resolver and asserts
  // when there is none. Surfaces that have one — the knowledge base, an issue —
  // get it; anywhere else falls through to the plain chip rather than taking
  // the page down over a missing scope.
  final hasResolver =
      context.dependOnInheritedWidgetOfExactType<SmartLinkScope>() != null;
  if (!hasResolver) return null;
  return SmartLinkChip(kind: kind.wire, id: targetId);
}

/// The plain chip, used when nothing richer is supplied.
class _SmartLinkChip extends StatelessWidget {
  const _SmartLinkChip({
    required this.kind,
    required this.targetId,
    required this.label,
    this.onTap,
    this.builder,
  });

  final SmartLinkKind kind;
  final String targetId;
  final String? label;
  final SmartLinkTapped? onTap;
  final SmartLinkChipBuilder? builder;

  IconData get _icon => switch (kind) {
    SmartLinkKind.issue => LucideIcons.circleDot,
    SmartLinkKind.doc => LucideIcons.fileText,
    SmartLinkKind.user => LucideIcons.atSign,
  };

  @override
  Widget build(BuildContext context) {
    final custom = builder?.call(context, kind, targetId, label);
    if (custom != null) return custom;

    // The label is the denormalised copy; the id is the fallback so a chip is
    // never blank, which is the one thing worse than a stale title.
    final text = label ?? targetId;
    const accent = AppColors.accent;

    return GestureDetector(
      onTap: onTap == null ? null : () => onTap!(kind, targetId),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icon, size: 12, color: accent),
              const SizedBox(width: 4),
              // A chip sits in a line of prose and must never be wider than it.
              // The label is a title or a readable key, which fits; the fallback
              // is a raw id, which on a narrow screen does not — so it shrinks
              // and ellipsizes rather than overflowing the line it lives in.
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders a stored document, read-only.
///
/// This replaces the hand-rolled markdown renderer everywhere content is shown
/// rather than edited: the knowledge-base reader, an issue's description, a
/// comment bubble. It takes the stored JSON rather than an editor, because
/// every one of those surfaces has a string from the API and nothing else.
///
/// A document that fails to open renders as nothing rather than throwing. A
/// broken article must not take its whole page down with it, and the failure is
/// already loud where it matters — the wire-contract test.
class HinataDocument extends StatefulWidget {
  const HinataDocument({
    required this.doc,
    super.key,
    this.fontSize = 15,
    this.blockSpacing,
    this.registry,
    this.onDocument,
    this.onChecked,
    this.padding = EdgeInsets.zero,
    this.scrollable = false,
    this.onTapSmartLink,
    this.chipBuilder,
    this.onTapLink,
    this.stats,
  });

  /// The stored Lexical JSON. Null or unreadable renders nothing.
  final String? doc;

  /// Called with the whole document after a tick box in it is toggled.
  ///
  /// A rendered document is read-only, with one exception: a checklist. Ticking
  /// one off is reading it, not editing it, and a list that cannot be ticked is
  /// a picture of a list. But a box that ticks and never saves is worse than
  /// one that does nothing, so the boxes are live only where a host takes this
  /// callback and persists what it is handed. Whether the reader is allowed to
  /// is the server's answer, not this widget's.
  final void Function(String doc)? onChecked;

  /// Body size everything else scales from.
  final double fontSize;

  /// Space below each block. Defaults to the body size's rhythm; a comment row
  /// passes a smaller value so the last block does not leave a gap.
  final double? blockSpacing;

  /// Receives the mounted blocks, so a surface can scroll to one of them. The
  /// knowledge base's table of contents is the reason this exists.
  final BlockRegistry? registry;

  /// Called with the editor once a document has been opened, and again whenever
  /// a different one is. Node keys are assigned at parse time and are not in the
  /// stored JSON, so this is the only place a caller can learn them.
  ///
  /// Called with **null** when there is no document to open — it was null,
  /// empty, or unreadable. A surface that derives something from the document,
  /// an outline or a list of linked issues, has to be told the derivation is
  /// gone; a callback that simply never fires leaves the previous article's
  /// table of contents on screen as a row of dead buttons.
  final void Function(LexicalEditor? editor)? onDocument;

  /// Padding around the document.
  final EdgeInsetsGeometry padding;

  /// Whether to scroll. Off when embedded in another scrollable, which is the
  /// common case — a comment bubble inside a thread, a description inside a
  /// sheet.
  final bool scrollable;

  /// What tapping a smart-link chip does.
  final SmartLinkTapped? onTapSmartLink;

  /// Draws a chip once its target is resolved.
  final SmartLinkChipBuilder? chipBuilder;

  /// What tapping an external link does.
  ///
  /// Defaults to [openHinataLink] — the browser — rather than to nothing. Every
  /// reader in the app left this null, so every link in every article, issue
  /// and comment was inert: rendered blue, underlined, and dead. A link that
  /// cannot be followed is worse than plain text, because it promises.
  final void Function(String url)? onTapLink;

  /// Rebuild counters, forwarded to the renderer.
  ///
  /// The block cache is the whole point of `LexicalDocument`, and whether it
  /// survives an ancestor rebuild is invisible from the outside — a document
  /// that rebuilds every block every frame looks exactly like one that reuses
  /// them. This is how a test can tell the difference.
  // The counters are the renderer's own test-only hook; forwarding them is the
  // only way a test above this widget can reach them.
  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  final LexicalRenderStats? stats;

  @override
  State<HinataDocument> createState() => _HinataDocumentState();
}

class _HinataDocumentState extends State<HinataDocument> {
  LexicalEditor? _editor;
  String? _loaded;

  /// The memoised theme and decorator map, and the inputs they were built for.
  ///
  /// `LexicalDocument.didUpdateWidget` throws its whole block cache away when
  /// `theme` or `decoratorBuilders` is not `==` to the previous one, and
  /// `LexicalTheme` declares no `operator ==` while a fresh `Map` literal is
  /// never equal to another. Building either in `build()` therefore switches
  /// off the one optimisation the renderer is designed around: every block
  /// re-enters `editor.read()` and rebuilds its spans whenever *any* ancestor
  /// rebuilds — a comment thread on every SSE tick, an article on every
  /// keystroke in the composer above it.
  LexicalTheme? _theme;
  Map<String, DecoratorBuilder>? _decorators;
  ({
    double fontSize,
    double? blockSpacing,
    Brightness brightness,
    LexicalEditor? editor,
    bool tappable,
    ApiClient? api,
  })?
  _memoKey;

  /// The API client, when this surface is inside the app rather than a test.
  ///
  /// Only images stored behind the media proxy need it; everything else renders
  /// identically without one.
  ApiClient? get _api {
    try {
      return context.read<ApiClient>();
    } on Object {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(HinataDocument oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.doc != _loaded) _load();
  }

  @override
  void dispose() {
    _checkSub?.call();
    super.dispose();
  }

  /// Cancels the tick listener on the editor currently loaded.
  Unsubscribe? _checkSub;

  void _load() {
    _loaded = widget.doc;
    final source = widget.doc;
    LexicalEditor? opened;
    if (source != null && source.trim().isNotEmpty) {
      final editor = createHinataEditor();
      try {
        editor.setEditorState(editor.parseEditorStateFromString(source));
        // Read-only unless the host can save what a tick changes. The tick box
        // reads this flag, so leaving it set on a document nobody persists is
        // exactly the silent-revert this guards against.
        editor.isEditable = widget.onChecked != null;
        opened = editor;
      } on Object {
        // Unreadable: show nothing rather than an exception box in the middle
        // of an otherwise fine page.
        opened = null;
      }
    }
    _checkSub?.call();
    _checkSub = null;
    _editor = opened;
    final live = opened;
    if (live != null && widget.onChecked != null) {
      // The tick box commits straight to the editor, so the document changing
      // is the only signal there is that one was pressed.
      _checkSub = live.registerUpdateListener((_) {
        if (mounted) widget.onChecked?.call(live.toJsonString());
      });
    }

    final notify = widget.onDocument;
    if (notify != null) {
      // After the frame: the caller almost always calls setState from here, and
      // this runs during initState and didUpdateWidget. Null is reported the
      // same way a document is — a surface that heard about the last one has to
      // hear that this one is not there.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) notify(opened);
      });
    }
  }

  /// Forwards to the host's current callback rather than being it.
  ///
  /// The decorator map is memoised, so a closure captured into it would
  /// outlive the widget that supplied it. This indirection is stable, which is
  /// what lets the map be reused, and always calls the callback the host has
  /// right now.
  void _tapSmartLink(SmartLinkKind kind, String targetId) =>
      widget.onTapSmartLink?.call(kind, targetId);

  Widget? _chipBuilder(
    BuildContext context,
    SmartLinkKind kind,
    String targetId,
    String? label,
  ) => (widget.chipBuilder ?? defaultSmartLinkChip)(
    context,
    kind,
    targetId,
    label,
  );

  /// Rebuilds the theme and the decorator map only when something they depend
  /// on actually changed.
  void _refreshStyling(LexicalEditor editor) {
    final api = _api;
    final key = (
      fontSize: widget.fontSize,
      blockSpacing: widget.blockSpacing,
      // Every neutral token is a theme-aware getter, so a cached theme goes
      // stale the moment the app switches to dark.
      brightness: AppColors.brightness,
      editor: editor,
      tappable: widget.onTapSmartLink != null,
      api: api,
    );
    if (_memoKey == key && _theme != null && _decorators != null) return;
    _memoKey = key;
    _theme = hinataLexicalTheme(
      fontSize: widget.fontSize,
      blockSpacing: widget.blockSpacing,
      extraLayouts: hinataBlockLayouts(
        blockSpacing:
            widget.blockSpacing ?? hinataBlockSpacing(widget.fontSize),
      ),
    );
    _decorators = hinataDecoratorBuilders(
      editor: editor,
      api: api,
      onTapSmartLink: widget.onTapSmartLink == null ? null : _tapSmartLink,
      chipBuilder: _chipBuilder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final editor = _editor;
    if (editor == null) return const SizedBox.shrink();
    _refreshStyling(editor);
    return LexicalDocument(
      editor: editor,
      theme: _theme!,
      padding: widget.padding,
      scrollable: widget.scrollable,
      registry: widget.registry,
      decoratorBuilders: _decorators!,
      // ignore: invalid_use_of_visible_for_testing_member
      stats: widget.stats,
      interaction: LexicalInteraction(
        types: hinataInteractiveNodeTypes,
        onTap: (hit) {
          // The hit carries the node's serialized fields, which is where a
          // link's url lives — no read scope needed to get at it.
          final url = hit.json['url'];
          if (url is! String || url.isEmpty) return;
          (widget.onTapLink ?? openHinataLink)(url);
        },
      ),
    );
  }
}
