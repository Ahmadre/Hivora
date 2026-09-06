import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr/qr.dart';

import '../../core/api/api_client.dart';
import '../../core/repositories/account_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/account_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../sprint/modals/glass_modal.dart'
    show showGlassModal, GlassModalHeader, showGlassToast, GlassToastKind;
import 'account_widgets.dart';
import '../../core/widgets/hive_widgets.dart' show forwardArrow;

/// Renders a QR matrix for an `otpauth://` URI using the pure-Dart [qr]
/// package — no network, no platform channel.
class _QrPainter extends CustomPainter {
  _QrPainter(this.data, this.color);

  final String data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final qr = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final image = QrImage(qr);
    final count = image.moduleCount;
    final cell = size.width / count;
    final paint = Paint()
      ..color = color
      ..isAntiAlias = false;
    for (var x = 0; x < count; x++) {
      for (var y = 0; y < count; y++) {
        if (image.isDark(y, x)) {
          canvas.drawRect(
            Rect.fromLTWH(x * cell, y * cell, cell + 0.5, cell + 0.5),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.data != data || old.color != color;
}

/// A 6-digit segmented OTP entry with auto-advance, backspace-to-previous and
/// paste-fills-all (mirrors the reference `OtpInput`).
class OtpInput extends StatefulWidget {
  const OtpInput({super.key, required this.onChanged, this.autofocus = true});

  final ValueChanged<String> onChanged;
  final bool autofocus;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  static const _length = 6;
  final _controllers = List.generate(_length, (_) => TextEditingController());
  final _nodes = List.generate(_length, (_) => FocusNode());
  // Stable focus nodes for the per-digit KeyboardListeners. Building these inline
  // in build() leaked 6 undisposed FocusNodes on every rebuild (paste/busy/error).
  final _keyNodes = List.generate(
    _length,
    (_) => FocusNode(skipTraversal: true),
  );

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    for (final n in _keyNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _emit() => widget.onChanged(_controllers.map((c) => c.text).join());

  void _onChanged(int i, String value) {
    if (value.length > 1) {
      // Paste: distribute digits across the fields.
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (var j = 0; j < _length; j++) {
        _controllers[j].text = j < digits.length ? digits[j] : '';
      }
      final next = (digits.length).clamp(0, _length - 1);
      _nodes[next].requestFocus();
      _emit();
      setState(() {});
      return;
    }
    if (value.isNotEmpty && i < _length - 1) {
      _nodes[i + 1].requestFocus();
    }
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < _length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                end: i == _length - 1 ? 0 : 8,
              ),
              child: KeyboardListener(
                focusNode: _keyNodes[i],
                onKeyEvent: (event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.backspace &&
                      _controllers[i].text.isEmpty &&
                      i > 0) {
                    _controllers[i - 1].clear();
                    _nodes[i - 1].requestFocus();
                    _emit();
                  }
                },
                child: TextField(
                  controller: _controllers[i],
                  focusNode: _nodes[i],
                  autofocus: widget.autofocus && i == 0,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  maxLength: i == 0 ? _length : 1,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                    fontFamily: AppTheme.fontMono,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    filled: true,
                    fillColor: AppColors.surface.withValues(alpha: 0.7),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusControl,
                      ),
                      borderSide: BorderSide(color: AppColors.hairline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusControl,
                      ),
                      borderSide: const BorderSide(
                        color: AppColors.accent,
                        width: 1.6,
                      ),
                    ),
                  ),
                  onChanged: (v) => _onChanged(i, v),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The 3-step enrolment wizard (Scan → Verify → Recovery). Returns true when
/// 2FA was enabled.
Future<bool?> show2faWizard(BuildContext context, AccountRepository repo) {
  return showGlassModal<bool>(
    context,
    width: 460,
    builder: (_) => _TwoFactorWizard(repo: repo),
  );
}

class _TwoFactorWizard extends StatefulWidget {
  const _TwoFactorWizard({required this.repo});
  final AccountRepository repo;

  @override
  State<_TwoFactorWizard> createState() => _TwoFactorWizardState();
}

enum _Step { scan, verify, recovery }

class _TwoFactorWizardState extends State<_TwoFactorWizard> {
  _Step _step = _Step.scan;
  TotpSetup? _setup;
  String _code = '';
  List<String> _recoveryCodes = const [];
  bool _busy = false;
  bool _saved = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  Future<void> _begin() async {
    setState(() => _busy = true);
    try {
      final setup = await widget.repo.beginTotpSetup();
      if (mounted) setState(() => _setup = setup);
    } on ApiFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_code.length != 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final codes = await widget.repo.verifyTotpSetup(_code);
      if (mounted) {
        setState(() {
          _recoveryCodes = codes;
          _step = _Step.recovery;
        });
      }
    } on ApiFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: (MediaQuery.sizeOf(context).height * 0.86).clamp(0, 720),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassModalHeader(
            icon: LucideIcons.shieldCheck,
            title: context.t('twofa.title'),
            subtitle: switch (_step) {
              _Step.scan => context.t('twofa.step1'),
              _Step.verify => context.t('twofa.step2'),
              _Step.recovery => context.t('twofa.step3'),
            },
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _body(),
              ),
            ),
          ),
          _footer(),
        ],
      ),
    );
  }

  Widget _body() {
    if (_error != null && _setup == null) {
      return _errorBox(_error!);
    }
    return switch (_step) {
      _Step.scan => _scanBody(),
      _Step.verify => _verifyBody(),
      _Step.recovery => _recoveryBody(),
    };
  }

  Widget _errorBox(String message) => Padding(
    key: const ValueKey('err'),
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: AccountNote(
      text: message,
      icon: LucideIcons.triangleAlert,
      tone: AccountNoteTone.danger,
    ),
  );

  Widget _scanBody() {
    final setup = _setup;
    return Column(
      key: const ValueKey('scan'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.t('twofa.scanHint'),
          style: TextStyle(
            fontSize: 12.5,
            height: 1.45,
            color: AppColors.inkSoft,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.hairline),
            ),
            child: setup == null
                ? const SizedBox(
                    width: 180,
                    height: 180,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : SizedBox(
                    width: 180,
                    height: 180,
                    child: CustomPaint(
                      painter: _QrPainter(
                        setup.otpauthUri,
                        const Color(0xFF1A1830),
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          context.t('twofa.manualKey'),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppColors.inkSoft,
          ),
        ),
        const SizedBox(height: 6),
        if (setup != null)
          _CopyField(label: setup.groupedSecret, copyValue: setup.secret),
      ],
    );
  }

  Widget _verifyBody() {
    return Column(
      key: const ValueKey('verify'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.t('twofa.verifyHint'),
          style: TextStyle(
            fontSize: 12.5,
            height: 1.45,
            color: AppColors.inkSoft,
          ),
        ),
        const SizedBox(height: 18),
        OtpInput(onChanged: (v) => setState(() => _code = v)),
        if (_error != null) ...[
          const SizedBox(height: 14),
          AccountNote(
            text: _error!,
            icon: LucideIcons.triangleAlert,
            tone: AccountNoteTone.danger,
          ),
        ],
      ],
    );
  }

  Widget _recoveryBody() {
    return Column(
      key: const ValueKey('recovery'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountNote(
          text: context.t('twofa.recoveryHint'),
          icon: LucideIcons.info,
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              for (final code in _recoveryCodes)
                SelectableText(
                  code,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontMono,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            AccountActionButton(
              label: context.t('twofa.copyAll'),
              icon: LucideIcons.copy,
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: _recoveryCodes.join('\n')),
                );
                showGlassToast(
                  context,
                  context.t('twofa.codesCopied'),
                  kind: GlassToastKind.success,
                );
              },
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _saved = !_saved),
                child: Row(
                  children: [
                    _MiniCheck(on: _saved),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.t('twofa.saved'),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _footer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.hairline.withValues(alpha: 0.6)),
        ),
      ),
      child: Row(
        children: [
          const Spacer(),
          TextButton(
            onPressed: _busy
                ? null
                : () => Navigator.of(context).maybePop(_saved),
            child: Text(
              context.t(
                _step == _Step.recovery ? 'twofa.close' : 'common.cancel',
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (_step != _Step.recovery)
            FilledButton.icon(
              onPressed: _busy || (_step == _Step.verify && _code.length != 6)
                  ? null
                  : () {
                      if (_step == _Step.scan) {
                        setState(() => _step = _Step.verify);
                      } else {
                        _verify();
                      }
                    },
              style: _primaryStyle(),
              icon: _busy
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(forwardArrow(context), size: 15),
              label: Text(
                context.t(
                  _step == _Step.scan
                      ? 'twofa.continueStep'
                      : 'twofa.verifyEnable',
                ),
              ),
            )
          else
            FilledButton.icon(
              onPressed: _saved
                  ? () => Navigator.of(context).maybePop(true)
                  : null,
              style: _primaryStyle(),
              icon: const Icon(LucideIcons.check, size: 15),
              label: Text(context.t('twofa.finish')),
            ),
        ],
      ),
    );
  }

  ButtonStyle _primaryStyle() => FilledButton.styleFrom(
    backgroundColor: AppColors.navy,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
    ),
  );
}

