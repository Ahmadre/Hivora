import 'dart:typed_data';

import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hinata/core/widgets/hive_loader.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/blocs/app_config_bloc.dart';
import '../../../core/branding/org_logo_store.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/util/file_pick.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/repositories/meta_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_popup_menu.dart';
import '../../sprint/modals/glass_modal.dart'
    show showGlassToast, showGlassErrorToast, GlassToastKind;
import '../admin_form_helpers.dart';

/// General organization settings: name, logo, timezone, default language.
class AdminGeneralSection extends StatefulWidget {
  const AdminGeneralSection({super.key, required this.settings});

  final Map<String, dynamic> settings;

  @override
  State<AdminGeneralSection> createState() => _AdminGeneralSectionState();
}

class _AdminGeneralSectionState extends State<AdminGeneralSection> {
  Map<String, dynamic> get _general =>
      (widget.settings['general'] ??= <String, dynamic>{})
          as Map<String, dynamic>;

  /// Bumped after an upload/remove to remount the URL field (so its
  /// initialValue re-reads) and force the preview past the HTTP cache.
  int _logoVersion = 0;
  bool _logoBusy = false;

  /// Whether the server says the configured logo reaches mails and exported
  /// documents too, or only the app.
  ///
  /// Read from the settings payload rather than guessed from the URL: the server
  /// has actually tried to decode the bytes, so it also catches a vector served
  /// without an `.svg` suffix and a URL that cannot be fetched at all — both of
  /// which look identical to a working logo from here.
  bool get _logoReachesDocuments =>
      _general['logoUsableForDocuments'] as bool? ?? true;

  /// Whether [url] refers to an uploaded logo (an internal proxy path) rather
  /// than an external URL the admin typed. Mirrors the server's own check.
  bool _isUploadedLogo(String url) =>
      url.isNotEmpty &&
      !url.startsWith('http://') &&
      !url.startsWith('https://');

  Future<void> _uploadLogo() async {
    final repo = context.read<AdminRepository>();
    final updated = context.t('admin.logoUpdated');
    final failed = context.t('admin.logoUploadFailed');

    final List<ChosenFile> picked;
    try {
      picked = await pickFilesToUpload(
        context,
        kind: FilePickKind.image,
        withData: kIsWeb,
      );
    } catch (_) {
      // Unguarded until now: a dialog that will not open threw straight past
      // this screen instead of saying so.
      if (mounted) showGlassErrorToast(context, failed);
      return;
    }
    // An empty list means cancelled — nothing to report.
    if (picked.isEmpty) return;
    final file = picked.first;
    final multipart = kIsWeb
        ? (file.bytes == null
              ? null
              : MultipartFile.fromBytes(file.bytes!, filename: file.name))
        : (file.path == null
              ? null
              : await MultipartFile.fromFile(file.path!, filename: file.name));
    if (multipart == null) return;

    setState(() => _logoBusy = true);
    try {
      final url = await repo.uploadOrganizationLogo(multipart);
      if (!mounted) return;
      // Sync the draft so a later "Save" of the settings form doesn't clobber
      // the freshly-uploaded logo, and bump the version to refresh the preview.
      setState(() {
        _general['logoUrl'] = url;
        _logoVersion++;
      });
      _refreshChrome(url);
      showGlassToast(context, updated, kind: GlassToastKind.success);
    } catch (_) {
      if (mounted) showGlassErrorToast(context, failed);
    } finally {
      if (mounted) setState(() => _logoBusy = false);
    }
  }

  Future<void> _removeLogo() async {
    final repo = context.read<AdminRepository>();
    final removed = context.t('admin.logoRemoved');
    final failed = context.t('admin.logoUploadFailed');

    setState(() => _logoBusy = true);
    try {
      await repo.deleteOrganizationLogo();
      if (!mounted) return;
      setState(() {
        _general['logoUrl'] = '';
        _logoVersion++;
      });
      _refreshChrome(null);
      showGlassToast(context, removed, kind: GlassToastKind.success);
    } catch (_) {
      if (mounted) showGlassErrorToast(context, failed);
    } finally {
      if (mounted) setState(() => _logoBusy = false);
    }
  }

