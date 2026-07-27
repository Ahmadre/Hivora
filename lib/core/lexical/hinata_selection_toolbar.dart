/// The quick actions that follow the selection, and the link editor they open.
///
/// This replaces the platform's own cut/copy/paste menu, which the editor turns
/// off: two menus on one gesture, one over the other, is what the writer got
/// before. What is here instead is the thing a writer actually reaches for
/// mid-sentence — the formats, and the link — on hinata's glass, right above
/// the words it acts on.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../i18n/i18n.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_panel.dart';

/// Wraps an editable and floats hinata's quick actions over its selection.
///
/// Held by a [GlobalKey] so the editor's own toolbar can push it into link mode
/// — the link button belongs in both places, and it must not open two different
/// things depending on which one was pressed.
class HinataSelectionToolbar extends StatefulWidget {
  const HinataSelectionToolbar({
    required this.editor,
    required this.editableKey,
    required this.child,
    super.key,
  });

  final LexicalEditor editor;

  /// The key on the editable, for reaching the selection's geometry.
  final GlobalKey<LexicalEditableState> editableKey;

  final Widget child;

  @override
  State<HinataSelectionToolbar> createState() => HinataSelectionToolbarState();
}

class HinataSelectionToolbarState extends State<HinataSelectionToolbar> {
  OverlayEntry? _entry;
  Unsubscribe? _unsubscribe;
  bool _editingLink = false;

  @override
  void initState() {
    super.initState();
    _unsubscribe = widget.editor.registerUpdateListener((_) => _schedule());
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  /// Opens the inline link editor over the current selection.
  ///
  /// The editor's toolbar calls this; nothing else should have to know that the
  /// address field lives in an overlay rather than in a dialog.
  void editLink() {
    setState(() => _editingLink = true);
    _sync();
    _entry?.markNeedsBuild();
  }

  // --- geometry ---------------------------------------------------------

  /// Geometry only exists after layout, and a commit can land *during* a build,
  /// so the overlay is always updated at the end of the frame.
  void _schedule() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync());

  /// The rectangle the toolbar points at, or null when it should not be shown.
  ///
  /// Read afresh every time rather than cached: blocks register their render
  /// objects in a post-frame callback, so the first answer after a commit can be
  /// a frame stale — and a toolbar 80 pixels below the words it belongs to is
  /// the visible result.
  Rect? get _anchor {
    final editable = widget.editableKey.currentState;
    if (editable == null) return null;
    final rects = editable.selectionRects;
    if (rects.isNotEmpty) {
      return rects.reduce((a, b) => a.expandToInclude(b));
    }
    // A caret with no range: only the link editor wants the toolbar then —
    // quick actions over nothing are noise the writer has to dismiss.
    if (!_editingLink) return null;
    final caret = editable.caretRect;
    if (caret != null) return caret;
    // Pressed with the editor never focused, so there is no caret to point at.
    // The field opens over the top of the writing area rather than not at all:
    // a button that silently does nothing is the worse of the two.
    final bounds = editable.editableBounds;
    return bounds == null ? null : Rect.fromLTWH(bounds.left, bounds.top, 0, 0);
  }

  void _sync() {
    if (!mounted) return;
    if (_anchor == null) {
      _hide();
      return;
    }
    if (_entry == null) {
      _entry = OverlayEntry(builder: _buildOverlay);
      Overlay.of(context).insert(_entry!);
    } else {
      // The selection can move without changing whether there is one, and the
      // active-format highlighting changes with every commit.
      _entry!.markNeedsBuild();
    }
  }

  void _hide() {
    if (_entry == null) return;
    _entry!.remove();
    _entry = null;
    if (_editingLink && mounted) setState(() => _editingLink = false);
  }

  // --- reading the selection --------------------------------------------

  /// Whether every text node in the selection carries [format].
  ///
  /// The whole selection, not the first node: a button that lights up because
  /// the selection *starts* in bold lies about what a second press will do.
  bool _isActive(TextFormat format) => widget.editor.editorState.read(() {
    final selection = $getSelection();
    if (selection is! RangeSelection) return false;
    if (selection.isCollapsed) return selection.format & format.bit != 0;
    final texts = selection.getNodes().whereType<TextNode>();
    return texts.isNotEmpty && texts.every((node) => node.hasFormat(format));
  });

  String? get _currentLink =>
      widget.editor.editorState.read(() => $getLinkAtSelection()?.url);

  // --- acting on it -----------------------------------------------------

  void _format(TextFormat format) {
    widget.editor.dispatchCommand(formatTextCommand, format);
    _entry?.markNeedsBuild();
  }

