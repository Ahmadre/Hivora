/// Asking the writer for a link address.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../i18n/i18n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../../features/sprint/modals/glass_modal.dart';

/// Opens the glass link dialog and returns what the writer decided.
///
/// * a non-empty string — link the selection to it,
/// * the empty string — remove the link that is there,
/// * null — they cancelled, so nothing happens at all.
///
/// A dialog rather than a field in the toolbar: an address is a whole second
/// thing to type, and a toolbar row that grows a text input is the shape this
/// app deliberately does not use.
Future<String?> showGlassLinkDialog(
  BuildContext context, {
  String? initialUrl,
}) => showGlassModal<String>(
  context,
  width: 420,
  builder: (modalContext) => _LinkDialog(initialUrl: initialUrl),
);

class _LinkDialog extends StatefulWidget {
  const _LinkDialog({this.initialUrl});

  final String? initialUrl;

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  late final TextEditingController _url = TextEditingController(
    text: widget.initialUrl ?? '',
  );

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _url.text.trim();
    if (url.isEmpty) return;
    Navigator.of(context).pop(url);
  }

  @override
  Widget build(BuildContext context) {
    final hasLink = (widget.initialUrl ?? '').isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 14, 4),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  LucideIcons.link,
                  size: 17,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.t('md.link'),
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
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
          child: GlassField(
            label: context.t('md.linkUrl'),
            child: TextField(
              controller: _url,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: glassInputDecoration(hint: 'https://'),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: AppColors.hairline.withValues(alpha: 0.6)),
            ),
          ),
          // A Wrap rather than a Row: three buttons with translated labels do
          // not fit a 320 px phone side by side, and a toolbar dialog that
          // overflows is worse than one that takes two lines.
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (hasLink)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(''),
                  child: Text(
                    context.t('md.linkRemove'),
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(context.t('common.cancel')),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _url,
                builder: (context, value, _) => FilledButton.icon(
                  onPressed: value.text.trim().isEmpty ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusControl,
                      ),
                    ),
                  ),
                  icon: const Icon(LucideIcons.check, size: 15),
                  label: Text(context.t('md.linkAdd')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
