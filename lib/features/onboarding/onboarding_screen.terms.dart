part of 'onboarding_screen.dart';

/// The rules summarised on the gate, one line each. Keys resolve to
/// `terms.rule.<id>` — the summary a person actually reads, above the link to
/// the full document nobody does.
const _termsRules = <({String id, IconData icon})>[
  (id: 'respect', icon: LucideIcons.users),
  (id: 'illegal', icon: LucideIcons.ban),
  (id: 'privacy', icon: LucideIcons.lock),
  (id: 'report', icon: LucideIcons.flag),
];

/// The one-time content-terms gate: nobody creates content on this server until
/// they have accepted the rules for it.
///
/// A full route rather than a dialog, and a router gate rather than a check at
/// the first composer, because the requirement is that it *cannot be skipped* —
/// Google's UGC policy asks for acceptance before a user can create or upload
/// content and its moderation guidance spells out that the step must not be
/// skippable, and an Apple reviewer looks for the same EULA-with-zero-tolerance
/// step. A modal has a barrier, a back gesture and a route underneath; a gate
/// has none of those, and it is the same mechanism the app already uses for
/// connect / setup / onboarding / login, so it inherits their deep-link parking
/// for free.
///
/// Refusing is a real option and has to stay one: someone who does not accept
/// signs out. The only thing this screen must never offer is a way past it.
///
/// Acceptance is recorded per server **and** per user (see
/// [AppStorage.termsAcceptedBy]) — on device, because the server has no field
/// for it yet.
class TermsGateScreen extends StatefulWidget {
  const TermsGateScreen({
    super.key,
    required this.storage,
    required this.userId,
    required this.onAccepted,
  });

  final AppStorage storage;

  /// The signed-in user's id — acceptance is theirs, not the device's.
  final String userId;

  final VoidCallback onAccepted;

  @override
  State<TermsGateScreen> createState() => _TermsGateScreenState();
}

class _TermsGateScreenState extends State<TermsGateScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ambient;
  bool _accepted = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  @override
  void dispose() {
    _ambient.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    if (!_accepted || _saving) return;
    setState(() => _saving = true);
    await widget.storage.setTermsAccepted(widget.userId);
    if (mounted) widget.onAccepted();
  }

  @override
  Widget build(BuildContext context) {
    // canPop: false so the Android back gesture cannot dismiss the gate. The
    // router redirect would bounce straight back anyway; this stops the frame
    // of another screen that would otherwise flash on the way.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: _bgMid,
        body: Stack(
          children: [
            const Positioned.fill(child: _BackgroundGradient()),
            Positioned.fill(child: _Orbs(animation: _ambient)),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _header(context),
                        const SizedBox(height: 24),
                        _GlassCard(child: _rules(context)),
                        const SizedBox(height: 20),
                        _consent(context),
                        const SizedBox(height: 18),
                        _AcceptButton(
                          enabled: _accepted && !_saving,
                          busy: _saving,
                          onTap: _accept,
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          // Refusing is a real choice, and the only honest one
                          // to offer: nobody is forced to agree, but nobody
                          // creates content here without agreeing either.
                          onPressed: _saving
                              ? null
                              : () => context.read<AuthBloc>().add(
                                  const LogoutRequested(),
                                ),
                          style: TextButton.styleFrom(
                            foregroundColor: _white(0.45),
                          ),
                          child: Text(context.t('terms.decline')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Column(
      children: [
        const _GlassTile(size: 72, radius: 22, child: HexMark(size: 34)),
        const SizedBox(height: 18),
        Text(
          context.t('terms.label').toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AppTheme.fontUi,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
            color: _amber,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          context.t('terms.title'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AppTheme.fontBrand,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
            height: 1.15,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          context.t('terms.body'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTheme.fontUi,
            fontSize: 13.5,
            height: 1.6,
            color: _white(0.48),
          ),
        ),
      ],
    );
  }

  Widget _rules(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _termsRules.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(_termsRules[i].icon, size: 16, color: _amber),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.t('terms.rule.${_termsRules[i].id}'),
                    style: TextStyle(
                      fontFamily: AppTheme.fontUi,
                      fontSize: 13,
                      height: 1.55,
                      color: _white(0.78),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Text(
            context.t('terms.zeroTolerance'),
            style: TextStyle(
              fontFamily: AppTheme.fontUi,
              fontSize: 12,
              height: 1.55,
              fontWeight: FontWeight.w600,
              color: _white(0.6),
            ),
          ),
        ],
      ),
    );
  }

  /// The consent row: a tick the user has to set, plus the links to the full
  /// documents. Tapping the row toggles the tick; tapping a link opens the
  /// hosted page in the browser and leaves the tick alone.
  Widget _consent(BuildContext context) {
    return InkWell(
      onTap: () => setState(() => _accepted = !_accepted),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _accepted ? _amber : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: _accepted ? _amber : _white(0.28),
                  width: 1.5,
                ),
              ),
              child: _accepted
                  ? const Icon(LucideIcons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 2,
                children: [
                  Text(
                    context.t('terms.consent'),
                    style: TextStyle(
                      fontFamily: AppTheme.fontUi,
                      fontSize: 13,
                      height: 1.5,
                      color: _white(0.72),
                    ),
                  ),
                  _TermsLink(
                    label: context.t('auth.termsOfService'),
                    onTap: () => openTermsOfService(context),
                  ),
                  Text(
                    context.t('terms.and'),
                    style: TextStyle(
                      fontFamily: AppTheme.fontUi,
                      fontSize: 13,
                      color: _white(0.72),
                    ),
                  ),
                  _TermsLink(
                    label: context.t('auth.privacyPolicy'),
                    onTap: () => openPrivacyPolicy(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TermsLink extends StatelessWidget {
  const _TermsLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: AppTheme.fontUi,
          fontSize: 13,
          height: 1.5,
          fontWeight: FontWeight.w600,
          color: _amber,
          decoration: TextDecoration.underline,
          decorationColor: _amber,
        ),
      ),
    );
  }
}

/// The gate's call-to-action — the onboarding CTA's amber gradient, but greyed
/// and inert until the tick is set, so "you have not agreed yet" is visible
/// rather than something the user discovers by tapping.
class _AcceptButton extends StatelessWidget {
  const _AcceptButton({
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: enabled ? 1 : 0.4,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_amber, _amber2],
            ),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: _amber.withValues(alpha: 0.40),
                      blurRadius: 30,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  context.t('terms.accept'),
                  style: const TextStyle(
                    fontFamily: AppTheme.fontUi,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.15,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}
