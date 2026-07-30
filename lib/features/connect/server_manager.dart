import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/repositories/meta_repository.dart';
import '../../core/blocs/app_config_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/models/server_profile.dart';
import '../../core/storage/app_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/status_widgets.dart';
import '../sprint/modals/glass_modal.dart'
    show
        glassInputDecoration,
        kGlassPopoverBreakpoint,
        showGlassAnchoredPopover,
        showGlassBottomSheet,
        showGlassConfirm;

/// Opens the Liquid-Glass **server manager** — lists every saved backend with a
/// live status dot + ping, lets the user switch or (in edit mode) forget
/// servers, and flows into an "add server" connection test. Surfaced from the
/// login screen and the account → appearance section.
///
/// Responsive like the detail pickers: on tablet/desktop it anchors as a glass
/// popover beneath the tapped trigger (the [context]'s render box, or an
/// explicit [anchor] rect); on phone it slides up as a bottom sheet.
///
/// Providers are captured from the caller's [context] and handed to the sheet so
/// the lookups don't depend on the root-navigator subtree the sheet renders in.
/// Pass [startOnAdd] to open straight on the "add server" page.
Future<void> showServerManager(
  BuildContext context, {
  bool startOnAdd = false,
  Rect? anchor,
}) {
  Widget builder(BuildContext _) => _ServerManagerSheet(
    repo: context.read<MetaRepository>(),
    storage: context.read<AppStorage>(),
    appConfig: context.read<AppConfigBloc>(),
    startOnAdd: startOnAdd,
  );
  final wide = MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint;
  final rect = anchor ?? _anchorOf(context);
  if (wide && rect != null) {
    return showGlassAnchoredPopover<void>(
      context,
      anchorRect: rect,
      width: 420,
      maxHeight: 560,
      builder: builder,
    );
  }
  return showGlassBottomSheet<void>(context, maxWidth: 480, builder: builder);
}

/// Global rect of the [context]'s render box — the trigger we anchor the
/// desktop popover beneath. Null when the element has no laid-out box.
Rect? _anchorOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Which page of the single sheet is showing.
enum _Page { manage, add }

/// Live reachability of one saved server, resolved by probing on sheet open.
enum _Reach { checking, online, offline }

class _RowStatus {
  const _RowStatus(this.reach, this.ms);
  const _RowStatus.checking() : this(_Reach.checking, null);
  const _RowStatus.offline() : this(_Reach.offline, null);
  const _RowStatus.online(int ms) : this(_Reach.online, ms);

  final _Reach reach;
  final int? ms;
}

class _ServerManagerSheet extends StatefulWidget {
  const _ServerManagerSheet({
    required this.repo,
    required this.storage,
    required this.appConfig,
    required this.startOnAdd,
  });

  final MetaRepository repo;
  final AppStorage storage;
  final AppConfigBloc appConfig;
  final bool startOnAdd;

  @override
  State<_ServerManagerSheet> createState() => _ServerManagerSheetState();
}

class _ServerManagerSheetState extends State<_ServerManagerSheet> {
  late _Page _page = widget.startOnAdd ? _Page.add : _Page.manage;
  bool _editing = false;

  /// URL currently being switched to (drives the in-row connecting pulse).
  String? _connectingUrl;

  /// Saved servers, current first.
  late List<ServerProfile> _servers;

  /// Live status per server URL, filled in as the parallel probes land.
  final Map<String, _RowStatus> _status = {};

  @override
  void initState() {
    super.initState();
    _reload();
    _probeAll();
  }

  void _reload() {
    final current = widget.storage.serverUrl;
    final all = widget.storage.servers.toList();
    all.sort((a, b) {
      if (a.url == current) return -1;
      if (b.url == current) return 1;
      return 0;
    });
    _servers = all;
  }

  /// Fires a reachability probe at every saved server in parallel; each row
  /// flips from "checking" to its real ping (or "offline") as results arrive.
  void _probeAll() {
    for (final server in _servers) {
      _status[server.url] = const _RowStatus.checking();
      widget.repo.probeServer(server.url).then((probe) {
        if (!mounted) return;
        setState(() {
          _status[server.url] = probe == null
              ? const _RowStatus.offline()
              : _RowStatus.online(probe.ms);
        });
      });
    }
  }

