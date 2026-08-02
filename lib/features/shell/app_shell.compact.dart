part of 'app_shell.dart';

// ─────────────────────────── Compact Shell (Liquid-Glass) ─────────────────

/// Content height of the compact glass app bar (excludes the status-bar inset).
const double _kCompactBarHeight = 52;

class _CompactShell extends StatefulWidget {
  const _CompactShell({
    required this.location,
    required this.child,
    this.immersive = false,
  });

  final String location;
  final Widget child;

  /// A full-screen route that supplies its own chrome: hide the shell's glass
  /// app bar + floating nav and drop their footprints from the content gutters.
  final bool immersive;

  @override
  State<_CompactShell> createState() => _CompactShellState();
}

class _CompactShellState extends State<_CompactShell> {
  int get _selectedIndex {
    for (var i = 0; i < _bottomTabs.length - 1; i++) {
      if (_isActive(widget.location, _bottomTabs[i].route)) return i;
    }
    // Anything that isn't one of the first three tabs (dashboard · issues ·
    // board) lives behind the "More" sheet — teams, projects, gantt, timesheet,
    // reports, knowledge — so "More" (index 3) is the active tab for all of
    // them. (Earlier this returned Dashboard for primary routes like
    // /projects & /teams, wrongly lighting up Dashboard while their page was
    // open via the More sheet.)
    return 3;
  }

  void _onTap(int index) {
    final tab = _bottomTabs[index];
    if (tab.route == '/more') {
      _showMoreSheet();
    } else {
      context.go(tab.route);
    }
  }

  @override
  void dispose() {
    ShellInsets.withdraw(this);
    super.dispose();
  }

  void _showMoreSheet() {
    final user = context.read<AuthBloc>().state.user;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (sheetCtx) => _MoreSheet(
        location: widget.location,
        user: user,
        onNavigate: (route) {
          Navigator.of(sheetCtx).pop();
          context.go(route);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      // Content fills the whole screen and scrolls *behind* the translucent
      // glass app bar and the floating glass nav. We inject both bars'
      // footprints into MediaQuery.padding so screens clear them via
      // context.topGutter / context.bottomGutter while still blurring through.
      body: Stack(
        children: [
          // App-wide ambient backdrop (same as the wide shell) so every screen
          // — including the mobile dashboard — sits on the v2 canvas.
          Positioned.fill(child: AmbientBackground(dark: dark)),
          Positioned.fill(
            child: Builder(
              builder: (context) {
                final mq = MediaQuery.of(context);
                // A page may dock a toolbar into the app bar (below the title);
                // its height extends the bar and this gutter so content still
                // clears the whole bar. Listening here re-runs the footprint
                // when the page publishes/updates its docked toolbar.
                final bottomH = widget.immersive
                    ? 0.0
                    : PageChromeScope.of(
                        context,
                      ).bottomHeightFor(widget.location);
                // Glass app bar: status-bar inset + bar content height (+ any
                // docked toolbar). Immersive routes hide the bar, so only the
                // status-bar inset remains.
                final topFootprint = widget.immersive
                    ? mq.viewPadding.top
                    : _kCompactBarHeight + bottomH + mq.viewPadding.top;
                // Same footprint, minus the status-bar inset, for widgets in
                // the root overlay: they float above this shell and get no
                // MediaQuery of ours to read it from.
                ShellInsets.publishTop(this, topFootprint - mq.viewPadding.top);
                // Floating nav: GlassBottomBar barHeight(64) + verticalPadding
                // (8 top + 8 bottom) + device safe-area. Immersive routes hide
                // the nav, so only the device safe-area remains.
                final navFootprint = widget.immersive
                    ? mq.viewPadding.bottom
                    : 80 + mq.viewPadding.bottom;
                // Likewise for the root overlay — so a toast rides above the
                // nav where there is one, and drops to the bottom edge on the
                // routes that hide it.
                ShellInsets.publishBottom(
                  this,
                  navFootprint - mq.viewPadding.bottom,
                );
                return MediaQuery(
                  data: mq.copyWith(
                    padding: mq.padding.copyWith(
                      top: topFootprint,
                      bottom: navFootprint,
                    ),
                    viewPadding: mq.viewPadding.copyWith(
                      top: topFootprint,
                      bottom: navFootprint,
                    ),
                  ),
                  // Keep left/right safe-area handling; top/bottom flow through as
                  // gutters so content can scroll behind the bars.
                  child: SafeArea(
                    top: false,
                    bottom: false,
                    child: widget.child,
                  ),
                );
              },
            ),
          ),
          // Black gradient scrim rising from the bottom up to the nav so content
          // dissolves beneath the floating glass pill. (Hidden when immersive.)
          if (!widget.immersive)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(child: _BottomNavScrim()),
            ),
          // Floating liquid-glass nav (package GlassBottomBar). Kept in the
          // Stack (not Scaffold.bottomNavigationBar) so it floats over the
          // content it refracts; SafeArea lifts it above the home indicator.
          if (!widget.immersive)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                bottom: false,
                // iOS-26 layout: the tab pill and a detached global-search button
                // are two separate floating glass elements with a gap between
                // them. The padding that used to live inside GlassBottomBar is
                // hoisted to this Row so both elements share the same inset and
                // the footprint injected above (navFootprint) stays unchanged.
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GlassTabBar.bottom(
                          horizontalPadding: 0,
                          verticalPadding: 0,
                          selectedIndex: _selectedIndex,
                          onTabSelected: _onTap,
                          // Black-tinted glass in dark mode (so it doesn't turn
                          // milky), clean white frost in light — see _kNavGlass*.
                          settings: dark ? kNavGlassDark : kNavGlassLight,
                          // Honey-amber indicator (translucent so the glass shows
                          // through).
                          indicatorColor: AppColors.accent.withValues(
                            alpha: dark ? 0.30 : 0.22,
                          ),
                          selectedIconColor: dark
                              ? AppColors.accent
                              : AppColors.accentStrong,
                          unselectedIconColor: dark
                              ? AppColors.inkDark
                              : AppColors.ink,
                          tabs: [
                            for (final d in _bottomTabs)
                              GlassTab(
                                icon: Icon(d.icon),
                                label: context.t(d.labelKey),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _GlassNavSearchButton(dark: dark),
                    ],
                  ),
                ),
              ),
            ),
          // Transparent glass app bar with a top-down scrim — overlays content.
          // (Hidden when immersive; the page draws its own top bar.)
          if (!widget.immersive)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _GlassTopBar(location: widget.location, dark: dark),
            ),
        ],
      ),
    );
  }
}

