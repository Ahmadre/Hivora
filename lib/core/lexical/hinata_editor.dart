/// The editable surface: a Lexical field with hinata's toolbar around it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../i18n/i18n.dart';
import '../theme/app_colors.dart';
import 'hinata_document.dart';
import 'hinata_editing.dart';
import 'hinata_editor_controller.dart';
import 'hinata_lexical.dart';
import 'hinata_theme.dart';

/// One toolbar button: what it does, and whether it currently looks pressed.
class _Action {
  const _Action(this.icon, this.tooltipKey, this.run, {this.active});

  final IconData icon;
  final String tooltipKey;
  final void Function(LexicalEditor editor) run;

  /// Reads the pressed state inside an editor read, or null for an action that
  /// has no state (undo, insert a divider).
  final bool Function()? active;
}

/// A rich-text editor over a stored Lexical document.
///
/// Replaces the markdown textarea plus its syntax-inserting toolbar. The
/// difference that matters is not the buttons: a real document model means
/// `**bold with `code`**` and a link with emphasized text work, which the flat
/// regex the app rendered with could not express at all.
///
/// The host owns the [controller] and therefore owns save and cancel, exactly
/// as it owned the `TextEditingController` before.
class HinataEditor extends StatefulWidget {
  const HinataEditor({
    required this.controller,
    super.key,
    this.fontSize = 15,
    this.minHeight = 180,
    this.autofocus = false,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 12),
    this.showToolbar = true,
    this.onTapSmartLink,
    this.chipBuilder,
    this.trailing,
  });

  /// The document being edited.
  final HinataEditorController controller;

  /// Body size everything else scales from.
  final double fontSize;

  /// Smallest height the writing area takes, so an empty editor is still a
  /// target worth tapping.
  final double minHeight;

  final bool autofocus;
  final EdgeInsetsGeometry padding;

  /// Whether to show the formatting toolbar. Off for the comment composer,
  /// which stays a light single-line surface until it is expanded.
  final bool showToolbar;

  /// What tapping a smart-link chip does while editing.
  final SmartLinkTapped? onTapSmartLink;

  /// Draws a chip once its target is resolved.
  final SmartLinkChipBuilder? chipBuilder;

  /// Extra buttons at the end of the toolbar — image upload, mention picker,
  /// whatever the host surface adds.
  final List<Widget>? trailing;

  @override
  State<HinataEditor> createState() => HinataEditorState();
}

/// Exposed so a host can focus the editor from a toolbar of its own.
class HinataEditorState extends State<HinataEditor> {
  final FocusNode _focus = FocusNode();
  final HistoryState _history = HistoryState();

  LexicalEditor get _editor => widget.controller.editor;

  @override
  void initState() {
    super.initState();
    // The toolbar's pressed states follow the caret, so it has to rebuild when
    // the selection moves — not only when the document changes.
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _focus.dispose();
    super.dispose();
  }