  Future<void> _pick(String url) async {
    // Tapping the active server is a no-op beyond closing the sheet.
    if (url == widget.storage.serverUrl) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _connectingUrl = url);
    // Let the connecting pulse breathe before the route changes under us.
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    Navigator.of(context).pop();
    await widget.storage.setCurrentServer(url);
    // AppConfig re-verifies the new backend; the router then shows the
    // connecting splash and routes onward (sign-in or straight into the app).
    widget.appConfig.add(const AppConfigStarted());
  }

  Future<void> _delete(ServerProfile server) async {
    final ok = await showGlassConfirm(
      context,
      icon: LucideIcons.trash2,
      title: context.t('server.remove'),
      message: context.t(
        'server.removeConfirm',
        variables: {'name': server.displayName},
      ),
      confirmLabel: context.t('server.remove'),
      destructive: true,
      confirmIcon: LucideIcons.trash2,
    );
    if (ok != true || !mounted) return;
    await widget.storage.removeServer(server.url);
    if (!mounted) return;
    setState(() {
      _status.remove(server.url);
      _reload();
      if (_servers.length <= 1) _editing = false;
    });
  }

  /// Persists a freshly tested server, makes it current and routes to it.
  Future<void> _saveAndConnect(String url, String name) async {
    await widget.storage.upsertServer(ServerProfile(url: url, label: name));
    await widget.storage.setCurrentServer(url);
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.appConfig.add(const AppConfigStarted());
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
      child: _page == _Page.add
          ? _AddServerPage(
              repo: widget.repo,
              onBack: () => setState(() => _page = _Page.manage),
              onSave: _saveAndConnect,
            )
          : _buildManage(context),
    );
  }

  Widget _buildManage(BuildContext context) {
    final current = widget.storage.serverUrl;
    final canEdit = _servers.length > 1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 0, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('server.manageTitle'),
                      style: const TextStyle(
                        fontFamily: AppTheme.fontBrand,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      context.t('server.manageSubtitle'),
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              if (canEdit)
                TextButton(
                  onPressed: () => setState(() => _editing = !_editing),
                  child: Text(
                    _editing
                        ? context.t('common.done')
                        : context.t('common.edit'),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _editing
                          ? AppColors.accentStrong
                          : AppColors.inkSoft,
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (final server in _servers)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _ServerRow(
              server: server,
              status: _status[server.url] ?? const _RowStatus.checking(),
              active: server.url == current,
              editing: _editing,
              connecting: _connectingUrl == server.url,
              onTap: () => _pick(server.url),
              onDelete: () => _delete(server),
            ),
          ),
        const SizedBox(height: 5),
        _AddServerButton(onTap: () => setState(() => _page = _Page.add)),
      ],
    );
  }
}