/// Transparent liquid-glass app bar for the compact (mobile) shell. Blurs the
/// content scrolling beneath it and lays a subtle top-down black scrim so the
/// status bar and title stay legible. Centered page title, brand mark on the
/// left, the always-visible action icons (search · notifications · settings)
/// grouped in a glass capsule on the right.
class _GlassTopBar extends StatelessWidget {
  const _GlassTopBar({required this.location, required this.dark});

  final String location;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.viewPaddingOf(context).top;
    final chrome = PageChromeScope.of(context);

    // Optional toolbar the page docks below the title row (shares this bar's
    // single blur, so there is no separate blurred band beneath it).
    final bottom = chrome.bottomFor(location);
    final bottomHeight = chrome.bottomHeightFor(location);

    // Sub-page → back button + the page's own title; primary nav page → brand
    // mark + the nav-derived title.
    final subKey = _subPageTitleKey(location);
    final String titleText;
    VoidCallback? onBack;
    if (subKey != null) {
      titleText = chrome.titleFor(location) ?? context.t(subKey);
      final override = chrome.onBackFor(location);
      onBack = () => _handleBack(context, location, override);
    } else {
      final all = [..._primary, ..._secondary];
      final current = all.firstWhere(
        (d) => _isActive(location, d.route),
        orElse: () =>
            const _Destination('/', 'nav.dashboard', LucideIcons.house),
      );
      titleText = context.t(current.labelKey);
    }
    // Black scrim, strongest under the status bar, fading to nothing at the
    // bar's lower edge. Subtle in light (keeps dark status-bar icons legible),
    // stronger in dark.
    //
    // The bar reads content through a *progressive* backdrop blur — heavy at the
    // status-bar edge, easing to perfectly sharp at the bottom (the iOS-26 look,
    // cf. Instagram's profile header). The pill/buttons on top must NOT add
    // their own BackdropFilter: a filter sampling an already-blurred backdrop is
    // what produced the pixelated / "layered" blocks. Instead they are
    // translucent frosted surfaces that simply let this one blur show through.
    final scrimTop = dark ? 0.5 : 0.16;
    // The docked toolbar (if any) extends the bar below the title row; the
    // single progressive blur and this whole height cover both, so the toolbar
    // reads as part of the same glass — no separate band.
    final chromeZone = topInset + _kCompactBarHeight;
    final height = chromeZone + bottomHeight;