/// Manage modal: shows remaining recovery codes count + regenerate (requires a
/// current code). Returns the new remaining count if regenerated.
Future<void> show2faManage(BuildContext context, AccountRepository repo) {
  return showGlassModal<void>(
    context,
    width: 440,
    builder: (_) => _CodeGatedAction(
      repo: repo,
      icon: LucideIcons.keyRound,
      title: context.t('twofa.manageTitle'),
      subtitle: context.t('twofa.manageSubtitle'),
      confirmLabel: context.t('twofa.regenerate'),
      onConfirm: (code) => repo.regenerateRecoveryCodes(code),
      showCodes: true,
    ),
  );
}

/// Disable modal: requires a current TOTP/recovery code. Returns true when off.
Future<bool?> show2faDisable(BuildContext context, AccountRepository repo) {
  return showGlassModal<bool>(
    context,
    width: 440,
    builder: (_) => _CodeGatedAction(
      repo: repo,
      icon: LucideIcons.shieldOff,
      title: context.t('twofa.disableTitle'),
      subtitle: context.t('twofa.disableSubtitle'),
      confirmLabel: context.t('twofa.disableButton'),
      danger: true,
      onConfirm: (code) async {
        await repo.disableTotp(code);
        return const <String>[];
      },
    ),
  );
}

