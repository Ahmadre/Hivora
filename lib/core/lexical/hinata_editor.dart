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
import 'hinata_link_dialog.dart';
import 'hinata_theme.dart';

/// One toolbar button: what it does, and whether it currently looks pressed.
class _Action {
  const _Action(
    this.icon,
    this.tooltipKey,
    this.run, {
    this.active,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltipKey;
  final VoidCallback run;

  /// Whether the button looks pressed, or null for an action that has no state
  /// (undo, insert a divider).
  final bool? active;

  /// Whether the button does anything right now. Undo with nothing to undo is
  /// the only case, and a button that looks live and does nothing is worse
  /// than one that looks spent.
  final bool enabled;
}

/// Everything the toolbar needs to draw itself, read in one go.
///
/// The toolbar rebuilds on every editor commit — every keystroke — and each
/// button used to open its own `editorState.read()` to answer "am I pressed".
/// Thirteen round trips a frame for one question the editor can answer once.
class _ToolbarState {
  const _ToolbarState({
    required this.formats,
    required this.block,
    required this.callout,
    required this.linked,
  });

  const _ToolbarState.empty()
    : formats = 0,
      block = null,
      callout = null,
      linked = false;

  /// Bitmask of the formats every selected text node carries.
  final int formats;

  /// The block kind under the caret, or null when it is mixed or unmodelled.
  final BlockKind? block;

  /// The callout flavour under the caret, or null.
  final CalloutKind? callout;

  /// Whether the selection sits inside a link.
  final bool linked;

  bool has(TextFormat format) => (formats & format.bit) != 0;
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
  void didUpdateWidget(HinataEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Every host holds its controller in a `late final` today, so this never
    // fires. The day one of them swaps it, the toolbar would silently stop
    // following the caret and the discarded controller would keep a live
    // `setState` closure — a trap, not a bug, and cheaper to close than to find.
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
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

  /// Everything the toolbar draws itself from, in a single read.
  ///
  /// The format rule has two cases and they are genuinely different: over a
  /// range, a format is "on" only when *every* selected text node has it — the
  /// same rule `formatText` uses to decide whether a press turns it on or off.
  /// At a bare caret there are no nodes yet, so the answer is the selection's
  /// pending format, which is what the next typed character will carry.
  _ToolbarState _readToolbar() => _editor.editorState.read(() {
    final selection = $getSelection();
    if (selection is! RangeSelection) return const _ToolbarState.empty();

    final nodes = selection.getNodes().whereType<TextNode>().toList();
    var formats = 0;
    for (final format in _formatButtons) {
      final on = nodes.isEmpty
          ? (selection.format & format.bit) != 0
          : nodes.every((node) => node.hasFormat(format));
      if (on) formats |= format.bit;
    }

    return _ToolbarState(
      formats: formats,
      block: $selectedBlockKind(),
      callout: $selectedCalloutKind(),
      linked: $getLinkAtSelection() != null,
    );
  });

  void _block(BlockKind kind, {CalloutKind callout = CalloutKind.info}) {
    _editor.update(() => $setBlockKind(kind, callout: callout));
    _focus.requestFocus();
  }

  void _undo() {
    _editor.dispatchCommand(undoCommand, null);
    _focus.requestFocus();
  }

  void _redo() {
    _editor.dispatchCommand(redoCommand, null);
    _focus.requestFocus();
  }

  /// Adds, edits or removes the link over the selection.
  ///
  /// Opens a glass dialog rather than an inline field: the address is a whole
  /// second thing to type, and a toolbar that grows a text input mid-row is
  /// the shape this app explicitly does not use.
  Future<void> _editLink() async {
    final current = _editor.editorState.read(() => $getLinkAtSelection()?.url);
    final url = await showGlassLinkDialog(context, initialUrl: current);
    if (url == null) return;
    _editor.dispatchCommand(toggleLinkCommand, url.isEmpty ? null : url);
    if (mounted) _focus.requestFocus();
  }

  /// The inline formats the toolbar offers, and the only ones it has to read.
  static const List<TextFormat> _formatButtons = [
    TextFormat.bold,
    TextFormat.italic,
    TextFormat.underline,
    TextFormat.strikethrough,
    TextFormat.code,
  ];

  static const Map<TextFormat, (IconData, String)> _formatButtonLook = {
    TextFormat.bold: (LucideIcons.bold, 'md.bold'),
    TextFormat.italic: (LucideIcons.italic, 'md.italic'),
    TextFormat.underline: (LucideIcons.underline, 'md.underline'),
    TextFormat.strikethrough: (LucideIcons.strikethrough, 'md.strikethrough'),
    TextFormat.code: (LucideIcons.code, 'md.inlineCode'),
  };

  /// The callout flavours, in the order they read as a scale: neutral, then
  /// louder, then quieter.
  static const Map<CalloutKind, (IconData, String)> _calloutButtons = {
    CalloutKind.info: (LucideIcons.info, 'md.calloutInfo'),
    CalloutKind.warn: (LucideIcons.triangleAlert, 'md.calloutWarn'),
    CalloutKind.note: (LucideIcons.notebookPen, 'md.calloutNote'),
    CalloutKind.tip: (LucideIcons.lightbulb, 'md.calloutTip'),
  };

  /// The toolbar, left to right.
  ///
  /// Ordered by how often a writer reaches for it, because the row scrolls on a
  /// phone and everything past the fold costs a swipe: formatting, then block
  /// shape, then the occasional ones. Undo and redo sit at the far end on
  /// purpose — every platform already has a keyboard shortcut and a gesture for
  /// them, and putting them first would push bold off a narrow screen.
  List<List<_Action>> _groups(_ToolbarState state) => [
    [
      for (final format in _formatButtons)
        _Action(
          _formatButtonLook[format]!.$1,
          _formatButtonLook[format]!.$2,
          () => _format(format),
          active: state.has(format),
        ),
      _Action(
        LucideIcons.link,
        state.linked ? 'md.linkRemove' : 'md.link',
        _editLink,
        active: state.linked,
      ),
    ],
    [
      _Action(
        LucideIcons.pilcrow,
        'md.paragraph',
        () => _block(BlockKind.paragraph),
        active: state.block == BlockKind.paragraph,
      ),
      _Action(
        LucideIcons.heading1,
        'md.heading1',
        () => _block(BlockKind.heading1),
        active: state.block == BlockKind.heading1,
      ),
      _Action(
        LucideIcons.heading2,
        'md.heading2',
        () => _block(BlockKind.heading2),
        active: state.block == BlockKind.heading2,
      ),
      _Action(
        LucideIcons.heading3,
        'md.heading3',
        () => _block(BlockKind.heading3),
        active: state.block == BlockKind.heading3,
      ),
    ],
    [
      _Action(
        LucideIcons.list,
        'md.bulletList',
        () => _block(BlockKind.bulletList),
        active: state.block == BlockKind.bulletList,
      ),
      _Action(
        LucideIcons.listOrdered,
        'md.numberedList',
        () => _block(BlockKind.numberList),
        active: state.block == BlockKind.numberList,
      ),
      _Action(
        LucideIcons.listChecks,
        'md.taskList',
        () => _block(BlockKind.checkList),
        active: state.block == BlockKind.checkList,
      ),
    ],
    [
      _Action(
        LucideIcons.quote,
        'md.quote',
        () => _block(BlockKind.quote),
        active: state.block == BlockKind.quote,
      ),
      _Action(
        LucideIcons.squareCode,
        'md.codeBlock',
        () => _block(BlockKind.code),
        active: state.block == BlockKind.code,
      ),
      for (final entry in _calloutButtons.entries)
        _Action(
          entry.value.$1,
          entry.value.$2,
          () => _block(BlockKind.callout, callout: entry.key),
          // Pressed only for the flavour that is actually there: four buttons
          // for one block kind, and a writer needs to see which one they are in.
          active:
              state.block == BlockKind.callout && state.callout == entry.key,
        ),
      _Action(LucideIcons.minus, 'md.divider', () {
        _editor.update($insertDivider);
        _focus.requestFocus();
      }),
    ],
    [
      _Action(LucideIcons.undo2, 'md.undo', _undo, enabled: _history.canUndo),
      _Action(LucideIcons.redo2, 'md.redo', _redo, enabled: _history.canRedo),
    ],
  ];

  // --- build ----------------------------------------------------------------

  /// The theme and the decorator map, rebuilt only when their inputs change.
  ///
  /// Same reason as the reader: the renderer drops its whole block cache when
  /// either is not `==` to the previous one, and neither type has an
  /// `operator ==`. The editable surface rebuilds on every keystroke, so this
  /// is where it costs the most.
  LexicalTheme? _themeCache;
  Map<String, DecoratorBuilder>? _decoratorCache;
  ({double fontSize, Brightness brightness})? _styleKey;

  void _refreshStyling() {
    final key = (
      fontSize: widget.fontSize,
      // The neutral tokens are theme-aware getters; a cached theme keeps the
      // light colours after a switch to dark.
      brightness: AppColors.brightness,
    );
    if (_styleKey == key && _themeCache != null && _decoratorCache != null) {
      return;
    }
    _styleKey = key;
    _themeCache = hinataLexicalTheme(
      fontSize: widget.fontSize,
      extraLayouts: hinataBlockLayouts(
        blockSpacing: hinataBlockSpacing(widget.fontSize),
      ),
    );
    _decoratorCache = hinataDecoratorBuilders(
      editor: _editor,
      // This *is* the editable surface: handles and the caption editor belong
      // here, and only here.
      editable: true,
      onTapSmartLink: (kind, targetId) =>
          widget.onTapSmartLink?.call(kind, targetId),
      // The same fallback the reader uses. Without it a `@`-mention shows the
      // raw ObjectId while you write and the person's name once you save.
      chipBuilder: (context, kind, targetId, label) =>
          (widget.chipBuilder ?? defaultSmartLinkChip)(
            context,
            kind,
            targetId,
            label,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _refreshStyling();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showToolbar) _toolbar(context),
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: widget.minHeight),
          child: LexicalEditorField(
            editor: _editor,
            baseTextStyle: TextStyle(fontSize: widget.fontSize),
            theme: _themeCache!,
            focusNode: _focus,
            autofocus: widget.autofocus,
            padding: widget.padding,
            // The host is a form or a sheet that scrolls; a second scroll view
            // here would trap the gesture and strand the save bar off-screen.
            scrollable: false,
            history: _history,
            decoratorBuilders: _decoratorCache!,
          ),
        ),
      ],
    );
  }

  Widget _toolbar(BuildContext context) {
    // One read for the whole row, rather than one per button.
    final state = _readToolbar();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 34,
        // The toolbar scrolls rather than wrapping: on a phone the full set
        // does not fit, and a wrapped second row pushes the writing area
        // off-screen exactly when the keyboard is already taking half of it.
        child: ListView(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          children: [
            for (final (index, group) in _groups(state).indexed) ...[
              if (index > 0) _separator(),
              for (final action in group) _button(context, action),
            ],
            if (widget.trailing != null) ...[_separator(), ...widget.trailing!],
          ],
        ),
      ),
    );
  }

  Widget _separator() => Container(
    width: 1,
    height: 18,
    margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    color: AppColors.hairline,
  );

  Widget _button(BuildContext context, _Action action) {
    final active = action.active ?? false;
    final label = context.t(action.tooltipKey);
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: action.active,
        enabled: action.enabled,
        label: label,
        child: InkWell(
          onTap: action.enabled ? action.run : null,
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
              color: !action.enabled
                  ? AppColors.inkFaint
                  : active
                  ? AppColors.accent
                  : AppColors.inkSoft,
            ),
          ),
        ),
      ),
    );
  }
}