    return SizedBox(
      height: height,
      child: Stack(
        children: [
          // Smooth progressive blur: strongest at the top, fading to sharp at the
          // bottom edge so the bar dissolves into the content beneath it.
          Positioned.fill(
            child: ProgressiveBlur(
              maxSigma: dark ? 14 : 12,
              direction: ProgressiveBlurDirection.topToBottom,
            ),
          ),
          // Darkening scrim over the title zone only (fades out before the
          // toolbar so the docked controls sit on clean glass, not a dark tint).
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: chromeZone,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: scrimTop),
                    Colors.black.withValues(alpha: scrimTop * 0.4),
                    Colors.black.withValues(alpha: 0),
                  ],
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
            ),
          ),
          // Title row + optional docked toolbar, stacked. The GlassAppBar is a
          // transparent layout container (leading · centered title · actions)
          // that handles its own status-bar SafeArea; its children are
          // translucent frosted surfaces that let the one progressive blur show
          // through (no nested BackdropFilter). The docked toolbar sits directly
          // below it, sharing the same blur.
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassAppBar(
                backgroundColor: Colors.transparent,
                centerTitle: true,
                toolbarHeight: _kCompactBarHeight,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                leading: onBack != null
                    ? Tooltip(
                        message: MaterialLocalizations.of(
                          context,
                        ).backButtonTooltip,
                        child: !isNativeApp
                            ? _FrostedCircleButton(
                                icon: LucideIcons.arrowLeft,
                                onTap: onBack,
                              )
                            : GlassButton(
                                icon: const Icon(LucideIcons.arrowLeft),
                                onTap: onBack,
                                width: 42,
                                height: 42,
                                iconSize: 18,
                                useOwnLayer: true,
                                settings: dark ? kNavGlassDark : kNavGlassLight,
                                iconColor: dark
                                    ? AppColors.inkDark
                                    : AppColors.ink,
                                glowColor: AppColors.accent,

                                // Keep the tactile press-scale but damp the liquid drag-follow so the
                                // isolated button doesn't over-stretch on tap.
                                stretch: 0.15,
                              ),
                      )
                    : Tooltip(
                        message: context.t('nav.dashboard'),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => context.go('/dashboard'),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: HexMark(size: 24, color: AppColors.accent),
                          ),
                        ),
                      ),
                title: Text(
                  titleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTheme.fontBrand,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: AppColors.ink,
                  ),
                ),
                actions: [_GlassTopActions(location: location, dark: dark)],
              ),
              if (bottom != null)
                SizedBox(
                  height: bottomHeight,
                  width: double.infinity,
                  child: bottom,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Persistent top-bar actions — notifications and settings, each its own
/// separate round iOS-26 liquid-glass button (no more grouped capsule; global
/// search moved to the floating bottom nav). Each button is a [_FrostedSurface]
/// circle that relies on the bar's single [ProgressiveBlur] showing through its
/// translucent fill (no nested [BackdropFilter], which would re-sample the
/// already-blurred backdrop and pixelate).
class _GlassTopActions extends StatelessWidget {
  const _GlassTopActions({required this.location, required this.dark});

  final String location;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    // Trailing actions the visible sub-page published into the bar (Save,
    // Invite, …), rendered as icon-only frosted circles ahead of the persistent
    // notification + settings controls.
    final pageActions = PageChromeScope.of(context).actionsFor(location);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in pageActions) ...[
          _PageActionButton(action: action, dark: dark),
          const SizedBox(width: 8),
        ],
        _NotificationBell(
          active: location.startsWith('/notifications'),
          frosted: true,
          dark: dark,
        ),
        const SizedBox(width: 8),
        !isNativeApp
            ? _FrostedCircleButton(
                icon: LucideIcons.settings2,
                tooltip: context.t('nav.settings'),
                active: location.startsWith('/settings'),
                onTap: () => context.go('/settings'),
              )
            : Tooltip(
                message: context.t('nav.settings'),
                child: GlassButton(
                  icon: const Icon(LucideIcons.settings2),
                  onTap: () => context.go('/settings'),
                  width: 42,
                  height: 42,
                  iconSize: 18,
                  useOwnLayer: true,
                  settings: dark ? kNavGlassDark : kNavGlassLight,
                  iconColor: dark ? AppColors.inkDark : AppColors.ink,
                  glowColor: AppColors.accent,

                  // Keep the tactile press-scale but damp the liquid drag-follow so the
                  // isolated button doesn't over-stretch on tap.
                  stretch: 0.15,
                ),
              ),
      ],
    );
  }
}