/// Shared body for the "enter a code to do X" management modals.
class _CodeGatedAction extends StatefulWidget {
  const _CodeGatedAction({
    required this.repo,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.confirmLabel,
    required this.onConfirm,
    this.danger = false,
    this.showCodes = false,
  });

  final AccountRepository repo;
  final IconData icon;
  final String title;
  final String subtitle;
  final String confirmLabel;
  final Future<List<String>> Function(String code) onConfirm;
  final bool danger;
  final bool showCodes;

  @override
  State<_CodeGatedAction> createState() => _CodeGatedActionState();
}

class _CodeGatedActionState extends State<_CodeGatedAction> {
  String _code = '';
  bool _busy = false;
  String? _error;
  List<String>? _result;

  Future<void> _confirm() async {
    if (_code.length < 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final codes = await widget.onConfirm(_code);
      if (!mounted) return;
      if (widget.showCodes) {
        setState(() => _result = codes);
      } else {
        Navigator.of(context).maybePop(true);
      }
    } on ApiFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: widget.icon,
          title: widget.title,
          subtitle: widget.subtitle,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
          child: _result != null
              ? _codesView(_result!)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OtpInput(onChanged: (v) => setState(() => _code = v)),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      AccountNote(
                        text: _error!,
                        icon: LucideIcons.triangleAlert,
                        tone: AccountNoteTone.danger,
                      ),
                    ],
                  ],
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: AppColors.hairline.withValues(alpha: 0.6)),
            ),
          ),
          child: Row(
            children: [
              const Spacer(),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).maybePop(),
                child: Text(
                  context.t(_result != null ? 'twofa.close' : 'common.cancel'),
                ),
              ),
              const SizedBox(width: 8),
              if (_result == null)
                FilledButton.icon(
                  onPressed: _busy || _code.length < 6 ? null : _confirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.danger
                        ? AppColors.danger
                        : AppColors.navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusControl,
                      ),
                    ),
                  ),
                  icon: _busy
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          widget.danger
                              ? LucideIcons.shieldOff
                              : LucideIcons.check,
                          size: 15,
                        ),
                  label: Text(widget.confirmLabel),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _codesView(List<String> codes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountNote(
          text: context.t('twofa.newCodesHint'),
          icon: LucideIcons.info,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              for (final code in codes)
                SelectableText(
                  code,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontMono,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AccountActionButton(
          label: context.t('twofa.copyAll'),
          icon: LucideIcons.copy,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: codes.join('\n')));
            showGlassToast(
              context,
              context.t('twofa.codesCopied'),
              kind: GlassToastKind.success,
            );
          },
        ),
      ],
    );
  }
}

class _CopyField extends StatelessWidget {
  const _CopyField({required this.label, required this.copyValue});
  final String label;
  final String copyValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              label,
              style: const TextStyle(
                fontFamily: AppTheme.fontMono,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(LucideIcons.copy, size: 16, color: AppColors.inkSoft),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: copyValue));
              showGlassToast(
                context,
                context.t('twofa.keyCopied'),
                kind: GlassToastKind.success,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MiniCheck extends StatelessWidget {
  const _MiniCheck({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: on ? AppColors.accent : AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: on ? AppColors.accent : AppColors.hairline),
      ),
      child: on
          ? const Icon(LucideIcons.check, size: 13, color: Color(0xFF2A2410))
          : null,
    );
  }
}
