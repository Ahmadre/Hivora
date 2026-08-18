import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/team_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/keys.dart';
import '../../core/widgets/entity_avatar_editor.dart';
import '../deletion/delete_flows.dart';
import 'team_modal_kit.dart';
import 'team_widgets.dart';

export 'team_member_modals.dart';
export 'team_project_modal.dart';

/// Create-team modal. Returns the created [Team] (so the caller can open it).
///
/// [takenKeys] lets the suggested key step around the ones already in use.
Future<Team?> showCreateTeamModal(
  BuildContext context, {
  Set<String> takenKeys = const {},
}) {
  final repo = context.read<TeamRepository>();
  return showTeamModal<Team>(
    context,
    _TeamFormBody(repo: repo, takenKeys: takenKeys),
    width: 580,
  );
}

/// Edit-team modal. Returns true if the team was saved.
Future<bool?> showEditTeamModal(
  BuildContext context,
  Team team, {
  Set<String> takenKeys = const {},
}) {
  final repo = context.read<TeamRepository>();
  return showTeamModal<bool>(
    context,
    _TeamFormBody(repo: repo, existing: team, takenKeys: takenKeys),
    width: 580,
  );
}

/// Delete-team modal: warns about the access members lose, then streams the
/// cascade over SSE. Returns true if deleted.
Future<bool?> showDeleteTeamModal(BuildContext context, Team team) {
  return showDeleteTeamFlow(context, teamId: team.id, teamName: team.name);
}

class _TeamFormBody extends StatefulWidget {
  const _TeamFormBody({
    required this.repo,
    this.existing,
    this.takenKeys = const {},
  });

  final TeamRepository repo;
  final Team? existing;

  /// Keys already in use — best effort, the server still answers 409 for one
  /// this list missed.
  final Set<String> takenKeys;

  @override
  State<_TeamFormBody> createState() => _TeamFormBodyState();
}