/// A translucent frosted surface — the visual "glass" used by the top-bar
/// pill/buttons. It carries NO blur of its own; it relies on the bar's single
/// progressive [BackdropFilter] showing through the semi-transparent fill, then
/// adds the hairline edge + top specular highlight that read as a glass rim.
/// Keeping the blur in ONE place is what keeps the surface crisp (no nested
/// backdrop sampling → no pixelation).
class _FrostedSurface extends StatelessWidget {
  const _FrostedSurface({
    required this.child,
    required this.borderRadius,
    required this.dark,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        // Light frost lift in dark, a brighter wash in light — translucent so
        // the progressive blur behind stays visible through the surface.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0x33FFFFFF), Color(0x1FFFFFFF)]
              : const [Color(0x6BFFFFFF), Color(0x4DFFFFFF)],
        ),
        border: Border.all(
          color: dark ? const Color(0x40FFFFFF) : const Color(0x66FFFFFF),
          width: 0.6,
        ),
      ),
      child: child,
    );
  }
}

/// 40×40 frosted circular button — the iOS-26 standalone glass control used for
/// the top-bar back affordance and each trailing action (notifications ·
/// settings). Same no-own-blur frosted treatment as [_FrostedSurface]. When
/// [active] it fills with a translucent honey-amber tint and the glyph adopts
/// the accent colour; [overlay] paints an extra badge (e.g. the unread dot)
/// above the icon.
class _FrostedCircleButton extends StatelessWidget {
  const _FrostedCircleButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.active = false,
    this.overlay,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool active;

  /// Optional badge (e.g. the unread dot) painted above the icon.
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final button = _FrostedSurface(
      borderRadius: BorderRadius.circular(20),
      dark: dark,
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (active)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accent.withValues(
                          alpha: dark ? 0.30 : 0.20,
                        ),
                      ),
                    ),
                  ),
                Icon(
                  icon,
                  size: 18,
                  color: active
                      ? (dark ? AppColors.accent : AppColors.accentStrong)
                      : AppColors.ink,
                ),
                ?overlay,
              ],
            ),
          ),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: button) : button;
  }
}

/// A sub-page's [PageAction] rendered in the compact glass bar. On native it is
/// a real iOS-26 [GlassButton] (its own glass layer), matching the bell/settings
/// controls; on web it falls back to the frosted circle (a nested backdrop blur
/// pixelates on Skia). [PageAction.primary] gets an amber glyph; [PageAction.busy]
/// shows a small spinner and ignores taps.
class _PageActionButton extends StatelessWidget {
  const _PageActionButton({required this.action, required this.dark});

  final PageAction action;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    if (action.busy) {
      return _FrostedSurface(
        borderRadius: BorderRadius.circular(20),
        dark: dark,
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Center(child: HiveLoader(size: 18, strokeWidth: 2)),
        ),
      );
    }
    if (isNativeApp) {
      return Tooltip(
        message: action.label,
        child: GlassButton(
          icon: Icon(action.icon),
          onTap: action.onTap ?? () {},
          width: 42,
          height: 42,
          iconSize: 18,
          useOwnLayer: true,
          settings: dark ? kNavGlassDark : kNavGlassLight,
          iconColor: action.primary
              ? AppColors.accentStrong
              : (dark ? AppColors.inkDark : AppColors.ink),
          glowColor: AppColors.accent,
          stretch: 0.15,
        ),
      );
    }
    return _FrostedCircleButton(
      icon: action.icon,
      tooltip: action.label,
      active: action.primary,
      onTap: action.onTap ?? () {},
    );
  }
}

