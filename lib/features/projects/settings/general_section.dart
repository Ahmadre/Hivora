import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/hue_colors.dart';
import '../../../core/util/keys.dart';
import '../../../core/widgets/entity_avatar_editor.dart';
import 'settings_common.dart';

/// General card: picture, name (required), key (required, uppercase),
/// description, accent.
class GeneralSection extends StatelessWidget {
  const GeneralSection({
    super.key,
    required this.nameController,
    required this.keyController,
    required this.descController,
    required this.nameError,
    required this.keyError,
    required this.selectedHue,
    required this.onHue,
    required this.avatarUrl,
    required this.onUploadAvatar,
    required this.onRemoveAvatar,
    required this.onAvatarChanged,
  });

  final TextEditingController nameController;
  final TextEditingController keyController;
  final TextEditingController descController;
  final bool nameError;
  final bool keyError;
  final int selectedHue;
  final ValueChanged<int> onHue;

  /// Server-owned project picture, or null while the key glyph stands in.
  final String? avatarUrl;

  /// Stores a newly picked picture and answers its fresh URL.
  final Future<String> Function(MultipartFile file) onUploadAvatar;

  /// Drops the current picture.
  final Future<void> Function() onRemoveAvatar;

  /// The picture's new URL, or null after a removal. Not part of the settings
  /// draft: the upload endpoints commit on their own, so there is nothing for
  /// the save bar to pick up.
  final ValueChanged<String?> onAvatarChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: context.t('projectSettings.general'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel(text: context.t('projectSettings.avatar.label')),
          _AvatarRow(
            avatarUrl: avatarUrl,
            projectKey: keyController.text,
            hue: selectedHue,
            onUpload: onUploadAvatar,
            onRemove: onRemoveAvatar,
            onChanged: onAvatarChanged,
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 480;
              final nameField = _NameField(
                controller: nameController,
                error: nameError,
              );
              final keyField = _KeyField(
                controller: keyController,
                nameController: nameController,
                error: keyError,
              );
              if (stacked) {
                return Column(
                  children: [nameField, const SizedBox(height: 16), keyField],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: nameField),
                  const SizedBox(width: 16),
                  SizedBox(width: 160, child: keyField),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          FieldLabel(text: context.t('issues.description')),
          TextField(
            controller: descController,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            textCapitalization: TextCapitalization.sentences,
            minLines: 2,
            maxLines: 5,
            decoration: settingsInput(
              context,
              hint: context.t('projectSettings.descHint'),
            ),
          ),
          const SizedBox(height: 16),
          FieldLabel(text: context.t('projectSettings.accentColor')),
          _Swatches(selectedHue: selectedHue, onHue: onHue),
        ],
      ),
    );
  }
}

/// The project picture next to the line explaining what happens to it.
///
/// The glyph behind it is the same mono-key square the project cards draw, so
/// removing the picture visibly returns the project to what it looked like
/// before — and the key/colour being edited above are reflected live.
class _AvatarRow extends StatelessWidget {
  const _AvatarRow({
    required this.avatarUrl,
    required this.projectKey,
    required this.hue,
    required this.onUpload,
    required this.onRemove,
    required this.onChanged,
  });

  final String? avatarUrl;
  final String projectKey;
  final int hue;
  final Future<String> Function(MultipartFile file) onUpload;
  final Future<void> Function() onRemove;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        EntityAvatarField(
          avatarUrl: avatarUrl,
          size: 64,
          radius: 18,
          strings: EntityAvatarStrings.project,
          fallback: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: hueSoft(hue),
              borderRadius: BorderRadius.circular(18),
            ),
            alignment: Alignment.center,
            child: Text(
              projectKey.isEmpty ? 'KEY' : projectKey,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontFamily: AppTheme.fontMono,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: hueChipText(hue),
              ),
            ),
          ),
          onUpload: onUpload,
          onRemove: onRemove,
          onChanged: onChanged,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            context.t('projectSettings.avatar.hint'),
            style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
          ),
        ),
      ],
    );
  }
}

class _NameField extends StatelessWidget {
  const _NameField({required this.controller, required this.error});
  final TextEditingController controller;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(text: context.t('projects.name'), required: true),
        TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: settingsInput(
            context,
            hint: context.t('projects.name'),
            error: error,
          ),
        ),
        if (error) ...[
          const SizedBox(height: 6),
          Text(
            context.t('projectSettings.nameEmpty'),
            style: const TextStyle(fontSize: 11.5, color: AppColors.danger),
          ),
        ],
      ],
    );
  }
}

class _KeyField extends StatelessWidget {
  const _KeyField({
    required this.controller,
    required this.nameController,
    required this.error,
  });
  final TextEditingController controller;

  /// The name the key can be re-derived from — on request only. An existing
  /// project's key prefixes every one of its issue ids, and the server re-keys
  /// them all when it changes, so this never follows the name on its own the
  /// way the create dialog does.
  final TextEditingController nameController;
  final bool error;

  void _generate() {
    final suggestion = suggestKey(nameController.text);
    if (suggestion.isEmpty) return;
    controller.value = TextEditingValue(
      text: suggestion,
      selection: TextSelection.collapsed(offset: suggestion.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            FieldLabel(text: context.t('projects.key'), required: true),
            const Spacer(),
            Tooltip(
              message: context.t('projectSettings.keyFromName'),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: _generate,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    LucideIcons.wandSparkles,
                    size: 14,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
            ),
          ],
        ),
        TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          maxLength: 10,
          style: const TextStyle(fontFamily: AppTheme.fontMono),
          inputFormatters: [_UpperAlphaNum()],
          decoration: settingsInput(
            context,
            hint: 'KEY',
            error: error,
          ).copyWith(counterText: ''),
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            text: '${context.t('projectSettings.issuesReadLike')} ',
            style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
            children: [
              TextSpan(
                text: '${controller.text.isEmpty ? 'KEY' : controller.text}-42',
                style: TextStyle(
                  fontFamily: AppTheme.fontMono,
                  color: AppColors.inkSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Uppercases and strips anything outside [A-Z0-9] as the user types.
class _UpperAlphaNum extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.toUpperCase().replaceAll(
      RegExp('[^A-Z0-9]'),
      '',
    );
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _Swatches extends StatelessWidget {
  const _Swatches({required this.selectedHue, required this.onHue});
  final int selectedHue;
  final ValueChanged<int> onHue;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final c in kProjectHues)
          GestureDetector(
            onTap: () => onHue(c.hue),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: hueSwatch(c.hue),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: c.hue == selectedHue
                      ? AppColors.ink
                      : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            hueName(selectedHue),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.inkSoft,
            ),
          ),
        ),
      ],
    );
  }
}
