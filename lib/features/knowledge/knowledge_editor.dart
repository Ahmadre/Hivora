import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/lexical/hinata_editor.dart';
import '../../core/lexical/hinata_editor_controller.dart';
import 'data/knowledge_models.dart';
import 'data/knowledge_repository.dart';
import 'knowledge_scope.dart';
import 'knowledge_tokens.dart';

/// Result handed back to the shell on Save / Publish.
class EditorResult {
  EditorResult(this.title, this.doc, this.spaceId);
  final String title;

  /// The Lexical document to store.
  final String doc;
  final String spaceId;
}

/// Article editor: title + space picker over a rich-text body.
///
/// There is no preview pane and no Write/Preview switch any more. Those existed
/// because the writer typed markdown and could not see what it would become;
/// the editor now shows the document itself, so a second view of it would show
/// the same thing twice and take half the width doing it.
class KnowledgeEditor extends StatefulWidget {
  const KnowledgeEditor({
    super.key,
    required this.isNew,
    required this.initialTitle,
    required this.initialDoc,
    required this.spaceId,
    required this.onSave,
    required this.onCancel,
  });

  final bool isNew;
  final String initialTitle;
  /// The stored Lexical document, or null for a new article.
  final String? initialDoc;
  final String spaceId;
  final ValueChanged<EditorResult> onSave;
  final VoidCallback onCancel;

  @override
  State<KnowledgeEditor> createState() => _KnowledgeEditorState();
}

class _KnowledgeEditorState extends State<KnowledgeEditor> {
  late final TextEditingController _title = TextEditingController(
    text: widget.initialTitle,
  );
  late final HinataEditorController _body = HinataEditorController(
    doc: widget.initialDoc,
  );
  late String _spaceId = widget.spaceId;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _save() {
    widget.onSave(EditorResult(_title.text.trim(), _body.doc, _spaceId));
    _body.markSaved();
  }

  @override
  Widget build(BuildContext context) {
    final repo = KnowledgeScope.of(context).repo;
    return Builder(
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(KbTokens.radiusCard),
            border: Border.all(color: AppColors.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _head(repo),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                  child: HinataEditor(controller: _body, minHeight: 320),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _head(KnowledgeRepository repo) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 10,
        spacing: 12,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 140, maxWidth: 380),
            child: TextField(
              controller: _title,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              style: const TextStyle(
                fontFamily: AppTheme.fontBrand,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: context.t('knowledge.articleTitleHint'),
                hintStyle: TextStyle(color: AppColors.inkFaint),
              ),
            ),
          ),
          GlassPopupMenu<String>(
            value: _spaceId,
            width: 220,
            onSelected: (v) => setState(() => _spaceId = v),
            items: [
              for (final s in repo.spaces)
                GlassMenuItem(
                  value: s.id,
                  label: s.name,
                  leading: Icon(
                    lucideIcon(s.icon),
                    size: 16,
                    color: KbTokens.accent,
                  ),
                ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(lucideIcon('hash'), size: 15, color: AppColors.inkFaint),
                const SizedBox(width: 6),
                Text(
                  repo.spaceById(_spaceId)?.name ?? '',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  lucideIcon('chevron-down'),
                  size: 15,
                  color: AppColors.inkFaint,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: widget.onCancel,
            child: Text(context.t('common.cancel')),
          ),
          FilledButton.icon(
            onPressed: _save,
            icon: Icon(lucideIcon('check'), size: 16),
            label: Text(
              widget.isNew
                  ? context.t('knowledge.publish')
                  : context.t('common.save'),
            ),
          ),
        ],
      ),
    );
  }

}