  void _applyLink(String? url) {
    if (url != null && url.isNotEmpty && _needsOwnText) {
      // No words to wrap: linking a caret would be a no-op and the writer would
      // watch their address disappear. The address becomes the link's own text,
      // which is what every editor does with a paste onto nothing.
      widget.editor.update(() {
        var selection = $getSelection();
        if (selection is! RangeSelection) {
          // Never focused, so there is no caret. The end of the document is
          // where typing would have gone.
          $getRoot().selectEnd();
          selection = $getSelection();
        }
        if (selection is! RangeSelection) return;
        selection.insertNodes([
          $createLinkNode(url)..append($createTextNode(url)),
        ]);
      });
    } else {
      widget.editor.dispatchCommand(toggleLinkCommand, url);
    }
    if (mounted) setState(() => _editingLink = false);
    _entry?.markNeedsBuild();
    // The address field took the focus; give it back so typing continues.
    widget.editableKey.currentState?.requestFocus();
  }

  /// Whether the link has to bring its own text: nothing is selected, and the
  /// caret is not already inside a link to re-point.
  bool get _needsOwnText => widget.editor.editorState.read(() {
    final selection = $getSelection();
    if (selection is! RangeSelection) return true;
    return selection.isCollapsed && $getLinkAtSelection() == null;
  });

  void _copy() {
    widget.editableKey.currentState?.copy();
    _hide();
  }

  void _paste() {
    widget.editableKey.currentState?.paste();
    _hide();
  }

  // --- chrome -----------------------------------------------------------

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        // A toolbar that stays put while the text scrolls out from under it is
        // worse than no toolbar at all.
        onNotification: (_) {
          _sync();
          return false;
        },
        child: widget.child,
      );

  Widget _buildOverlay(BuildContext context) {
    final anchor = _anchor;
    if (anchor == null) return const SizedBox.shrink();
    return Positioned.fill(
      // Centring on the selection with a fixed offset is not enough: a word
      // near the left edge puts half the toolbar off-screen, where it is
      // clipped and unreachable. The position is computed from the toolbar's
      // measured size, which is what this delegate is for.
      child: CustomSingleChildLayout(
        delegate: _ToolbarLayout(anchor),
        child: GlassFloatingSurface(
          radius: 16,
          child: _editingLink
              ? _LinkField(
                  initial: _currentLink ?? '',
                  hasLink: _currentLink != null,
                  onApply: _applyLink,
                  onCancel: () {
                    setState(() => _editingLink = false);
                    _sync();
                    _entry?.markNeedsBuild();
                    widget.editableKey.currentState?.requestFocus();
                  },
                )
              : _actions(context),
        ),
      ),
    );
  }

  static const Map<TextFormat, (IconData, String)> _formatButtons = {
    TextFormat.bold: (LucideIcons.bold, 'md.bold'),
    TextFormat.italic: (LucideIcons.italic, 'md.italic'),
    TextFormat.underline: (LucideIcons.underline, 'md.underline'),
    TextFormat.strikethrough: (LucideIcons.strikethrough, 'md.strikethrough'),
    TextFormat.code: (LucideIcons.code, 'md.inlineCode'),
  };

  Widget _actions(BuildContext context) {
    final linked = _currentLink != null;
    // The buttons must not take focus: the editor would lose the selection they
    // are about to act on, and on a phone the keyboard would drop.
    return ExcludeFocus(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in _formatButtons.entries)
              _OverlayButton(
                icon: entry.value.$1,
                tooltipKey: entry.value.$2,
                active: _isActive(entry.key),
                onTap: () => _format(entry.key),
              ),
            const _OverlayDivider(),
            _OverlayButton(
              icon: LucideIcons.link,
              tooltipKey: 'md.link',
              active: linked,
              onTap: editLink,
            ),
            if (linked)
              _OverlayButton(
                icon: LucideIcons.unlink,
                tooltipKey: 'md.linkRemove',
                onTap: () => _applyLink(null),
              ),
            const _OverlayDivider(),
            // The platform menu is off, so the clipboard has to live somewhere.
            // Over a selection is where both of these mean something: copy
            // takes it, paste replaces it.
            _OverlayButton(
              icon: LucideIcons.copy,
              tooltipKey: 'common.copy',
              onTap: _copy,
            ),
            _OverlayButton(
              icon: LucideIcons.clipboardPaste,
              tooltipKey: 'common.paste',
              onTap: _paste,
            ),
          ],
        ),
      ),
    );
  }
}

/// One round button on the floating glass.
class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.icon,
    required this.tooltipKey,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltipKey;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final label = context.t(tooltipKey);
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active
                  ? AppColors.accent.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 16,
              color: active ? AppColors.accentStrong : AppColors.inkSoft,
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayDivider extends StatelessWidget {
  const _OverlayDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 18,
    margin: const EdgeInsets.symmetric(horizontal: 5),
    color: AppColors.hairline,
  );
}

/// The address field, right over the text being linked.
///
/// A row rather than a dialog: the writer can see the words they are linking
/// while they type the address, and confirming is the check beside the field
/// rather than a trip to a button in the corner of a modal.
class _LinkField extends StatefulWidget {
  const _LinkField({
    required this.initial,
    required this.hasLink,
    required this.onApply,
    required this.onCancel,
  });

  final String initial;

  /// Whether there is already a link, which turns the address into an edit.
  final bool hasLink;