  /// Pushes a just-saved logo into the rest of the app.
  ///
  /// Without this the admin sees the new mark in the preview beside them while
  /// the rail above their head keeps showing the old one until a restart — the
  /// one place in the product where the change is guaranteed to be noticed.
  /// The bloc is re-run as well because [AppConfigBloc] writes `meta` only from
  /// its own events, so `logoUrl` would otherwise stay stale for every surface
  /// that reads it.
  void _refreshChrome(String? logoUrl) {
    context.read<OrgLogoStore>().refresh(logoUrl);
    context.read<AppConfigBloc>().add(const AppConfigStarted());
  }

  static const _timezones = [
    'Europe/Berlin',
    'Europe/London',
    'Europe/Paris',
    'Europe/Madrid',
    'Europe/Amsterdam',
    'UTC',
    'America/New_York',
    'America/Chicago',
    'America/Denver',
    'America/Los_Angeles',
    'Asia/Tokyo',
    'Asia/Shanghai',
    'Asia/Kolkata',
    'Australia/Sydney',
  ];

  static const _locales = [
    ('de', 'Deutsch (Deutschland)'),
    ('en', 'English (United Kingdom)'),
  ];

  /// A liquid-glass select styled like the rest of the admin inputs (shared
  /// [adminInputDecoration] + a chevron), replacing the stock Material dropdown
  /// so this section matches the fully-glass admin area.
  Widget _glassSelect(
    BuildContext context, {
    required String label,
    required String value,
    required List<({String value, String label})> options,
    required ValueChanged<String> onChanged,
  }) {
    // The server may persist a value outside the hardcoded list (e.g. any IANA
    // zone). Append it so it both displays and highlights, instead of silently
    // falling back to the first option and risking an accidental overwrite.
    final opts = (value.isEmpty || options.any((o) => o.value == value))
        ? options
        : [...options, (value: value, label: value)];
    final current = opts.firstWhere(
      (o) => o.value == value,
      orElse: () => opts.first,
    );
    return GlassPopupMenu<String>(
      value: value,
      onSelected: onChanged,
      items: [
        for (final o in opts) GlassMenuItem(value: o.value, label: o.label),
      ],
      child: InputDecorator(
        decoration: adminInputDecoration(context, label: label),
        child: Row(
          children: [
            Expanded(
              child: Text(
                current.label,
                style: TextStyle(fontSize: 14, color: AppColors.ink),
              ),
            ),
            Icon(LucideIcons.chevronDown, size: 18, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }

  /// Logo controls: a live preview, upload/remove buttons, and the external
  /// URL field — the admin can point at a URL or upload a file, whichever they
  /// prefer.
  Widget _buildLogoControls(BuildContext context) {
    final logoUrl = (_general['logoUrl'] as String?) ?? '';
    final uploaded = _isUploadedLogo(logoUrl);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              _LogoPreview(version: _logoVersion),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('admin.logo'),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _logoButton(
                          context,
                          icon: LucideIcons.upload,
                          label: context.t('admin.logoUpload'),
                          onTap: _logoBusy ? null : _uploadLogo,
                          busy: _logoBusy,
                        ),
                        if (uploaded)
                          _logoButton(
                            context,
                            icon: LucideIcons.trash2,
                            label: context.t('admin.logoRemove'),
                            onTap: _logoBusy ? null : _removeLogo,
                            danger: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        AdminField(
          // Remount on upload/remove so the field re-reads its initialValue
          // (blank while an uploaded logo is in use). The version only changes
          // on those actions — never on typing — so live edits aren't wiped.
          key: ValueKey('logoUrl-$_logoVersion'),
          label: context.t('admin.logoUrl'),
          initialValue: uploaded ? '' : logoUrl,
          onChanged: (v) => _general['logoUrl'] = v,
          hint: 'https://example.com/logo.png',
          keyboardType: TextInputType.url,
        ),
        AdminNote(text: context.t('admin.logoHint'), tone: AdminNoteTone.info),
        // A logo the server cannot draw shows in the app and nowhere else —
        // e-mail clients strip SVG, and no decoder here may be pointed at one.
        // Silence would look like a bug in the mails; the fix is one upload
        // away, so say so.
        if (logoUrl.isNotEmpty && !_logoReachesDocuments)
          AdminNote(
            text: context.t('admin.logoVectorLimitation'),
            tone: AdminNoteTone.warning,
          ),
      ],
    );
  }

  Widget _logoButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool danger = false,
    bool busy = false,
  }) {
    final color = danger ? AppColors.danger : AppColors.accentStrong;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: danger ? AppColors.dangerSoft : AppColors.accentSoft,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: danger
                  ? AppColors.danger.withValues(alpha: 0.35)
                  : AppColors.accentLine,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              busy
                  ? HiveLoader(size: 15, color: color)
                  : Icon(icon, size: 15, color: color),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminSectionCard(
          icon: LucideIcons.building2,
          title: context.t('admin.general'),
          subtitle: context.t('admin.generalHint'),
          children: [
            AdminField(
              label: context.t('admin.orgName'),
              initialValue:
                  (widget.settings['organizationName'] as String?) ?? '',
              onChanged: (v) => widget.settings['organizationName'] = v,
            ),
            _buildLogoControls(context),
          ],
        ),
        const SizedBox(height: 16),
        AdminSectionCard(
          icon: LucideIcons.globe,
          title: context.t('admin.localization'),
          subtitle: context.t('admin.localizationHint'),
          children: [
            _glassSelect(
              context,
              label: context.t('admin.timezone'),
              value: (_general['timezone'] as String?) ?? 'Europe/Berlin',
              options: [for (final tz in _timezones) (value: tz, label: tz)],
              onChanged: (v) => setState(() => _general['timezone'] = v),
            ),
            const SizedBox(height: 12),
            _glassSelect(
              context,
              label: context.t('admin.defaultLanguage'),
              value: (_general['defaultLocale'] as String?) ?? 'de',
              options: [for (final l in _locales) (value: l.$1, label: l.$2)],
              onChanged: (v) => setState(() => _general['defaultLocale'] = v),
            ),
          ],
        ),
      ],
    );
  }
}

