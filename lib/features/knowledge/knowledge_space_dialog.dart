import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/hue_colors.dart';
import '../sprint/modals/glass_modal.dart'
    show
        GlassField,
        GlassModalFooter,
        GlassModalHeader,
        glassInputDecoration,
        showGlassModal;
import 'data/knowledge_models.dart';
import 'knowledge_tokens.dart';

/// Curated set of space-appropriate Lucide glyphs (all resolvable via
/// [lucideIcon]) offered in the create-space picker.
const List<String> _kSpaceIcons = [
  'code-xml',
  'compass',
  'palette',
  'server-cog',
  'rocket',
  'flame',
  'graduation-cap',
  'git-branch',
  'sparkles',
  'container',
  'database-backup',
  'key-round',
];

/// Opens the Liquid-Glass "new space" dialog. [onCreate] performs the actual
/// persistence and returns an error message to show inline, or null on success
/// (the dialog then closes). Resolves to the created space's name, or null if
/// the user cancelled.
Future<String?> showCreateSpaceDialog(
  BuildContext context, {
  required Future<String?> Function({
    required String name,
    required String icon,
    required int hue,
    required String description,
  })
  onCreate,
}) {
  return showGlassModal<String>(
    context,
    width: 460,
    builder: (modalContext) => _CreateSpaceForm(onCreate: onCreate),
  );
}

class _CreateSpaceForm extends StatefulWidget {
  const _CreateSpaceForm({required this.onCreate});

  final Future<String?> Function({
    required String name,
    required String icon,
    required int hue,
    required String description,
  })
  onCreate;

  @override
  State<_CreateSpaceForm> createState() => _CreateSpaceFormState();
}

class _CreateSpaceFormState extends State<_CreateSpaceForm> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  String _icon = _kSpaceIcons.first;
  int _hue = kLabelHues.first;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await widget.onCreate(
      name: name,
      icon: _icon,
      hue: _hue,
      description: _desc.text.trim(),
    );
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop(name);
    } else {
      setState(() {
        _busy = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _name.text.trim().isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: lucideIcon('folder-plus'),
          title: context.t('knowledge.newSpace'),
          subtitle: context.t('knowledge.newSpaceSubtitle'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GlassField(
                label: context.t('knowledge.spaceName'),
                child: TextField(
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: glassInputDecoration(
                    hint: context.t('knowledge.spaceNameHint'),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(height: 16),
              GlassField(
                label: context.t('knowledge.spaceDescription'),
                child: TextField(
                  controller: _desc,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: glassInputDecoration(
                    hint: context.t('knowledge.spaceDescriptionHint'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              GlassField(
                label: context.t('knowledge.spaceIcon'),
                child: _iconPicker(),
              ),
              const SizedBox(height: 16),
              GlassField(
                label: context.t('knowledge.spaceColor'),
                child: _huePicker(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(
                      lucideIcon('triangle-alert'),
                      size: 15,
                      color: AppColors.danger,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('knowledge.createSpace'),
          confirmIcon: lucideIcon('plus'),
          busy: _busy,
          onConfirm: canSubmit ? _submit : null,
        ),
      ],
    );
  }

  Widget _iconPicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final name in _kSpaceIcons)
          _PickTile(
            selected: _icon == name,
            hue: _hue,
            onTap: () => setState(() => _icon = name),
            child: Icon(
              lucideIcon(name),
              size: 18,
              color: _icon == name
                  ? KbTokens.spaceChipText(_hue)
                  : AppColors.inkSoft,
            ),
          ),
      ],
    );
  }

  Widget _huePicker() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final h in kLabelHues)
          GestureDetector(
            onTap: () => setState(() => _hue = h),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: hueSwatch(h),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _hue == h ? AppColors.ink : Colors.transparent,
                  width: 2.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A square, selectable tile used by the icon picker.
class _PickTile extends StatelessWidget {
  const _PickTile({
    required this.selected,
    required this.hue,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final int hue;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? KbTokens.spaceChipBg(hue) : AppColors.surface,
          borderRadius: BorderRadius.circular(KbTokens.radiusControl),
          border: Border.all(
            color: selected ? KbTokens.spaceChipText(hue) : AppColors.hairline,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: child,
      ),
    );
  }
}