  /// Called with the address, or null to unlink. Never called on cancel.
  final ValueChanged<String?> onApply;

  final VoidCallback onCancel;

  @override
  State<_LinkField> createState() => _LinkFieldState();
}

/// "Take the address as typed" — Enter, from wherever it came.
class _ApplyLinkIntent extends Intent {
  const _ApplyLinkIntent();
}

class _LinkFieldState extends State<_LinkField> {
  late final TextEditingController _url = TextEditingController(
    text: widget.initial,
  );
  bool _unsafe = false;

  /// Whether the address has already been applied.
  ///
  /// Enter reaches this field two ways — as the text input's "done" action and
  /// as a raw key event — and which one arrives depends on the platform and on
  /// whether the keyboard is a real one. Both are handled, so both can fire;
  /// applying twice would toggle the link straight back off.
  bool _applied = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    if (_applied) return;
    final url = _url.text.trim();
    if (url.isEmpty) {
      // An emptied address on an existing link means "remove it", which is the
      // only reading that does not silently discard the writer's intent.
      _applied = true;
      widget.onApply(widget.hasLink ? null : '');
      return;
    }
    // The model stores a URL verbatim so documents round-trip; refusing an
    // unsafe one is the application's job, at the point it is created. A
    // `javascript:` address in a stored document is XSS waiting for a tap.
    if (!isSafeUrl(url)) {
      // Not applied: the writer has to be able to correct it and press again.
      setState(() => _unsafe = true);
      return;
    }
    _applied = true;
    widget.onApply(url);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.link, size: 15, color: AppColors.inkFaint),
            const SizedBox(width: 8),
            // Flexible *and* capped: the overlay is sized by its content, so
            // an uncapped field would grow to the screen — and a fixed one
            // overflows the 320 px phone the row still has to fit on.
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Shortcuts(
                  // Enter is bound here as well as through `onSubmitted`.
                  // Which of the two fires depends on the platform and on
                  // whether the key came from a real keyboard or the input
                  // method — and on the web it is the key event, where the
                  // action never arrived and pressing Enter did nothing at all.
                  shortcuts: const {
                    SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
                    SingleActivator(LogicalKeyboardKey.enter):
                        _ApplyLinkIntent(),
                    SingleActivator(LogicalKeyboardKey.numpadEnter):
                        _ApplyLinkIntent(),
                  },
                  child: Actions(
                    actions: {
                      DismissIntent: CallbackAction<DismissIntent>(
                        onInvoke: (_) {
                          widget.onCancel();
                          return null;
                        },
                      ),
                      _ApplyLinkIntent: CallbackAction<_ApplyLinkIntent>(
                        onInvoke: (_) {
                          _submit();
                          return null;
                        },
                      ),
                    },
                    child: TextField(
                      controller: _url,
                      autofocus: true,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      onChanged: (_) {
                        if (_unsafe) setState(() => _unsafe = false);
                      },
                      style: TextStyle(fontSize: 13.5, color: AppColors.ink),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        hintText: 'https://',
                        hintStyle: TextStyle(
                          fontSize: 13.5,
                          color: AppColors.inkFaint,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            _OverlayButton(
              icon: LucideIcons.check,
              tooltipKey: 'md.linkAdd',
              active: true,
              onTap: _submit,
            ),
            _OverlayButton(
              icon: LucideIcons.x,
              tooltipKey: 'common.cancel',
              onTap: widget.onCancel,
            ),
          ],
        ),
        if (_unsafe)
          Padding(
            padding: const EdgeInsets.only(left: 23, bottom: 2),
            child: Text(
              context.t('md.linkUnsafe'),
              style: const TextStyle(fontSize: 11.5, color: AppColors.danger),
            ),
          ),
      ],
    ),
  );
}

/// Places the toolbar over [anchor] without letting it leave the screen.
class _ToolbarLayout extends SingleChildLayoutDelegate {
  const _ToolbarLayout(this.anchor);

  /// The selection, in the overlay's coordinates.
  final Rect anchor;

  static const double _margin = 8;
  static const double _gap = 10;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen().copyWith(
        maxWidth: (constraints.maxWidth - _margin * 2).clamp(
          0,
          double.infinity,
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = (anchor.center.dx - childSize.width / 2).clamp(
      _margin,
      // A toolbar wider than the screen would produce an empty range; the max
      // is pinned to at least the margin so the clamp stays valid.
      (size.width - childSize.width - _margin).clamp(_margin, double.infinity),
    );
    // Above the selection when there is room, below it otherwise — a toolbar
    // covering the text it acts on is worse than one on the wrong side.
    final above = anchor.top - childSize.height - _gap >= _margin;
    final y = above
        ? anchor.top - childSize.height - _gap
        : (anchor.bottom + _gap).clamp(
            _margin,
            (size.height - childSize.height - _margin).clamp(
              _margin,
              double.infinity,
            ),
          );
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_ToolbarLayout oldDelegate) =>
      oldDelegate.anchor != anchor;
}
