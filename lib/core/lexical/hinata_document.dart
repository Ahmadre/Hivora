/// Rendering a stored document, in hinata's design language.
library;

import 'package:flutter/widgets.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
Map<String, BlockLayoutBuilder> hinataBlockLayouts() => {
  'callout': (context, element, buildChild) {
    final callout = element as CalloutNode;
    final style = calloutStyles[callout.kind]!;
    // Read the children inside this builder — it runs inside the editor's read,
    // and the widgets it returns are built later without one.
    final children = callout.children.map(buildChild).toList(growable: false);
    return _Callout(style: style, children: children);
  },
};

/// A tinted block with a flavour icon down its left edge.
class _Callout extends StatelessWidget {
  const _Callout({required this.style, required this.children});

  final CalloutStyle style;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: style.fill,
      borderRadius: BorderRadius.circular(12),
      border: Border(left: BorderSide(color: style.rule, width: 3)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 10),
            child: Icon(style.icon, size: 16, color: style.accent),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        ],
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
Map<String, DecoratorBuilder> hinataDecoratorBuilders({
  required LexicalEditor editor,
  SmartLinkTapped? onTapSmartLink,
  SmartLinkChipBuilder? chipBuilder,
}) => {
  ...lexicalDecoratorBuilders(editor: editor),
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
    this.padding = EdgeInsets.zero,
    this.scrollable = false,
    this.onTapSmartLink,
    this.chipBuilder,
    this.onTapLink,
  });

  /// The stored Lexical JSON. Null or unreadable renders nothing.
  final String? doc;

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
  final void Function(LexicalEditor editor)? onDocument;

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
  final void Function(String url)? onTapLink;

  @override
  State<HinataDocument> createState() => _HinataDocumentState();
}

class _HinataDocumentState extends State<HinataDocument> {
  LexicalEditor? _editor;
  String? _loaded;

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

  void _load() {
    _loaded = widget.doc;
    final source = widget.doc;
    if (source == null || source.trim().isEmpty) {
      _editor = null;
      return;
    }
    final editor = createHinataEditor();
    try {
      editor.setEditorState(editor.parseEditorStateFromString(source));
      _editor = editor;
    } on Object {
      // Unreadable: show nothing rather than an exception box in the middle of
      // an otherwise fine page.
      _editor = null;
      return;
    }
    final notify = widget.onDocument;
    if (notify != null) {
      // After the frame: the caller almost always calls setState from here, and
      // this runs during initState and didUpdateWidget.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) notify(editor);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final editor = _editor;
    if (editor == null) return const SizedBox.shrink();
    return LexicalDocument(
      editor: editor,
      theme: hinataLexicalTheme(
        fontSize: widget.fontSize,
        blockSpacing: widget.blockSpacing,
        extraLayouts: hinataBlockLayouts(),
      ),
      padding: widget.padding,
      scrollable: widget.scrollable,
      registry: widget.registry,
      decoratorBuilders: hinataDecoratorBuilders(
        editor: editor,
        onTapSmartLink: widget.onTapSmartLink,
        chipBuilder: widget.chipBuilder ?? defaultSmartLinkChip,
      ),
      interaction: widget.onTapLink == null
          ? null
          : LexicalInteraction(
              types: hinataInteractiveNodeTypes,
              onTap: (hit) {
                // The hit carries the node's serialized fields, which is where
                // a link's url lives — no read scope needed to get at it.
                final url = hit.json['url'];
                if (url is String && url.isNotEmpty) widget.onTapLink!(url);
              },
            ),
    );
  }
}
