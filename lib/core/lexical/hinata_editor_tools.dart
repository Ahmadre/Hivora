/// The buttons a host hangs off the end of the editor's toolbar.
///
/// Inserting an image and inserting a mention are the two authoring actions
/// that cannot live inside [HinataEditor]: one needs the host's upload
/// repository, the other its `SmartLinkResolver`. Everything else about them —
/// how the button looks, where the node lands — is the same everywhere, so it
/// lives here rather than being re-implemented per surface.
library;

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart'
    show ImageAttributes, insertImageCommand;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/api_client.dart';
import '../i18n/i18n.dart';
import '../repositories/media_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../../features/knowledge/data/knowledge_models.dart' show lucideIcon;
import '../../features/knowledge/markdown/smart_link_resolver.dart';
import '../../features/moderation/content_refused_dialog.dart';
import '../../features/sprint/modals/glass_modal.dart';
import 'hinata_editing.dart';
import 'hinata_editor_controller.dart';
import 'hinata_lexical.dart';

/// The two trailing buttons every rich-text host wants.
///
/// The mention button is dropped when there is no [SmartLinkScope] above this
/// widget: a picker with nothing to pick from is worse than no button.
List<Widget> hinataEditorTools(
  BuildContext context,
  HinataEditorController controller,
) => [
  HinataImageButton(controller: controller),
  if (context.dependOnInheritedWidgetOfExactType<SmartLinkScope>() != null)
    HinataMentionButton(controller: controller),
];

/// A button shaped like the editor toolbar's own.
class HinataToolButton extends StatelessWidget {
  const HinataToolButton({
    required this.icon,
    required this.tooltipKey,
    required this.onTap,
    super.key,
    this.busy = false,
  });

  final IconData icon;
  final String tooltipKey;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final label = context.t(tooltipKey);
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: !busy,
        label: label,
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Center(
              child: busy
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.inkSoft,
                      ),
                    )
                  : Icon(icon, size: 16, color: AppColors.inkSoft),
            ),
          ),
        ),
      ),
    );
  }
}

/// Picks an image, uploads it, and drops it at the caret.
class HinataImageButton extends StatefulWidget {
  const HinataImageButton({required this.controller, super.key});

  final HinataEditorController controller;

  @override
  State<HinataImageButton> createState() => _HinataImageButtonState();
}

class _HinataImageButtonState extends State<HinataImageButton> {
  bool _busy = false;

  Future<void> _pick() async {
    final repo = context.read<MediaRepository>();

    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        // Web has no file path, so the bytes are always needed; harmless
        // everywhere else.
        withData: true,
      );
    } on Object {
      picked = null;
    }
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;

    MultipartFile multipart;
    if (!kIsWeb && (file.path?.isNotEmpty ?? false)) {
      // dio infers the content type from the extension, the same as the
      // attachment path; the server re-validates that it is really an image.
      multipart = await MultipartFile.fromFile(file.path!, filename: file.name);
    } else if (file.bytes != null) {
      multipart = MultipartFile.fromBytes(file.bytes!, filename: file.name);
    } else {
      return;
    }

    setState(() => _busy = true);
    try {
      final url = await repo.uploadMedia(multipart);
      // The package's own insert: it puts the image where the caret is and
      // wraps it in a paragraph when that turns out to be the root, which is
      // the shape every other Lexical client writes.
      widget.controller.editor.dispatchCommand(
        insertImageCommand,
        ImageAttributes(src: url, altText: file.name),
      );
    } on ApiFailure catch (failure) {
      // Nothing is inserted on this path, so the document being written is
      // untouched — only the picked image is refused, and the dialog says why.
      if (mounted && !handleContentRefusal(context, failure)) {
        showGlassErrorToast(context, context.t(failure.message));
      }
    } on Object {
      if (mounted) showGlassErrorToast(context, context.t('errors.unexpected'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => HinataToolButton(
    icon: LucideIcons.image,
    tooltipKey: 'md.image',
    busy: _busy,
    onTap: _pick,
  );
}

/// Opens the mention picker and inserts the chosen chip.
class HinataMentionButton extends StatelessWidget {
  const HinataMentionButton({required this.controller, super.key});

  final HinataEditorController controller;

  Future<void> _pick(BuildContext context) async {
    final resolver = SmartLinkScope.of(context);
    final picked = await showGlassMentionPicker(context, resolver);
    if (picked == null) return;
    controller.editor.update(
      () => $insertSmartLink(
        kind: SmartLinkKind.parse(picked.kind),
        targetId: picked.id,
        // Only an issue key reads as itself; an ObjectId does not, and putting
        // one in front of the reader is the thing the label exists to avoid.
        label: picked.kind == 'issue' ? picked.title : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => HinataToolButton(
    icon: LucideIcons.atSign,
    tooltipKey: 'md.mention',
    onTap: () => _pick(context),
  );
}

/// A glass picker over issues, articles and people.
///
/// A dialog rather than a list rendered into the form: the app's rule is a
/// one-line trigger opening a searchable glass surface, and a candidate list
/// that can run to hundreds of rows is exactly why.
Future<MentionCandidate?> showGlassMentionPicker(
  BuildContext context,
  SmartLinkResolver resolver,
) => showGlassModal<MentionCandidate>(
  context,
  width: 440,
  builder: (_) => _MentionPicker(resolver: resolver),
);

class _MentionPicker extends StatefulWidget {
  const _MentionPicker({required this.resolver});

  final SmartLinkResolver resolver;

  @override
  State<_MentionPicker> createState() => _MentionPickerState();
}

class _MentionPickerState extends State<_MentionPicker> {
  final TextEditingController _query = TextEditingController();
  List<MentionCandidate> _issues = const [];
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _query.addListener(_onQuery);
    _fetchIssues('');
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _onQuery() {
    _fetchIssues(_query.text.trim());
    setState(() {});
  }

  /// The issue detail keeps its issues on the server rather than draining the
  /// whole project set into memory, so those candidates arrive asynchronously.
  Future<void> _fetchIssues(String query) async {
    if (!widget.resolver.asyncIssueMentions) return;
    final request = ++_request;
    final found = await widget.resolver.searchIssueMentions(query);
    if (!mounted || request != _request) return;
    setState(() => _issues = found);
  }

  List<MentionCandidate> get _items => [
    ..._issues,
    ...widget.resolver.mentions(_query.text.trim(), commentMode: false),
  ];

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 14, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.t('md.mention'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontBrand,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(LucideIcons.x, size: 18, color: AppColors.inkFaint),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
          child: TextField(
            controller: _query,
            autofocus: true,
            decoration: glassInputDecoration(
              hint: context.t('md.mentionSearch'),
            ),
          ),
        ),
        Flexible(
          child: items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
                  child: Text(
                    context.t('common.noMatches'),
                    style: TextStyle(color: AppColors.inkFaint, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 14),
                  itemCount: items.length,
                  itemBuilder: (context, index) => _row(items[index]),
                ),
        ),
      ],
    );
  }

  Widget _row(MentionCandidate item) {
    final icon = switch (item.kind) {
      'issue' => lucideIcon(item.issueType ?? 'circle-dot'),
      'doc' => lucideIcon(item.icon ?? 'file-text'),
      _ => LucideIcons.atSign,
    };
    return InkWell(
      onTap: () => Navigator.of(context).pop(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 16, color: item.issueColor ?? AppColors.inkSoft),
            const SizedBox(width: 10),
            // Titles are user data of any length, and this has to survive a
            // 320 px phone.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.sub.isNotEmpty)
                    Text(
                      item.sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.inkFaint,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