/// Detached liquid-glass button carrying the global search, floating to the
/// right of the tab pill (iOS-26 separated-controls layout). It is its own
/// glass layer ([GlassButton.useOwnLayer]) so it refracts the content behind it
/// independently of the tab pill, matched to the same [kNavGlassDark] /
/// [kNavGlassLight] preset so the two elements read as one material. Sized to
/// the bar's 64px height so both align.
class _GlassNavSearchButton extends StatelessWidget {
  const _GlassNavSearchButton({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.t('appbar.search'),
      child: GlassButton(
        icon: const Icon(LucideIcons.search),
        onTap: () => openGlobalSearch(context),
        width: 64,
        height: 64,
        iconSize: 24,
        useOwnLayer: true,
        settings: dark ? kNavGlassDark : kNavGlassLight,
        iconColor: dark ? AppColors.inkDark : AppColors.ink,
        // Keep the tactile press-scale but damp the liquid drag-follow so the
        // isolated button doesn't over-stretch on tap.
        stretch: 0.15,
      ),
    );
  }
}

/// Black gradient that fades up from the bottom edge to behind the floating
/// nav, so scrolling content dissolves beneath it (the liquid-glass scrim).
class _BottomNavScrim extends StatelessWidget {
  const _BottomNavScrim();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pad = MediaQuery.viewPaddingOf(context).bottom;
    return SizedBox(
      height: 96 + pad,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0),
              Colors.black.withValues(alpha: dark ? 0.42 : 0.12),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreSheet extends StatelessWidget {
  const _MoreSheet({
    required this.location,
    required this.onNavigate,
    this.user,
  });

  final String location;
  final void Function(String route) onNavigate;
  final AuthUser? user;

  static const _items = [
    _Destination('/projects', 'nav.projects', LucideIcons.folder),
    _Destination('/teams', 'nav.teams', LucideIcons.usersRound),
    _Destination('/gantt', 'nav.gantt', LucideIcons.chartColumnStacked),
    _Destination('/timesheet', 'nav.timesheet', LucideIcons.table),
    _Destination('/reports', 'nav.reports', LucideIcons.chartLine),
    _Destination('/knowledge', 'nav.knowledge', LucideIcons.bookOpen),
    // Notifications intentionally omitted — they live in the always-visible
    // top bar bell, so they need no entry in the overflow sheet.
  ];

  static const double _radius = 28;

  @override
  Widget build(BuildContext context) {
    final tokens = SearchTokens.of(Theme.of(context).brightness);
    final dark = Theme.of(context).brightness == Brightness.dark;

    final subtitle = user?.title?.isNotEmpty == true
        ? user!.title!
        : user?.roles.isNotEmpty == true
        ? user!.roles.first.toLowerCase()
        : user?.email ?? '';

    final panel = GlassPanelShadow(
      radius: BorderRadius.circular(_radius),
      shadows: tokens.panelShadow,
      child: GlassContainer(
        useOwnLayer: true,
        quality: GlassQuality.premium,
        clipBehavior: Clip.antiAlias,
        shape: const LiquidRoundedSuperellipse(borderRadius: _radius),
        settings: liquidGlassPanelSettings(
          glassFill: tokens.glassFill,
          dark: dark,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // User header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                child: Row(
                  children: [
                    AppAvatar(
                      name: user?.displayName ?? '?',
                      imageUrl: user?.avatarUrl,
                      radius: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            user?.displayName ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: tokens.ink,
                            ),
                          ),
                          if (subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: tokens.inkSoft,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        LucideIcons.x,
                        size: 20,
                        color: tokens.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                color: tokens.hairline,
              ),
              const SizedBox(height: 12),
              // Compact 3-column grid — fixed row height so tiles never bloat
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.1,
                ),
                itemCount: _items.length,
                itemBuilder: (context, i) => _MoreTile(
                  tokens: tokens,
                  destination: _items[i],
                  active: location.startsWith(_items[i].route),
                  onTap: () => onNavigate(_items[i].route),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: panel,
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.tokens,
    required this.destination,
    required this.active,
    required this.onTap,
  });

  final SearchTokens tokens;
  final _Destination destination;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconColor = active ? AppColors.accentStrong : tokens.inkSoft;
    final badgeBg = active ? AppColors.accentSoft : tokens.field;
    return Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: active ? AppColors.accentSoft.withValues(alpha: 0.35) : null,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(
              color: active ? AppColors.accentLine : tokens.hairline,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon badge — small rounded square, matches reference design
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(destination.icon, size: 20, color: iconColor),
              ),
              const SizedBox(height: 7),
              Text(
                context.t(destination.labelKey),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: iconColor,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
