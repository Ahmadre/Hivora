import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_widgets.dart';

/// Tone of an [AdminNote] — drives its tint, rim and glyph colour.
enum AdminNoteTone { accent, info, warning, danger }

/// A tinted info/callout banner (icon + text) shared across the admin sections,
/// so every "note" (OWASP tip, integration hint, warning) reads identically.
class AdminNote extends StatelessWidget {
  const AdminNote({
    super.key,
    required this.text,
    this.icon = LucideIcons.info,
    this.tone = AdminNoteTone.accent,
  });

  final String text;
  final IconData icon;
  final AdminNoteTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, border, glyph) = switch (tone) {
      AdminNoteTone.accent => (
        AppColors.accentSoft,
        AppColors.accentLine,
        AppColors.accentStrong,
      ),
      AdminNoteTone.info => (
        AppColors.surfaceMuted,
        AppColors.hairline2,
        AppColors.inkSoft,
      ),
      AdminNoteTone.warning => (
        AppColors.warning.withValues(alpha: 0.12),
        AppColors.warning.withValues(alpha: 0.35),
        AppColors.warning,
      ),
      AdminNoteTone.danger => (
        AppColors.dangerSoft,
        AppColors.danger.withValues(alpha: 0.35),
        AppColors.danger,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: glyph),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: AppColors.inkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared input decoration for admin form fields — a filled, rounded field with
/// a hairline rim that lifts to the amber accent on focus. Keeps every section's
/// text/number inputs visually identical to the rest of the settings surfaces.
InputDecoration adminInputDecoration(
  BuildContext context, {
  String? label,
  String? hint,
  String? helper,
  String? suffix,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    suffixText: suffix,
    filled: true,
    fillColor: AppColors.surfaceMuted,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: border(AppColors.hairline),
    enabledBorder: border(AppColors.hairline),
    focusedBorder: border(AppColors.accent, 1.4),
    labelStyle: TextStyle(fontSize: 13.5, color: AppColors.inkSoft),
    floatingLabelStyle: const TextStyle(
      fontSize: 13.5,
      color: AppColors.accentStrong,
    ),
  );
}

/// Card that groups related admin settings with an icon, title and subtitle.
class AdminSectionCard extends StatelessWidget {
  const AdminSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: AppColors.accentStrong),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: AppTheme.fontBrand,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          letterSpacing: -0.2,
                          color: AppColors.ink,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              color: AppColors.inkSoft,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.hairline2),
          // Fields
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled text field bound to a map key. Handles secret masking.
class AdminField extends StatelessWidget {
  const AdminField({
    super.key,
    required this.label,
    required this.initialValue,
    required this.onChanged,
    this.isSecret = false,
    this.hint,
    this.keyboardType,
  });

  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final bool isSecret;
  final String? hint;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final noAutocorrect =
        isSecret ||
        keyboardType == TextInputType.url ||
        keyboardType == TextInputType.emailAddress;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        initialValue: initialValue,
        obscureText: isSecret,
        keyboardType: keyboardType,
        autocorrect: !noAutocorrect,
        enableSuggestions: !isSecret,
        style: TextStyle(fontSize: 14, color: AppColors.ink),
        decoration: adminInputDecoration(
          context,
          label: label,
          hint: hint,
          helper: isSecret ? context.t('admin.secretHint') : null,
        ),
        onChanged: onChanged,
      ),
    );
  }
}

/// A numeric text field bound to a map key.
///
/// Uses a controller so the field and the saved draft never diverge: in-range
/// values propagate live while typing, and when the field loses focus (or the
/// user hits Done) the value is clamped to [min]/[max] — or reset from an empty
/// field — and that clamped value is written back into the field itself, so the
/// admin always saves exactly what they see.
class AdminNumberField extends StatefulWidget {
  const AdminNumberField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.suffix,
    this.min,
    this.max,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final String? suffix;
  final int? min;
  final int? max;

  @override
  State<AdminNumberField> createState() => _AdminNumberFieldState();
}