class _TeamFormBodyState extends State<_TeamFormBody> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _key = TextEditingController(
    text: widget.existing?.key ?? '',
  );
  late final TextEditingController _desc = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  late int _hue = widget.existing?.colorHue ?? 70;
  late String _icon = widget.existing?.icon ?? 'hexagon';

  /// Picture of the team being edited. Uploads land immediately (the endpoints
  /// are separate from the team PATCH), so this only mirrors what the server
  /// already stored — it is never sent with the form.
  late String? _avatarUrl = widget.existing?.avatarUrl;
  bool _busy = false;
  String? _error;

  /// While true the key follows the name. It starts on for a new team, and for
  /// an existing one only while its key is still exactly what the name would
  /// generate — a key somebody chose is never rewritten under them.
  late bool _keyFollowsName = isGeneratedKey(
    widget.existing?.key ?? '',
    widget.existing?.name ?? '',
    maxLength: _maxKeyLength,
  );

  /// The key field is five characters wide here; the server allows ten.
  static const int _maxKeyLength = 5;

  bool get _isEdit => widget.existing != null;

  Set<String> get _taken => {
    for (final key in widget.takenKeys)
      if (key.toUpperCase() != (widget.existing?.key ?? '').toUpperCase())
        key.toUpperCase(),
  };

  bool get _keyTaken => _taken.contains(_key.text.trim().toUpperCase());

  @override
  void initState() {
    super.initState();
    _name.addListener(_onNameChanged);
    _key.addListener(_onKeyChanged);
  }

  /// Types the key along with the name, so nobody has to invent one — it stays
  /// a plain field they can overrule at any point.
  void _onNameChanged() {
    if (!_keyFollowsName) return;
    final suggestion = suggestKey(
      _name.text,
      taken: _taken,
      maxLength: _maxKeyLength,
    );
    if (suggestion == _key.text) return;
    _key.value = TextEditingValue(
      text: suggestion,
      selection: TextSelection.collapsed(offset: suggestion.length),
    );
  }

  void _onKeyChanged() {
    if (_keyFollowsName &&
        _key.text !=
            suggestKey(_name.text, taken: _taken, maxLength: _maxKeyLength)) {
      _keyFollowsName = false;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _name.removeListener(_onNameChanged);
    _key.removeListener(_onKeyChanged);
    _name.dispose();
    _key.dispose();
    _desc.dispose();
    super.dispose();
  }

  /// What gets sent: whatever stands in the field, or — if it was cleared — a
  /// fresh suggestion from the name.
  String get _effectiveKey {
    final typed = _key.text.trim().toUpperCase();
    if (typed.isNotEmpty) return typed;
    return suggestKey(_name.text, taken: _taken, maxLength: _maxKeyLength);
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = context.t('errors.required'));
      return;
    }
    if (_keyTaken) {
      setState(() => _error = context.t('teams.keyTaken'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isEdit) {
        await widget.repo.updateTeam(widget.existing!.id, {
          'name': name,
          'key': _effectiveKey.isEmpty ? widget.existing!.key : _effectiveKey,
          'description': _desc.text.trim(),
          'colorHue': _hue,
          'icon': _icon,
        });
        if (mounted) Navigator.of(context).pop(true);
      } else {
        final created = await widget.repo.createTeam(
          name: name,
          key: _effectiveKey,
          description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
          colorHue: _hue,
          icon: _icon,
        );
        if (mounted) Navigator.of(context).pop(created);
      }
    } on ApiFailure catch (failure) {
      setState(() {
        _busy = false;
        _error = failure.message;
      });
    }
  }

  /// The 52px identity square: a live preview of the colour + icon being
  /// picked, and — once the team exists — the picture upload itself.
  ///
  /// A team being *created* has no id yet, so there is nothing to upload
  /// against; it stays the plain preview and gets its picture from the settings
  /// tab afterwards.
  Widget _identityGlyph(Color color) {
    final preview = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.soft(color),
        borderRadius: BorderRadius.circular(15),
      ),
      alignment: Alignment.center,
      child: Icon(teamIcon(_icon), size: 26, color: color),
    );
    final team = widget.existing;
    if (team == null) return preview;
    return EntityAvatarField(
      avatarUrl: _avatarUrl,
      size: 52,
      radius: 15,
      strings: EntityAvatarStrings.team,
      fallback: preview,
      onUpload: (file) => widget.repo.uploadTeamAvatar(team.id, file),
      onRemove: () => widget.repo.deleteTeamAvatar(team.id),
      onChanged: (url) => setState(() => _avatarUrl = url),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = teamHueColor(_hue);
    return ModalShell(
      icon: _isEdit ? LucideIcons.slidersHorizontal : LucideIcons.usersRound,
      title: context.t(_isEdit ? 'teams.editTitle' : 'teams.createTitle'),
      subtitle: context.t(
        _isEdit ? 'teams.editSubtitle' : 'teams.createSubtitle',
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Identity row: live glyph + name + key.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _identityGlyph(color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FieldLabel(context.t('teams.name')),
                    TextField(
                      controller: _name,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: teamFieldDecoration(
                        context,
                        hint: context.t('teams.namePlaceholder'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 96,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FieldLabel(context.t('teams.key')),
                    TextField(
                      controller: _key,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      maxLength: 5,
                      buildCounter:
                          (
                            _, {
                            required currentLength,
                            required isFocused,
                            maxLength,
                          }) => null,
                      style: const TextStyle(fontFamily: AppTheme.fontMono),
                      decoration: teamFieldDecoration(context, hint: 'CORE'),
                    ),
                    // Said here rather than after a round trip that fails.
                    if (_keyTaken)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          context.t('teams.keyTaken'),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FieldLabel(context.t('teams.description'), optional: true),
          TextField(
            controller: _desc,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            textCapitalization: TextCapitalization.sentences,
            minLines: 2,
            maxLines: 4,
            decoration: teamFieldDecoration(
              context,
              hint: context.t('teams.descriptionPlaceholder'),
            ),
          ),
          const SizedBox(height: 18),
          FieldLabel(context.t('teams.colorLabel')),
          ColorPicker(hue: _hue, onChanged: (h) => setState(() => _hue = h)),
          const SizedBox(height: 18),
          FieldLabel(context.t('teams.iconLabel')),
          IconPicker(
            selected: _icon,
            onChanged: (i) => setState(() => _icon = i),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.danger, fontSize: 12.5),
            ),
          ],
        ],
      ),
      footer: ModalFooter(
        primaryLabel: context.t(_isEdit ? 'common.save' : 'teams.createCta'),
        primaryIcon: _isEdit ? LucideIcons.check : LucideIcons.check,
        busy: _busy,
        onPrimary: _name.text.trim().isEmpty ? null : _submit,
      ),
    );
  }
}