/// A pulsing status dot — solid core with glow plus an expanding ring (online /
/// connecting only). Honours reduced-motion (no ring animation).
class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.color, required this.pulse});

  final Color color;
  final bool pulse;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final ring = widget.pulse && !reduceMotion;
    return SizedBox(
      width: 9,
      height: 9,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (ring)
            AnimatedBuilder(
              animation: _c,
              builder: (_, _) => Opacity(
                opacity: 0.8 * (1 - _c.value),
                child: Transform.scale(
                  scale: 0.6 + 1.8 * _c.value,
                  child: Container(
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.6),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One row in the manage list: icon tile, name + Self/Cloud badge, status line,
/// mono host, and a trailing affordance (active check / chevron / trash).
class _ServerRow extends StatelessWidget {
  const _ServerRow({
    required this.server,
    required this.status,
    required this.active,
    required this.editing,
    required this.connecting,
    required this.onTap,
    required this.onDelete,
  });

  final ServerProfile server;
  final _RowStatus status;
  final bool active;
  final bool editing;
  final bool connecting;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final offline = status.reach == _Reach.offline;
    final tappable = !editing && !offline;

    final statusColor = connecting
        ? AppColors.accentStrong
        : switch (status.reach) {
            _Reach.online => AppColors.success,
            _Reach.offline => AppColors.danger,
            _Reach.checking => AppColors.inkFaint,
          };
    final statusText = connecting
        ? context.t('server.connecting')
        : switch (status.reach) {
            _Reach.online => context.t(
              'server.ms',
              variables: {'n': status.ms ?? 0},
            ),
            _Reach.offline => context.t('server.offline'),
            _Reach.checking => context.t('server.checking'),
          };

    return Opacity(
      opacity: offline && !editing ? 0.62 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: tappable ? onTap : null,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              color: active ? AppColors.accentSoft : AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: active ? AppColors.accentLine : AppColors.hairline,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.accent.withValues(alpha: 0.16)
                        : AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: active
                          ? AppColors.accent.withValues(alpha: 0.32)
                          : AppColors.hairline2,
                    ),
                  ),
                  child: Icon(
                    LucideIcons.server,
                    size: 21,
                    color: active ? AppColors.accentStrong : AppColors.inkSoft,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              server.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          PillChip(
                            label: server.isCloud
                                ? context.t('server.cloud')
                                : context.t('server.self'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _StatusDot(
                            color: statusColor,
                            pulse: connecting || status.reach != _Reach.offline,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Flexible(
                            child: Text(
                              server.host,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: AppTheme.fontMono,
                                fontSize: 12,
                                color: AppColors.inkFaint,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _trailing(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _trailing(BuildContext context) {
    if (connecting) {
      return const SizedBox(
        width: 26,
        height: 26,
        child: Center(child: HiveLoader(size: 20, strokeWidth: 2)),
      );
    }
    if (editing && !active) {
      return IconButton(
        onPressed: onDelete,
        visualDensity: VisualDensity.compact,
        tooltip: context.t('server.remove'),
        icon: const Icon(LucideIcons.trash2, size: 18, color: AppColors.danger),
      );
    }
    if (active) {
      return Container(
        width: 26,
        height: 26,
        decoration: const BoxDecoration(
          color: AppColors.accent,
          shape: BoxShape.circle,
        ),
        child: const Icon(LucideIcons.check, size: 16, color: Colors.white),
      );
    }
    if (status.reach == _Reach.offline) return const SizedBox.shrink();
    return Icon(LucideIcons.chevronRight, size: 18, color: AppColors.inkFaint);
  }
}

/// Dashed-style "add server" button at the foot of the manage list.
class _AddServerButton extends StatelessWidget {
  const _AddServerButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                LucideIcons.plus,
                size: 19,
                color: AppColors.accentStrong,
              ),
              const SizedBox(width: 9),
              Text(
                context.t('server.addServer'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Phase of the add-server connection test.
enum _Phase { input, testing, ok, error }

/// The "add server" page: enter a URL, test the connection (real
/// `/api/v1/meta` probe), then confirm a display name and connect.
class _AddServerPage extends StatefulWidget {
  const _AddServerPage({
    required this.repo,
    required this.onBack,
    required this.onSave,
  });

  final MetaRepository repo;
  final VoidCallback onBack;
  final Future<void> Function(String url, String name) onSave;

  @override
  State<_AddServerPage> createState() => _AddServerPageState();
}

class _AddServerPageState extends State<_AddServerPage> {
  final _url = TextEditingController();
  final _name = TextEditingController();
  _Phase _phase = _Phase.input;
  ServerProbe? _probe;

  /// The normalized URL of the last successful probe (what we'll save).
  String _probedUrl = '';

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    super.dispose();
  }

  String _normalize(String raw) {
    var v = raw.trim();
    if (v.isEmpty) return v;
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(v)) {
      v = 'https://$v';
    }
    if (v.endsWith('/')) v = v.substring(0, v.length - 1);
    return v;
  }

  Future<void> _test() async {
    final url = _normalize(_url.text);
    if (url.isEmpty) return;
    setState(() {
      _phase = _Phase.testing;
      _probe = null;
    });
    final probe = await widget.repo.probeServer(url);
    if (!mounted) return;
    if (probe == null) {
      setState(() => _phase = _Phase.error);
      return;
    }
    final host = Uri.tryParse(url)?.host ?? url;
    setState(() {
      _probe = probe;
      _probedUrl = url;
      _name.text = (probe.org?.trim().isNotEmpty ?? false)
          ? probe.org!.trim()
          : host;
      _phase = _Phase.ok;
    });
  }

  void _onUrlChanged() {
    // Always rebuild so the "test connection" button's enabled state tracks the
    // field (a no-op `if` would leave it greyed out on the first keystroke,
    // since the phase is already `input`). Also drop any stale probe result once
    // the URL is edited after a test.
    setState(() {
      if (_phase != _Phase.input) {
        _phase = _Phase.input;
        _probe = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header with back button.
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 2, 0, 14),
          child: Row(
            children: [
              IconButton(
                onPressed: widget.onBack,
                visualDensity: VisualDensity.compact,
                icon: const Icon(LucideIcons.arrowLeft, size: 20),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('server.addTitle'),
                      style: const TextStyle(
                        fontFamily: AppTheme.fontBrand,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.t('server.addSubtitle'),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.t('connect.serverUrl'),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkSoft,
                ),
              ),
              const SizedBox(height: 7),
              TextField(
                controller: _url,
                autofocus: true,
                enabled: _phase != _Phase.testing,
                keyboardType: TextInputType.url,
                autofillHints: const [AutofillHints.url],
                autocorrect: false,
                textInputAction: TextInputAction.done,
                style: const TextStyle(
                  fontFamily: AppTheme.fontMono,
                  fontSize: 14,
                ),
                decoration: glassInputDecoration(hint: 'server.hinata.com')
                    .copyWith(
                      prefixIcon: const Icon(LucideIcons.server, size: 18),
                    ),
                onChanged: (_) => _onUrlChanged(),
                onSubmitted: (_) => _test(),
              ),
              const SizedBox(height: 14),
              _result(context),
              const SizedBox(height: 18),
              _cta(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _result(BuildContext context) {
    switch (_phase) {
      case _Phase.testing:
        return _card(
          tint: AppColors.accent,
          child: Row(
            children: [
              const HiveLoader(size: 22, strokeWidth: 2),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('server.testing'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.t('server.testingHint'),
                      style: TextStyle(
                        fontFamily: AppTheme.fontMono,
                        fontSize: 11.5,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      case _Phase.ok:
        final probe = _probe!;
        return _card(
          tint: AppColors.success,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.check,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    context.t('server.reachable'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    LucideIcons.zap,
                    size: 13,
                    color: AppColors.accentStrong,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    context.t('server.ms', variables: {'n': probe.ms}),
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 12,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    LucideIcons.shieldCheck,
                    size: 14,
                    color: probe.tls ? AppColors.success : AppColors.danger,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    probe.tls
                        ? context.t('server.tlsValid')
                        : context.t('server.tlsNone'),
                    style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                  ),
                  const SizedBox(width: 18),
                  Text(
                    'hinata ${probe.version}',
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 12.5,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ],
              ),
              Divider(height: 26, color: AppColors.hairline),
              Text(
                context.t('server.displayName'),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkSoft,
                ),
              ),
              const SizedBox(height: 7),
              TextField(controller: _name, decoration: glassInputDecoration()),
            ],
          ),
        );
      case _Phase.error:
        return _card(
          tint: AppColors.danger,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                LucideIcons.triangleAlert,
                size: 20,
                color: AppColors.danger,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('server.notReachable'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.danger,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      context.t('server.notReachableHint'),
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      case _Phase.input:
        return const SizedBox.shrink();
    }
  }

  Widget _card({required Color tint, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.soft(tint),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tint.withValues(alpha: 0.3)),
      ),
      child: child,
    );
  }

  Widget _cta(BuildContext context) {
    if (_phase == _Phase.ok) {
      return FilledButton.icon(
        onPressed: () => widget.onSave(
          _probedUrl,
          _name.text.trim().isEmpty
              ? (Uri.tryParse(_probedUrl)?.host ?? _probedUrl)
              : _name.text.trim(),
        ),
        style: _ctaStyle(),
        icon: const Icon(LucideIcons.plus, size: 18),
        label: Text(context.t('server.connectAndSave')),
      );
    }
    final hasUrl = _url.text.trim().isNotEmpty;
    final label = switch (_phase) {
      _Phase.testing => context.t('server.testing'),
      _Phase.error => context.t('common.retry'),
      _ => context.t('server.testConnection'),
    };
    return FilledButton(
      onPressed: hasUrl && _phase != _Phase.testing ? _test : null,
      style: _ctaStyle(),
      child: Text(label),
    );
  }

  ButtonStyle _ctaStyle() => FilledButton.styleFrom(
    backgroundColor: AppColors.accent,
    foregroundColor: const Color(0xFF211603),
    minimumSize: const Size.fromHeight(52),
    textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  );
}