class _AdminNumberFieldState extends State<AdminNumberField> {
  late final TextEditingController _ctrl = TextEditingController(
    text: '${widget.value}',
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(AdminNumberField old) {
    super.didUpdateWidget(old);
    // Reflect an externally-changed value (e.g. a form reset) when the user
    // isn't actively editing this field.
    if (!_focus.hasFocus && widget.value != old.value) {
      _ctrl.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  int _clamp(int v) {
    final lo = widget.min;
    final hi = widget.max;
    if (lo != null && v < lo) return lo;
    if (hi != null && v > hi) return hi;
    return v;
  }

  /// Snap the field to a valid value on blur / submit and write it back so the
  /// display matches what will be saved.
  void _commit() {
    final clamped = _clamp(int.tryParse(_ctrl.text.trim()) ?? widget.value);
    if (_ctrl.text != '$clamped') _ctrl.text = '$clamped';
    if (clamped != widget.value) widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _ctrl,
        focusNode: _focus,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        style: TextStyle(fontSize: 14, color: AppColors.ink),
        decoration: adminInputDecoration(
          context,
          label: widget.label,
          suffix: widget.suffix,
        ),
        onChanged: (v) {
          // Propagate live only while the value is already in range — clamping
          // mid-keystroke would fight the user (typing "30" would stick at min).
          final parsed = int.tryParse(v);
          if (parsed != null && _clamp(parsed) == parsed) {
            widget.onChanged(parsed);
          }
        },
        onEditingComplete: () {
          _commit();
          _focus.unfocus();
        },
      ),
    );
  }
}

/// Enable/disable toggle row (used for SSO provider and feature blocks).
class AdminToggle extends StatelessWidget {
  const AdminToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppColors.ink,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              HiveSwitch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// Expandable provider block: enable switch + form fields.
class ProviderTile extends StatefulWidget {
  const ProviderTile({
    super.key,
    required this.title,
    required this.section,
    required this.fields,
    required this.onChanged,
    this.subtitle,
    this.initiallyExpanded = false,
    this.toggles = const [],
    this.note,
  });

  final String title;
  final String? subtitle;
  final Map<String, dynamic> section;

  /// (jsonKey, label, isSecret)
  final List<(String, String, bool)> fields;

  /// Boolean provider options rendered below the fields — (jsonKey, label).
  final List<(String, String)> toggles;

  /// Explanatory callout shown above the fields (e.g. the mapping syntax).
  final String? note;
  final VoidCallback onChanged;
  final bool initiallyExpanded;

  @override
  State<ProviderTile> createState() => _ProviderTileState();
}

class _ProviderTileState extends State<ProviderTile> {
  // Lets us programmatically unfold the tile when the provider is switched on —
  // ExpansionTile only honours initiallyExpanded on first build, so without this
  // toggling enable wouldn't reveal the credential fields the admin now needs.
  final ExpansibleController _expansion = ExpansibleController();

  @override
  void dispose() {
    _expansion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.section['enabled'] == true;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: enabled ? AppColors.accentSoft : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled ? AppColors.accentLine : AppColors.hairline2,
          ),
        ),
        margin: const EdgeInsets.only(bottom: 10),
        // Transparent Material so the ExpansionTile's inner ListTile paints its
        // ink/background on a Material in front of this coloured Container,
        // instead of a hidden one behind it (Flutter asserts otherwise).
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            controller: _expansion,
            initiallyExpanded: widget.initiallyExpanded || enabled,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 2,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
            title: Row(
              children: [
                HiveSwitch(
                  value: enabled,
                  onChanged: (value) {
                    setState(() => widget.section['enabled'] = value);
                    widget.onChanged();
                    // Reveal the credential fields the moment it's enabled.
                    if (value) _expansion.expand();
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: enabled ? AppColors.ink : AppColors.inkSoft,
                        ),
                      ),
                      if (widget.subtitle != null)
                        Text(
                          widget.subtitle!,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.inkFaint,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            children: [
              if (widget.note != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AdminNote(text: widget.note!),
                ),
              for (final (key, label, secret) in widget.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextFormField(
                    initialValue: (widget.section[key] as String?) ?? '',
                    obscureText: secret,
                    autocorrect: false,
                    enableSuggestions: !secret,
                    style: TextStyle(fontSize: 14, color: AppColors.ink),
                    decoration: adminInputDecoration(
                      context,
                      label: label,
                      helper: secret ? context.t('admin.secretHint') : null,
                    ),
                    onChanged: (value) => widget.section[key] = value,
                  ),
                ),
              for (final (key, label) in widget.toggles)
                AdminToggle(
                  label: label,
                  // Absent in a settings document written before the option
                  // existed — the server defaults it to on, so mirror that here.
                  value: widget.section[key] != false,
                  onChanged: (value) {
                    setState(() => widget.section[key] = value);
                    widget.onChanged();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
