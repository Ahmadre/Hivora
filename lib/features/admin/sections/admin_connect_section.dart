import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_client.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../sprint/modals/glass_modal.dart';
import '../admin_form_helpers.dart';

/// Admin → Connect (Hinata Connect enrolment).
///
/// Self-managed section (no draft/save-bar): enrols this instance with the
/// central Hinata Connect gateway using a one-time token minted in the Connect
/// portal, shows the live enrolment + domain-verification state, and can drop
/// the local enrolment. Push works as soon as the instance is enrolled; the
/// deep-link web fallback additionally requires the domain proof to pass.
class AdminConnectSection extends StatefulWidget {
  const AdminConnectSection({super.key});

  @override
  State<AdminConnectSection> createState() => _AdminConnectSectionState();
}

class _AdminConnectSectionState extends State<AdminConnectSection> {
  late final AdminRepository _repo = context.read<AdminRepository>();
  final TextEditingController _token = TextEditingController();

  Map<String, dynamic>? _status;
  bool _loading = true;
  bool _busy = false;
  String? _errorKey;

  // Automated "Jetzt verbinden" handshake state.
  Timer? _pollTimer;
  bool _handshakeStarting = false;
  bool _waiting = false;
  String? _handshakePortalUrl;

  bool get _enrolled => _status?['enrolled'] == true;
  bool get _verified => _status?['domainVerified'] == true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _token.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    try {
      final status = await _repo.connectStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
      // Resume the waiting UI if a handshake was still in flight (e.g. the admin
      // reopened the app before approving in the portal).
      if (status['enrolled'] != true && status['handshakePending'] == true) {
        _waiting = true;
        _handshakePortalUrl = status['handshakePortalUrl'] as String?;
        _startPolling();
      }
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorKey = failure.message;
      });
    }
  }

  // ── Automated "Jetzt verbinden" handshake ─────────────────────────────────

  Future<void> _startHandshake() async {
    setState(() => _handshakeStarting = true);
    try {
      final res = await _repo.connectHandshakeStart();
      final url = res['portalUrl'] as String?;
      if (!mounted) return;
      if (url == null || url.isEmpty) {
        // Gateway has no portal URL configured — fall back to the token flow.
        showGlassErrorToast(context, context.t('admin.connectAutoUnavailable'));
        return;
      }
      final launched = await _openUrl(url);
      if (!mounted) return;
      setState(() {
        _waiting = true;
        _handshakePortalUrl = url;
      });
      _startPolling();
      if (!launched) {
        showGlassToast(context, context.t('admin.connectOpenPortalManually'));
      }
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      showGlassErrorToast(context, context.t(failure.message));
    } finally {
      if (mounted) setState(() => _handshakeStarting = false);
    }
  }

  Future<bool> _openUrl(String url) async {
    try {
      return await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollOnce());
  }

  Future<void> _pollOnce() async {
    try {
      final status = await _repo.connectStatus();
      if (!mounted) return;
      final enrolled = status['enrolled'] == true;
      final pending = status['handshakePending'] == true;
      setState(() => _status = status);
      if (enrolled) {
        _stopWaiting();
        showGlassToast(
          context,
          context.t('admin.connectEnrolledToast'),
          kind: GlassToastKind.success,
        );
      } else if (!pending) {
        // The server dropped the handshake (expired / denied / cancelled).
        _stopWaiting();
        showGlassToast(context, context.t('admin.connectHandshakeEnded'));
      }
    } on ApiFailure {
      // Transient — keep polling; the timer fires again shortly.
    }
  }

  void _stopWaiting() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (mounted) {
      setState(() {
        _waiting = false;
        _handshakePortalUrl = null;
      });
    }
  }

  Future<void> _cancelHandshake() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    setState(() => _busy = true);
    try {
      final status = await _repo.connectHandshakeCancel();
      if (!mounted) return;
      setState(() {
        _status = status;
        _waiting = false;
        _handshakePortalUrl = null;
      });
    } on ApiFailure {
      if (!mounted) return;
      setState(() {
        _waiting = false;
        _handshakePortalUrl = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enroll() async {
    final token = _token.text.trim();
    if (token.isEmpty) return;
    setState(() => _busy = true);
    try {
      final status = await _repo.connectEnroll(token);
      if (!mounted) return;
      _token.clear();
      setState(() => _status = status);
      showGlassToast(
        context,
        context.t('admin.connectEnrolledToast'),
        kind: GlassToastKind.success,
      );
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      showGlassErrorToast(context, context.t(failure.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      final status = await _repo.connectStatus();
      if (!mounted) return;
      setState(() => _status = status);
      if (status['domainVerified'] == true) {
        showGlassToast(
          context,
          context.t('admin.connectVerifiedToast'),
          kind: GlassToastKind.success,
        );
      } else {
        showGlassToast(context, context.t('admin.connectStillPendingToast'));
      }
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      showGlassErrorToast(context, context.t(failure.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    try {
      final status = await _repo.connectDisconnect();
      if (!mounted) return;
      setState(() => _status = status);
      showGlassToast(context, context.t('admin.connectDisconnectedToast'));
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      showGlassErrorToast(context, context.t(failure.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: HiveLoader(size: 28)),
      );
    }
    if (_errorKey != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            children: [
              Text(
                context.t(_errorKey!),
                style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(LucideIcons.refreshCw, size: 15),
                label: Text(context.t('common.retry')),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Status ────────────────────────────────────────────────────────
        AdminSectionCard(
          icon: LucideIcons.radioTower,
          title: context.t('admin.connectStatusTitle'),
          subtitle: context.t('admin.connectStatusHint'),
          children: [
            _StatusRow(
              label: context.t('admin.connectEnrollment'),
              ok: _enrolled,
              okText: context.t('admin.connectEnrolled'),
              pendingText: context.t('admin.connectNotEnrolled'),
            ),
            if (_enrolled) ...[
              const SizedBox(height: 10),
              _StatusRow(
                label: context.t('admin.connectDomainProof'),
                ok: _verified,
                okText: context.t('admin.connectVerified'),
                pendingText: context.t('admin.connectPending'),
              ),
              const SizedBox(height: 10),
              _MonoRow(
                label: context.t('admin.connectServerId'),
                value: (_status?['serverId'] as String?) ?? '—',
              ),
              _MonoRow(
                label: context.t('admin.connectGateway'),
                value: (_status?['gatewayBaseUrl'] as String?) ?? '—',
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                if (_enrolled && !_verified)
                  FilledButton.icon(
                    onPressed: _busy ? null : _refresh,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(LucideIcons.badgeCheck, size: 16),
                    label: Text(context.t('admin.connectCheckNow')),
                  ),
                if (_enrolled && !_verified) const SizedBox(width: 10),
                if (_enrolled)
                  TextButton.icon(
                    onPressed: _busy ? null : _disconnect,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.danger,
                    ),
                    icon: const Icon(LucideIcons.unplug, size: 16),
                    label: Text(context.t('admin.connectDisconnect')),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Automated "Jetzt verbinden" ───────────────────────────────────
        if (!_enrolled) ...[
          AdminSectionCard(
            icon: LucideIcons.sparkles,
            title: context.t('admin.connectAutoTitle'),
            subtitle: context.t('admin.connectAutoHint'),
            children: [
              if (_waiting) ...[
                Row(
                  children: [
                    const HiveLoader(size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.t('admin.connectWaiting'),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (_handshakePortalUrl != null)
                      FilledButton.icon(
                        onPressed: () => _openUrl(_handshakePortalUrl!),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.navy,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(LucideIcons.externalLink, size: 16),
                        label: Text(context.t('admin.connectReopenPortal')),
                      ),
                    if (_handshakePortalUrl != null) const SizedBox(width: 10),
                    TextButton(
                      onPressed: _busy ? null : _cancelHandshake,
                      child: Text(context.t('common.cancel')),
                    ),
                  ],
                ),
              ] else
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: _handshakeStarting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: HiveLoader(strokeWidth: 2),
                        )
                      : FilledButton.icon(
                          onPressed: _startHandshake,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.navy,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(LucideIcons.zap, size: 16),
                          label: Text(context.t('admin.connectAutoAction')),
                        ),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],

        // ── Manual enrolment (paste token) ────────────────────────────────
        if (!_enrolled)
          AdminSectionCard(
            icon: LucideIcons.ticket,
            title: context.t('admin.connectEnrollTitle'),
            subtitle: context.t('admin.connectEnrollHint'),
            children: [
              TextFormField(
                controller: _token,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                style: const TextStyle(fontFamily: AppTheme.fontMono),
                decoration: InputDecoration(
                  labelText: context.t('admin.connectTokenLabel'),
                  helperText: context.t('admin.connectTokenHelper'),
                ),
                onFieldSubmitted: (_) => _enroll(),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: HiveLoader(strokeWidth: 2),
                      )
                    : FilledButton.icon(
                        onPressed: _enroll,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.navy,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(LucideIcons.plug, size: 16),
                        label: Text(context.t('admin.connectEnrollAction')),
                      ),
              ),
            ],
          ),

        // ── Domain proof details ──────────────────────────────────────────
        if (_enrolled && !_verified) ...[
          const SizedBox(height: 16),
          AdminSectionCard(
            icon: LucideIcons.globe,
            title: context.t('admin.connectChallengeTitle'),
            subtitle: context.t('admin.connectChallengeHint'),
            children: [
              _MonoRow(
                label: context.t('admin.connectChallengePath'),
                value: '/.well-known/hinata-connect-challenge',
                copyable: true,
              ),
              _MonoRow(
                label: context.t('admin.connectChallengeValue'),
                value: (_status?['challenge'] as String?) ?? '—',
                copyable: true,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A label + ok/pending badge line.
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.ok,
    required this.okText,
    required this.pendingText,
  });

  final String label;
  final bool ok;
  final String okText;
  final String pendingText;

  @override
  Widget build(BuildContext context) {
    final color = ok ? AppColors.success : AppColors.warning;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                ok ? LucideIcons.circleCheck : LucideIcons.clock,
                size: 13,
                color: color,
              ),
              const SizedBox(width: 5),
              Text(
                ok ? okText : pendingText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A label + monospaced value line, optionally copyable.
class _MonoRow extends StatelessWidget {
  const _MonoRow({
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                fontFamily: AppTheme.fontMono,
                color: AppColors.ink,
              ),
            ),
          ),
          if (copyable) ...[
            const SizedBox(width: 6),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: context.t('common.copy'),
              icon: Icon(LucideIcons.copy, size: 14, color: AppColors.inkSoft),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (context.mounted) {
                  showGlassToast(context, context.t('common.copied'));
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}