  /// Rebuilds the toolbar after the editor commits.
  ///
  /// Deferred when a commit lands mid-frame, which the field's own first build
  /// does: marking this element dirty while the tree is being built trips
  /// Flutter's `!_dirty` assertion and leaves the editor half-mounted. The
  /// toolbar's pressed states are a frame behind in that one case, which nobody
  /// can see, and correct in the case that matters — the user pressing a key.
  void _onChanged() {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  /// Gives the editor focus.
  void focus() => _focus.requestFocus();

  // --- actions --------------------------------------------------------------

  void _format(TextFormat format) {
    _editor.dispatchCommand(formatTextCommand, format);
    _focus.requestFocus();
  }

  /// Whether the button should look pressed.
  ///
  /// Two cases, and they are genuinely different: over a range, the format is
  /// "on" only when *every* selected text node has it — the same rule
  /// `formatText` uses to decide whether a press turns it on or off. At a bare
  /// caret there are no nodes yet, so the answer is the selection's pending
  /// format, which is what the next typed character will carry.
  bool _hasFormat(TextFormat format) => _editor.editorState.read(() {
    final selection = $getSelection();
    if (selection is! RangeSelection) return false;
    final nodes = selection.getNodes().whereType<TextNode>().toList();
    if (nodes.isEmpty) return (selection.format & format.bit) != 0;
    return nodes.every((node) => node.hasFormat(format));
  });

  void _block(BlockKind kind, {CalloutKind callout = CalloutKind.info}) {
    _editor.update(() => $setBlockKind(kind, callout: callout));
    _focus.requestFocus();
  }

  bool _isBlock(BlockKind kind) =>
      _editor.editorState.read(() => $blockKindIs(kind));

  List<List<_Action>> get _groups => [
    [
      _Action(
        LucideIcons.bold,
        'md.bold',
        (_) => _format(TextFormat.bold),
        active: () => _hasFormat(TextFormat.bold),
      ),
      _Action(
        LucideIcons.italic,
        'md.italic',
        (_) => _format(TextFormat.italic),
        active: () => _hasFormat(TextFormat.italic),
      ),
      _Action(
        LucideIcons.strikethrough,
        'md.strikethrough',
        (_) => _format(TextFormat.strikethrough),
        active: () => _hasFormat(TextFormat.strikethrough),
      ),
      _Action(
        LucideIcons.code,
        'md.inlineCode',
        (_) => _format(TextFormat.code),
        active: () => _hasFormat(TextFormat.code),
      ),
    ],
    [
      _Action(
        LucideIcons.heading1,
        'md.heading1',
        (_) => _block(BlockKind.heading1),
        active: () => _isBlock(BlockKind.heading1),
      ),
      _Action(
        LucideIcons.heading2,
        'md.heading2',
        (_) => _block(BlockKind.heading2),
        active: () => _isBlock(BlockKind.heading2),
      ),
      _Action(
        LucideIcons.heading3,
        'md.heading3',
        (_) => _block(BlockKind.heading3),
        active: () => _isBlock(BlockKind.heading3),
      ),
    ],
    [
      _Action(
        LucideIcons.list,
        'md.bulletList',
        (_) => _block(BlockKind.bulletList),
        active: () => _isBlock(BlockKind.bulletList),
      ),
      _Action(
        LucideIcons.listOrdered,
        'md.numberedList',
        (_) => _block(BlockKind.numberList),
        active: () => _isBlock(BlockKind.numberList),
      ),
      _Action(
        LucideIcons.listChecks,
        'md.taskList',
        (_) => _block(BlockKind.checkList),
        active: () => _isBlock(BlockKind.checkList),
      ),
    ],
    [
      _Action(
        LucideIcons.quote,
        'md.quote',
        (_) => _block(BlockKind.quote),
        active: () => _isBlock(BlockKind.quote),
      ),
      _Action(
        LucideIcons.squareCode,
        'md.codeBlock',
        (_) => _block(BlockKind.code),
        active: () => _isBlock(BlockKind.code),
      ),
      _Action(
        LucideIcons.info,
        'md.calloutInfo',
        (_) => _block(BlockKind.callout),
        active: () => _isBlock(BlockKind.callout),
      ),
      _Action(LucideIcons.minus, 'md.divider', (editor) {
        editor.update($insertDivider);
        _focus.requestFocus();
      }),
    ],
  ];

  // --- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (widget.showToolbar) _toolbar(context),
      ConstrainedBox(
        constraints: BoxConstraints(minHeight: widget.minHeight),
        child: LexicalEditorField(
          editor: _editor,
          baseTextStyle: TextStyle(fontSize: widget.fontSize),
          theme: hinataLexicalTheme(
            fontSize: widget.fontSize,
            extraLayouts: hinataBlockLayouts(),
          ),
          focusNode: _focus,
          autofocus: widget.autofocus,
          padding: widget.padding,
          // The host is a form or a sheet that scrolls; a second scroll view
          // here would trap the gesture and strand the save bar off-screen.
          scrollable: false,
          history: _history,
          decoratorBuilders: hinataDecoratorBuilders(
            editor: _editor,
            onTapSmartLink: widget.onTapSmartLink,
            chipBuilder: widget.chipBuilder,
          ),
        ),
      ),
    ],
  );

  Widget _toolbar(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: SizedBox(
      height: 34,
      // The toolbar scrolls rather than wrapping: on a phone the full set does
      // not fit, and a wrapped second row pushes the writing area off-screen
      // exactly when the keyboard is already taking half of it.
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        children: [
          for (final (index, group) in _groups.indexed) ...[
            if (index > 0) _separator(),
            for (final action in group) _button(context, action),
          ],
          if (widget.trailing != null) ...[_separator(), ...widget.trailing!],
        ],
      ),
    ),
  );

  Widget _separator() => Container(
    width: 1,
    height: 18,
    margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    color: AppColors.hairline,
  );

  Widget _button(BuildContext context, _Action action) {
    final active = action.active?.call() ?? false;
    return Tooltip(
      message: context.t(action.tooltipKey),
      child: Semantics(
        button: true,
        selected: action.active == null ? null : active,
        label: context.t(action.tooltipKey),
        child: InkWell(
          onTap: () => action.run(_editor),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active
                  ? AppColors.accent.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              action.icon,
              size: 16,
              color: active ? AppColors.accent : AppColors.inkSoft,
            ),
          ),
        ),
      ),
    );
  }
}