/// A small square preview of the current organization logo, fetched same-origin
/// through the `/api/v1/meta/logo` proxy (works for both an external URL and an
/// uploaded file). Re-fetches when [version] changes so an upload/remove shows
/// immediately, past the HTTP cache.
class _LogoPreview extends StatefulWidget {
  const _LogoPreview({required this.version});

  final int version;

  @override
  State<_LogoPreview> createState() => _LogoPreviewState();
}

class _LogoPreviewState extends State<_LogoPreview> {
  Uint8List? _bytes;
  bool _loading = true;
  bool _svg = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_LogoPreview old) {
    super.didUpdateWidget(old);
    if (old.version != widget.version) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await context.read<MetaRepository>().organizationLogo(
        cacheBust: widget.version,
      );
      if (!mounted) return;
      setState(() {
        _bytes = res == null ? null : Uint8List.fromList(res.bytes);
        _svg = res?.isSvg ?? false;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _bytes = null;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Two grounds, not one. The mark ends up on the paper-white topbar and on
    // the navy rail and the mail band, and a logo drawn in one ink only reads on
    // one of them — a white reverse mark vanishes on paper, a navy wordmark
    // vanishes on navy. On a single neutral swatch both look fine, and the
    // operator finds out from their users. We deliberately do not "fix" it by
    // plating the mark: it is their brand, and the honest move is to show them
    // what it will look like while they can still choose a different file.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _swatch(AppColors.surfaceMuted, AppColors.hairline),
        const SizedBox(width: 8),
        _swatch(AppColors.navyDeep, AppColors.navy),
      ],
    );
  }

  Widget _swatch(Color background, Color border) {
    return Container(
      width: 64,
      height: 64,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      alignment: Alignment.center,
      child: _loading
          ? HiveLoader(size: 22, color: AppColors.inkFaint)
          : _preview(context),
    );
  }

  Widget _preview(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) {
      return Icon(LucideIcons.image, size: 22, color: AppColors.inkFaint);
    }
    return Padding(
      padding: const EdgeInsets.all(6),
      child: _svg
          // Render SVG logos (e.g. an .svg URL) with the vector renderer so they
          // preview correctly instead of falling back to the placeholder glyph.
          ? SvgPicture.memory(
              bytes,
              fit: BoxFit.contain,
              placeholderBuilder: (_) =>
                  Icon(LucideIcons.image, size: 22, color: AppColors.inkFaint),
            )
          // Decode down to the 64px box (× DPR) instead of the raw upload, so a
          // large PNG doesn't bloat the image cache for a thumbnail.
          : Image.memory(
              bytes,
              fit: BoxFit.contain,
              cacheWidth: (64 * MediaQuery.devicePixelRatioOf(context)).round(),
            ),
    );
  }
}
