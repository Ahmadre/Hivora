/// Which language the code block under the caret is written in.
///
/// Highlighting is neither a widget nor a command — it is a transform over the
/// document — so setting the language is the only thing this file does. The
/// runs re-colour themselves on the next commit.
library;

import 'package:flutter/material.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../i18n/i18n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_popup_menu.dart';

/// The language of the code block the caret is in, and whether it is in one.
///
/// Read as plain values: the node must not escape the read scope.
({String? language, bool inCode}) $codeLanguageAtSelection() {
  final selection = $getSelection();
  final node = switch (selection) {
    final RangeSelection range => range.focus.getNode(),
    final NodeSelection nodes => nodes.getNodes().firstOrNull,
    _ => null,
  };
  for (var current = node; current != null; current = current.getParent()) {
    if (current is CodeNode) {
      return (language: current.language, inCode: true);
    }
  }
  return (language: null, inCode: false);
}

/// A strip naming the caret's code block, shown only while it is in one.
///
/// Nothing in the toolbar could say what language a block is: the toolbar acts
/// on a selection, and "which language" is a property of the block the caret
/// happens to be inside. So it is a context bar that appears with the block and
/// leaves with it, which is also why it costs no horizontal room the rest of
/// the time.
class HinataCodeBar extends StatelessWidget {
  const HinataCodeBar({
    required this.editor,
    required this.onDone,
    this.onMenu,
    super.key,
  });

  final LexicalEditor editor;

  /// Called after a language was chosen, so the host can take focus back.
  final VoidCallback onDone;

  /// Called while the language menu is up. Same reason as the toolbar's
  /// block picker: the selection overlay floats over the same words.
  final ValueChanged<bool>? onMenu;

  void _setLanguage(String? id) {
    editor.update(() {
      final node = ($getSelection() as RangeSelection?)?.focus.getNode();
      for (var current = node; current != null; current = current.getParent()) {
        if (current is CodeNode) {
          current.setLanguage(id);
          return;
        }
      }
    });
    onDone();
  }

  @override
  Widget build(BuildContext context) {
    final state = editor.editorState.read($codeLanguageAtSelection);
    if (!state.inCode) return const SizedBox.shrink();

    return ExcludeFocus(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Row(
          children: [
            const Icon(
              LucideIcons.squareCode,
              size: 14,
              color: AppColors.accent,
            ),
            const SizedBox(width: 8),
            Text(
              context.t('md.codeBlock'),
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: AppColors.accentStrong,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: _LanguageTrigger(
                current: state.language,
                onSelected: _setLanguage,
                onMenu: onMenu,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one-line trigger and the glass dropdown it opens at its own edge.
///
/// A popover anchored to the trigger rather than a modal in the middle of the
/// screen: this is a dropdown on a strip inside the editor, and pulling the
/// whole app behind a scrim to answer "which language" is far more ceremony
/// than the question deserves.
class _LanguageTrigger extends StatelessWidget {
  const _LanguageTrigger({
    required this.current,
    required this.onSelected,
    this.onMenu,
  });

  final String? current;
  final ValueChanged<String?> onSelected;
  final ValueChanged<bool>? onMenu;

  /// Every language the highlighter knows, plus "no language" at the top.
  ///
  /// Sorted by name rather than by registration order: a picker is read, and a
  /// reader looks a language up alphabetically.
  static final List<String> _languages = [
    for (final language in builtInCodeLanguages) language.id,
  ]..sort();

  @override
  Widget build(BuildContext context) {
    final chosen = current != null && current!.isNotEmpty;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: GlassPopupMenu<String>(
        width: 220,
        onOpenChanged: onMenu,
        value: current ?? '',
        onSelected: (id) => onSelected(id.isEmpty ? null : id),
        items: [
          GlassMenuItem<String>(
            value: '',
            label: context.t('md.codeLanguagePlain'),
          ),
          for (final id in _languages)
            GlassMenuItem<String>(value: id, label: id),
        ],
        child: Tooltip(
          message: context.t('md.codeLanguage'),
          child: Container(
            height: 26,
            padding: const EdgeInsetsDirectional.only(start: 10, end: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(color: AppColors.hairline),
              color: AppColors.surface,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    // A block with no language is not highlighted at all, and the
                    // trigger should say so rather than pretend one is chosen.
                    chosen ? current! : context.t('md.codeLanguagePlain'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 12,
                      color: chosen ? AppColors.ink : AppColors.inkFaint,
                    ),
                  ),
                ),
                Icon(
                  LucideIcons.chevronDown,
                  size: 14,
                  color: AppColors.inkFaint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
