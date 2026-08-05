import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/blocs/auth_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/responsive/responsive.dart';
import '../../core/storage/app_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hex_mark.dart';
import '../legal/legal_links.dart';

part 'onboarding_screen.chrome.dart';
part 'onboarding_screen.cards.dart';
part 'onboarding_screen.terms.dart';

/// One-time feature tour shown after the first successful server connection.
///
/// Implements the "hinata Onboarding Concept" design: a branded, dark-navy
/// walk-through with ambient orbs, liquid-glass feature cards, animated page
/// dots and a Continue → Get Started call-to-action. Always renders dark —
/// it is a brand splash, independent of the app's [ThemeMode].
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.storage,
    required this.onDone,
  });

  final AppStorage storage;
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

// ─── design palette (constant across themes — this screen is always dark) ───
const _amber = AppColors.accent; // #D9A032
const _amber2 = Color(0xFFB9831F);
const _bgTop = Color(0xFF1D1B38);
const _bgMid = Color(0xFF11102A);
const _bgBot = Color(0xFF19152E);
const _navFade = Color(0xFF0B0A1A);

Color _white(double o) => Colors.white.withValues(alpha: o);

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  static const _total = 4;

  final _controller = PageController();
  late final AnimationController _ambient;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Single long-running clock drives the orb drift + logo glow pulse.
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    _ambient.dispose();
    super.dispose();
  }

  bool get _isLast => _index == _total - 1;

  void _goTo(int i) {
    _controller.animateToPage(
      i.clamp(0, _total - 1),
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
    );
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _goTo(_index + 1);
    }
  }

  Future<void> _finish() async {
    await widget.storage.setOnboardingDone();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgMid,
      body: Stack(
        children: [
          // ── ambient background ──
          const Positioned.fill(child: _BackgroundGradient()),
          Positioned.fill(child: _Orbs(animation: _ambient)),

          // ── foreground ──
          SafeArea(
            child: Column(
              children: [
                _TopBar(visible: !_isLast, onSkip: () => _goTo(_total - 1)),
                Expanded(
                  child: PageView(
                    controller: _controller,
                    onPageChanged: (i) => setState(() => _index = i),
                    children: [
                      _WelcomeSlide(glow: _ambient),
                      const _FeatureSlide(
                        labelKey: 'onboarding.label',
                        titleKey: 'onboarding.projects.title',
                        bodyKey: 'onboarding.projects.body',
                        card: _ProjectsCard(),
                      ),
                      const _FeatureSlide(
                        labelKey: 'onboarding.label',
                        titleKey: 'onboarding.sprints.title',
                        bodyKey: 'onboarding.sprints.body',
                        card: _SprintCard(),
                      ),
                      const _FeatureSlide(
                        labelKey: 'onboarding.label',
                        titleKey: 'onboarding.teams.title',
                        bodyKey: 'onboarding.teams.body',
                        card: _TeamsCard(),
                      ),
                    ],
                  ),
                ),
                _BottomNav(
                  index: _index,
                  total: _total,
                  isLast: _isLast,
                  onCta: _next,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
