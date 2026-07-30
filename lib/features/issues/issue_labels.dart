import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../sprint/modals/glass_modal.dart'
    show
        kGlassPopoverBreakpoint,
        showGlassAnchoredPopover,
        showGlassBottomSheet,
        showGlassConfirm,
        showGlassErrorToast;

/// Multi-select label ("Stichwort") picker. On tablet/desktop it opens as an
/// anchored popover beside the field (like the other detail pickers); on phone
/// it falls back to a bottom sheet. Lets the user toggle existing project
/// labels, filter by typing, create a new label on the fly, and remove assigned
/// ones. Returns the new selection (in vocabulary order), or null if dismissed
/// without confirming.
Future<List<String>?> showLabelPicker(
  BuildContext context, {
  required List<String> available,
  required List<String> selected,
  Future<void> Function(String label)? onDelete,
  Rect? anchor,
}) {
  Widget builder(BuildContext sheetContext) => _LabelPickerSheet(
    available: available,
    selected: selected,
    onDelete: onDelete,
  );
  final wide = MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint;
  if (wide && anchor != null) {
    return showGlassAnchoredPopover<List<String>>(
      context,
      anchorRect: anchor,
      width: 340,
      maxHeight: 520,
      builder: builder,
    );
  }
  return showGlassBottomSheet<List<String>>(context, builder: builder);
}

class _LabelPickerSheet extends StatefulWidget {
  const _LabelPickerSheet({
    required this.available,
    required this.selected,
    this.onDelete,
  });

  final List<String> available;
  final List<String> selected;

  /// Permanently deletes a label from the project (and all its issues). When
  /// null, the per-chip delete affordance is hidden.
  final Future<void> Function(String label)? onDelete;

  @override
  State<_LabelPickerSheet> createState() => _LabelPickerSheetState();
}

class _LabelPickerSheetState extends State<_LabelPickerSheet> {
  final _controller = TextEditingController();
  late final List<String> _all; // vocabulary, mutable (created labels append)
  late final Set<String> _selected;
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Union of available + selected, preserving first-seen order.
    final seen = <String>{};
    _all = [
      for (final l in [...widget.available, ...widget.selected])
        if (l.trim().isNotEmpty && seen.add(l)) l,
    ];
    _selected = {...widget.selected};
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle(String label) {
    setState(() {
      if (!_selected.remove(label)) _selected.add(label);
    });
  }

  void _create(String raw) {
    final label = raw.trim();
    if (label.isEmpty) return;
    setState(() {
      if (!_all.contains(label)) _all.add(label);
      _selected.add(label);
      _controller.clear();
      _query = '';
    });
  }

  void _confirm() {
    Navigator.of(context).pop([
      for (final l in _all)
        if (_selected.contains(l)) l,
    ]);
  }

  // Unselecting a label only removes it from the issue; it stays in the
  // vocabulary. Permanent removal goes through this confirmed delete instead.
  Future<void> _delete(String label) async {
    final onDelete = widget.onDelete;
    if (onDelete == null) return;
    final confirmed = await showGlassConfirm(
      context,
      icon: LucideIcons.trash2,
      title: context.t('issues.deleteLabel'),
      message: context.t(
        'issues.deleteLabelConfirm',
        variables: {'name': label},
      ),
      confirmLabel: context.t('common.delete'),
      confirmIcon: LucideIcons.trash2,
      destructive: true,
    );
    if (confirmed != true) return;
    try {
      await onDelete(label);
      if (!mounted) return;
      setState(() {
        _all.remove(label);
        _selected.remove(label);
      });
    } catch (_) {
      if (!mounted) return;
      showGlassErrorToast(context, context.t('errors.unexpected'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _all
        : _all.where((l) => l.toLowerCase().contains(q)).toList();
    final exists = _all.any((l) => l.toLowerCase() == q);
    final canCreate = q.isNotEmpty && !exists;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
          child: Row(
            children: [
              Text(
                context.t('issues.labels'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _confirm,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.accentStrong,
                ),
                child: Text(
                  context.t('common.save'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: TextField(
            controller: _controller,
            autofocus: true,
            onChanged: (v) => setState(() => _query = v),
            onSubmitted: canCreate ? _create : null,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: Icon(
                LucideIcons.search,
                size: 18,
                color: AppColors.inkFaint,
              ),
              hintText: context.t('issues.addLabel'),
              hintStyle: TextStyle(color: AppColors.inkFaint, fontSize: 13.5),
              filled: true,
              fillColor: AppColors.surfaceMuted,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                borderSide: BorderSide(color: AppColors.hairline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                borderSide: BorderSide(color: AppColors.hairline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                borderSide: const BorderSide(color: AppColors.accentLine),
              ),
            ),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (canCreate)
                  _CreateRow(
                    label: _query.trim(),
                    onTap: () => _create(_query),
                  ),
                if (filtered.isEmpty && !canCreate)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        context.t('issues.noLabels'),
                        style: TextStyle(color: AppColors.inkFaint),
                      ),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final l in filtered)
                        _LabelChip(
                          label: l,
                          selected: _selected.contains(l),
                          onTap: () => _toggle(l),
                          onDelete: widget.onDelete == null
                              ? null
                              : () => _delete(l),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _CreateRow extends StatelessWidget {
  const _CreateRow({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const Icon(
                LucideIcons.plus,
                size: 18,
                color: AppColors.accentStrong,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  context.t('issues.createLabel', variables: {'name': label}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accentStrong,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LabelChip extends StatelessWidget {
  const _LabelChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onDelete,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: EdgeInsets.fromLTRB(11, 7, onDelete != null ? 5 : 11, 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          border: Border.all(
            color: selected ? AppColors.accentLine : AppColors.hairline2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 130),
              child: selected
                  ? Icon(
                      LucideIcons.check,
                      size: 14,
                      color: selected
                          ? AppColors.accentStrong
                          : AppColors.inkFaint,
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.accentStrong : AppColors.inkSoft,
              ),
            ),
            if (onDelete != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onDelete,
                behavior: HitTestBehavior.opaque,
                child: Tooltip(
                  message: context.t('issues.deleteLabel'),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(shape: BoxShape.circle),
                    child: const Icon(
                      LucideIcons.x,
                      size: 13,
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
