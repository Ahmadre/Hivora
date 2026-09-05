import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality, LiquidRoundedSuperellipse;

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../search/search_tokens.dart';
import '../data/knowledge_models.dart' show lucideIcon;
import '../knowledge_tokens.dart';
import 'smart_link_resolver.dart';

/// A `TextField` with a Jira/Confluence-style `@`-mention autocomplete.
///
/// Typing `@<query>` (at start-of-word) opens a caret-anchored menu of issues ·
/// articles · people. ↑/↓ move (wrapping), ↵/Tab insert the selected
/// `{{issue:…}}` / `{{doc:…}}` / `{{user:…}}` token + a trailing space, Esc
/// closes. In comment mode ⌘/Ctrl+↵ submits. Used by the article editor source
/// pane and by the issue-comment box.
class MentionField extends StatefulWidget {
  const MentionField({
    super.key,
    required this.controller,
    this.focusNode,
    this.hintText,
    this.minLines,
    this.maxLines,
    this.expands = false,
    this.monospace = false,
    this.autofocus = false,
    this.commentMode = false,
    this.onSubmit,
    this.onTabIndent,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? hintText;
  final int? minLines;
  final int? maxLines;
  final bool expands;
  final bool monospace;
  final bool autofocus;

  /// Comment mode: fewer candidates (6), articles-first, ⌘/Ctrl+↵ submits.
  final bool commentMode;
  final VoidCallback? onSubmit;

  /// When set, a bare Tab (menu closed) inserts two spaces instead of moving
  /// focus — used by the editor source pane.
  final VoidCallback? onTabIndent;

  @override
  State<MentionField> createState() => MentionFieldState();
}

class MentionFieldState extends State<MentionField> {
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  final ScrollController _scroll = ScrollController();
  final GlobalKey _fieldKey = GlobalKey();
  OverlayEntry? _menu;

  List<MentionCandidate> _items = const [];
  int _sel = 0;
  int _from = 0; // index of the '@'
  String _query = '';

  // Async issue candidates (issue detail only): fetched from the backend,
  // debounced, and merged ahead of the synchronous doc/user candidates. Empty
  // in the KB editor, which keeps issues in the synchronous mentions() list.
  List<MentionCandidate> _issueItems = const [];
  Timer? _issueDebounce;
  int _issueReq = 0;
  String? _issueQuery;

  TextEditingController get _ctrl => widget.controller;
  int get _max => widget.commentMode ? 6 : 8;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChanged);
    _focus.onKeyEvent = _onKey;
    _focus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _issueDebounce?.cancel();
    _ctrl.removeListener(_onChanged);
    _focus.removeListener(_onFocusChange);
    _removeMenu();
    _scroll.dispose();
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    // Defer so a row tap (which momentarily blurs the field) can still resolve.
    if (!_focus.hasFocus) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && !_focus.hasFocus) _close();
      });
    }
  }

  // ── query detection ──
  void _onChanged() {
    if (!mounted) return;
    final sel = _ctrl.selection;
    if (!sel.isValid || !sel.isCollapsed) {
      _close();
      return;
    }
    final caret = sel.baseOffset;
    final upto = _ctrl.text.substring(0, caret);
    final m = RegExp(r'(?:^|\s)@([\w-]*)$').firstMatch(upto);
    if (m == null) {
      _close();
      return;
    }
    final query = m.group(1)!;
    _query = query;
    setState(() {
      _from = caret - query.length - 1;
      _items = _build(query);
      _sel = 0;
    });
    _showMenu();
    _scheduleIssueSearch(query);
  }

  /// Fires a debounced backend issue type-ahead (issue detail only) and merges
  /// the results into the menu when they arrive. No-op in the KB editor, which
  /// keeps issues in the synchronous [SmartLinkResolver.mentions] list.
  void _scheduleIssueSearch(String query) {
    final resolver = SmartLinkScope.of(context);
    if (!resolver.asyncIssueMentions) return;
    if (_issueQuery == query) return; // already searching/searched this query
    _issueQuery = query;
    _issueDebounce?.cancel();
    final req = ++_issueReq;
    _issueDebounce = Timer(const Duration(milliseconds: 220), () async {
      List<MentionCandidate> issues;
      try {
        issues = await resolver.searchIssueMentions(query);
      } catch (_) {
        return; // keep the previous issue candidates on error
      }
      // Drop if superseded, unmounted, or the menu closed while we waited.
      if (!mounted || req != _issueReq || _menu == null) return;
      setState(() {
        _issueItems = issues;
        _items = _build(_query);
        if (_sel >= _items.length) _sel = 0;
      });
      _showMenu();
    });
  }

  List<MentionCandidate> _build(String rawQuery) {
    final sync = SmartLinkScope.of(
      context,
    ).mentions(rawQuery, commentMode: widget.commentMode);
    // Backend issue candidates (if any) lead, then the synchronous doc/user
    // candidates — matching the previous issues-first ordering.
    final merged = _issueItems.isEmpty ? sync : [..._issueItems, ...sync];
    return merged.length > _max ? merged.sublist(0, _max) : merged;
  }

  // ── keyboard ──
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (_menu != null && _items.isNotEmpty) {
      if (key == LogicalKeyboardKey.arrowDown) {
        setState(() => _sel = (_sel + 1) % _items.length);
        _menu?.markNeedsBuild();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        setState(() => _sel = (_sel - 1 + _items.length) % _items.length);
        _menu?.markNeedsBuild();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.tab) {
        _pick(_items[_sel]);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        _close();
        return KeyEventResult.handled;
      }
    }
    // Menu closed.
    final mod = HardwareKeyboard.instance;
    if ((key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) &&
        (mod.isMetaPressed || mod.isControlPressed) &&
        widget.onSubmit != null) {
      widget.onSubmit!.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab && widget.onTabIndent != null) {
      _insertAtCaret('  ');
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _insertAtCaret(String text) {
    final sel = _ctrl.selection;
    final caret = sel.isValid ? sel.baseOffset : _ctrl.text.length;
    final next = _ctrl.text.replaceRange(caret, caret, text);
    _ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: caret + text.length),
    );
  }

  void _pick(MentionCandidate it) {
    final token = switch (it.kind) {
      'issue' => '{{issue:${it.id}}}',
      'doc' => '{{doc:${it.id}}}',
      _ => '{{user:${it.id}}}',
    };
    final caret = _ctrl.selection.baseOffset;
    final from = _from.clamp(0, _ctrl.text.length);
    final end = caret.clamp(from, _ctrl.text.length);
    final next = _ctrl.text.replaceRange(from, end, '$token ');
    _ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: from + token.length + 1),
    );
    _close();
  }

  void _close() {
    _issueDebounce?.cancel();
    _issueQuery = null;
    if (_menu != null) _removeMenu();
    if (_items.isNotEmpty || _issueItems.isNotEmpty) {
      setState(() {
        _items = const [];
        _issueItems = const [];
      });
    }
  }

  // ── overlay menu ──
  void _showMenu() {
    if (_items.isEmpty) {
      _removeMenu();
      return;
    }
    _menu ??= OverlayEntry(builder: _menuBuilder);
    if (_menu!.mounted) {
      _menu!.markNeedsBuild();
    } else {
      Overlay.of(context).insert(_menu!);
    }
  }

  void _removeMenu() {
    _menu?.remove();
    _menu = null;
  }

  /// Caret pixel position within the field (mirror-painter technique), then to
  /// overlay-global coordinates.
  Offset _caretGlobal() {
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    if (box == null || !box.hasSize) return Offset.zero;
    const padH = 12.0, padV = 10.0;
    final caret = _ctrl.selection.baseOffset.clamp(0, _ctrl.text.length);
    final painter = TextPainter(
      text: TextSpan(text: _ctrl.text.substring(0, caret), style: _textStyle()),
      // The field's own direction, not a fixed one: this painter mirrors the
      // real field to find the caret, and in a right-to-left language a
      // left-to-right mirror puts the caret at the opposite edge — so the
      // mention popover would open across the field from the word being typed.
      textDirection: Directionality.of(context),
      maxLines: null,
    )..layout(maxWidth: (box.size.width - padH * 2).clamp(0, double.infinity));
    final local = painter.getOffsetForCaret(
      TextPosition(offset: caret),
      Rect.zero,
    );
    final scrollDy = _scroll.hasClients ? _scroll.offset : 0.0;
    final fieldLocal = Offset(local.dx + padH, local.dy + padV - scrollDy + 22);
    return box.localToGlobal(fieldLocal, ancestor: overlayBox);
  }

  Widget _menuBuilder(BuildContext _) {
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final anchor = _caretGlobal();
    const w = 320.0;
    var left = anchor.dx;
    if (left + w > overlayBox.size.width - 12) {
      left = overlayBox.size.width - w - 12;
    }
    if (left < 8) left = 8;
    final media = MediaQuery.maybeOf(context);
    final reduce = media?.disableAnimations ?? false;
    // Flip above the caret line when the menu would overflow the visible area.
    // On mobile the caret sits just above the on-screen keyboard, so the flip
    // decision must exclude the keyboard inset — otherwise the menu opens
    // downward into the region the keyboard covers and is unreachable. The
    // `bottom` offset below still uses the full overlay height, since a flipped
    // menu sits above the caret (above the keyboard) and is anchored to the
    // overlay's true bottom edge.
    final viewportH = overlayBox.size.height;
    final visibleH = viewportH - (media?.viewInsets.bottom ?? 0.0);
    final estHeight = (60 + _items.length * 44).clamp(0, 280).toDouble();
    final flipUp = anchor.dy + estHeight > visibleH - 8;
    final menu = _MentionMenu(
      items: _items,
      selected: _sel,
      reduceMotion: reduce,
      onHover: (i) {
        setState(() => _sel = i);
        _menu?.markNeedsBuild();
      },
      onPick: _pick,
    );
    return Positioned(
      left: left,
      top: flipUp ? null : anchor.dy,
      // anchor.dy already sits ~22 px below the caret line; lift to above it.
      bottom: flipUp ? (viewportH - anchor.dy + 26) : null,
      width: w,
      child: menu,
    );
  }

  TextStyle _textStyle() => TextStyle(
    fontFamily: widget.monospace ? AppTheme.fontMono : AppTheme.fontUi,
    // Comment box: a touch larger and a tighter line so the single-line pill
    // measures ~52 and lines up with the round +/mic/send buttons beside it.
    // The editor source pane (commentMode=false) keeps its roomy 14/1.7.
    fontSize: widget.monospace ? 13.5 : (widget.commentMode ? 15.5 : 14),
    height: widget.commentMode ? 1.3 : 1.7,
    color: AppColors.ink,
  );

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: _fieldKey,
      controller: _ctrl,
      focusNode: _focus,
      scrollController: _scroll,
      autofocus: widget.autofocus,
      minLines: widget.expands ? null : widget.minLines,
      maxLines: widget.expands ? null : widget.maxLines,
      expands: widget.expands,
      keyboardType: TextInputType.multiline,
      textAlignVertical: TextAlignVertical.top,
      style: _textStyle(),
      cursorColor: AppColors.accent,
      decoration: InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        hintText: widget.hintText,
        hintStyle: _textStyle().copyWith(color: AppColors.inkFaint),
      ),
    );
  }
}

class _MentionMenu extends StatelessWidget {
  const _MentionMenu({
    required this.items,
    required this.selected,
    required this.onHover,
    required this.onPick,
    required this.reduceMotion,
  });

  final List<MentionCandidate> items;
  final int selected;
  final ValueChanged<int> onHover;
  final ValueChanged<MentionCandidate> onPick;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final tokens = SearchTokens.of(Theme.of(context).brightness);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card = GlassPanelShadow(
      radius: BorderRadius.circular(KbTokens.radiusCard),
      shadows: tokens.panelShadow,
      child: GlassContainer(
        useOwnLayer: true,
        quality: GlassQuality.premium,
        clipBehavior: Clip.antiAlias,
        shape: const LiquidRoundedSuperellipse(
          borderRadius: KbTokens.radiusCard,
        ),
        settings: liquidGlassPanelSettings(
          glassFill: tokens.glassFill,
          dark: dark,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 5),
                    child: Text(
                      'LINK TO…',
                      style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 0.7,
                        fontWeight: FontWeight.w700,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        context.t('common.noMatches'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.inkFaint,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: items.length,
                      itemBuilder: (context, i) => _row(items[i], i),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return card;
  }

  Widget _row(MentionCandidate it, int i) {
    final isSel = i == selected;
    return MouseRegion(
      onEnter: (_) => onHover(i),
      child: GestureDetector(
        // onTapDown so we fire before the source field loses focus.
        onTapDown: (_) => onPick(it),
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: isSel ? AppColors.accentSoft : null,
            borderRadius: BorderRadius.circular(9),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              _leading(it),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      it.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      it.sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  it.kind.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkFaint,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _leading(MentionCandidate it) {
    if (it.kind == 'user') return AppAvatar(name: it.title, radius: 10);
    if (it.kind == 'doc') {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(KbTokens.radiusChip),
        ),
        alignment: Alignment.center,
        child: Icon(lucideIcon(it.icon), size: 14, color: KbTokens.accent),
      );
    }
    final color = it.issueColor ?? KbTokens.accent;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(KbTokens.radiusChip),
      ),
      alignment: Alignment.center,
      child: Icon(lucideIcon(it.issueType), size: 14, color: color),
    );
  }
}
