part of 'app_shell.dart';

// ─────────────────────────── Wide Shell (Navy Rail) ───────────────────────

/// Floating top bar geometry: the gap above it, its content height, and the gap
/// between it and the page below. [ShellInsets] publishes the first two so
/// root-overlay widgets can clear the bar.
const double _kTopBarGapAbove = 12;
const double _kTopBarHeight = 60;
const double _kTopBarGapBelow = 10;

class _WideShell extends StatefulWidget {
  const _WideShell({required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  State<_WideShell> createState() => _WideShellState();
}

class _WideShellState extends State<_WideShell> {
  // Desktop-only manual collapse. Medium widths are always collapsed (no room
  // to expand), so the toggle is offered only on the full layout.
  bool _collapsed = false;

  @override
  void dispose() {
    ShellInsets.withdraw(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Widgets in the root overlay float above this shell and cannot measure it
    // — tell them how far the floating top bar reaches so they can clear it.
    ShellInsets.publishTop(this, _kTopBarGapAbove + _kTopBarHeight);
    final isMedium = context.layoutSize == LayoutSize.medium;
    final collapsed = isMedium || _collapsed;
    final railWidth = collapsed ? 76.0 : 244.0;
    final subKey = _subPageTitleKey(widget.location);
    final dark = Theme.of(context).brightness == Brightness.dark;

    // The ambient backdrop is painted app-wide; the floating glass topbar and
    // nav rail sit over it, with the content area between/below them. The outer
    // SafeArea consumes the status-bar inset once (so context.topGutter stays 0
    // for pages, as before).
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Stack(
        children: [
          Positioned.fill(child: AmbientBackground(dark: dark)),
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      _kTopBarGapAbove,
                      16,
                      _kTopBarGapBelow,
                    ),
                    child: _GlassFloatingTopBar(location: widget.location),
                  ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _NavRail(
                          location: widget.location,
                          collapsed: collapsed,
                          width: railWidth,
                          canToggle: !isMedium,
                          onToggle: () =>
                              setState(() => _collapsed = !_collapsed),
                        ),
                        Expanded(
                          child: _ScrollWheelPassthrough(
                            location: widget.location,
                            child: Column(
                              children: [
                                // Sub-pages keep a slim back + title bar (the floating
                                // topbar carries no breadcrumb); primary pages render
                                // their own PageHead instead. Immersive routes (the
                                // full-page issue view) draw their own top bar, so the
                                // shell must not stack a second back+title row above it.
                                if (subKey != null &&
                                    !_isImmersive(widget.location))
                                  _BodyWidth(
                                    location: widget.location,
                                    child: _SubPageBar(
                                      location: widget.location,
                                      titleKey: subKey,
                                    ),
                                  ),
                                Expanded(
                                  child: _BodyWidth(
                                    location: widget.location,
                                    child: widget.child,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// How wide the page at [location] wants its body — the reading width unless it
/// published otherwise. Both the sub-page bar and the page itself go through
/// this, so a full-width page never ends up with its back button off its own
/// left edge. Listening here rather than in the shell keeps a chrome update
/// from rebuilding the whole shell: the child instance is unchanged, so the
/// page subtree below is reused as-is.
class _BodyWidth extends StatelessWidget {
  const _BodyWidth({required this.location, required this.child});

  final String location;
  final Widget child;

  static double of(BuildContext context, String location) =>
      PageChromeScope.of(context).fullWidthFor(location)
      ? double.infinity
      : Breakpoints.readingWidth;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: of(context, location)),
    child: child,
  );
}

/// The centered body leaves empty margins on wide screens that no [Scrollable]
/// covers, so a mouse wheel there does nothing. This wraps the full-width area
/// and, when a scroll happens outside the centered content, re-dispatches it as
/// if it occurred at the nearest point inside the content so the page
/// underneath still scrolls. A full-width page has no such margins, and the
/// infinite half-width below turns the whole thing into a pass-through.
class _ScrollWheelPassthrough extends StatelessWidget {
  const _ScrollWheelPassthrough({required this.location, required this.child});

  final String location;
  final Widget child;

  /// [bodyWidth] is read during build — an inherited-widget lookup while
  /// dispatching a pointer event would register a dependency mid-event.
  void _onPointerSignal(
    BuildContext context,
    PointerSignalEvent event,
    double bodyWidth,
  ) {
    if (event is! PointerScrollEvent) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return;

    final local = box.globalToLocal(event.position);
    final centerX = box.size.width / 2;
    final halfContent = bodyWidth / 2;
    final offsetFromCenter = local.dx - centerX;
    if (offsetFromCenter.abs() <= halfContent) {
      return; // Already inside the content column; let normal hit-testing handle it.
    }

    final clampedDx =
        centerX + offsetFromCenter.clamp(-halfContent, halfContent);
    final targetGlobal = box.localToGlobal(Offset(clampedDx, local.dy));
    final viewId = View.of(context).viewId;
    final result = HitTestResult();
    RendererBinding.instance.hitTestInView(result, targetGlobal, viewId);
    RendererBinding.instance.dispatchEvent(
      PointerScrollEvent(
        timeStamp: event.timeStamp,
        kind: event.kind,
        device: event.device,
        position: targetGlobal,
        scrollDelta: event.scrollDelta,
        viewId: viewId,
        embedderId: event.embedderId,
      ),
      result,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bodyWidth = _BodyWidth.of(context, location);
    return Listener(
      // Listener defaults to HitTestBehavior.deferToChild, so in the empty
      // margins beside the centered content (where no child claims the hit)
      // it would never be hit-tested and onPointerSignal would never fire.
      // opaque makes it always participate in hit-testing over its full area.
      behavior: HitTestBehavior.opaque,
      onPointerSignal: (event) => _onPointerSignal(context, event, bodyWidth),
      child: child,
    );
  }
}

/// Opens the create-issue form from global chrome (the nav-rail CTA). On a
/// successful create it broadcasts [IssueEvents.notifyChanged] so whatever
/// issue-bearing screen is currently visible re-fetches — the rail itself has
/// no handle to that page's cubit, so the change travels through the event bus.
/// [showIssueForm] already opens the new issue's detail sheet on success.
Future<void> _createIssue(BuildContext context) async {
  final created = await showIssueForm(context);
  if (created != null) IssueEvents.instance.notifyChanged();
}

class _NavRail extends StatelessWidget {
  const _NavRail({
    required this.location,
    required this.collapsed,
    required this.width,
    this.canToggle = false,
    this.onToggle,
  });

  final String location;
  final bool collapsed;
  final double width;

  /// Whether to show the manual collapse/expand control (desktop only).
  final bool canToggle;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
      width: width,
      margin: const EdgeInsets.fromLTRB(16, 0, 0, 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2D2B55).withValues(alpha: 0.34),
            blurRadius: 30,
            spreadRadius: -12,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Frosted navy liquid glass: blur the ambient behind the rail and lay
          // a slightly-translucent navy gradient over it so it reads as glass.
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.rail, AppColors.rail2],
                  ),
                ),
              ),
            ),
          ),
          // Faint honeycomb texture pooling at the base of the rail.
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 240,
            child: HoneycombBackground(),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Column(
                // Centre every item on the rail's vertical axis when collapsed;
                // left-align them in the expanded view.
                crossAxisAlignment: collapsed
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: [
                  // Scrollable nav section so short viewports never overflow the
                  // rail; the footer (toggle + account) below stays pinned.
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: collapsed
                            ? CrossAxisAlignment.center
                            : CrossAxisAlignment.start,
                        children: [
                          // Brand now lives in the floating topbar; the rail opens
                          // straight into its actions.
                          const SizedBox(height: 16),

                          // New issue CTA
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: collapsed ? 12 : 16,
                              vertical: 4,
                            ),
                            child: collapsed
                                ? _RailIconButton(
                                    icon: LucideIcons.plus,
                                    active: false,
                                    amber: true,
                                    tooltip: context.t('issues.new'),
                                    onTap: () => _createIssue(context),
                                  )
                                : DecoratedBox(
                                    // Soft honey glow beneath the CTA (matches the web
                                    // prototype's box-shadow: 0 6px 18px -8px amber/0.7).
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                        AppTheme.radiusControl,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.accent.withValues(
                                            alpha: 0.45,
                                          ),
                                          blurRadius: 18,
                                          spreadRadius: -6,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: () => _createIssue(context),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: AppColors.accent,
                                          foregroundColor: const Color(
                                            0xFF2A2410,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              AppTheme.radiusControl,
                                            ),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 12,
                                          ),
                                          textStyle: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                        icon: const Icon(
                                          LucideIcons.plus,
                                          size: 18,
                                        ),
                                        label: Text(context.t('issues.new')),
                                      ),
                                    ),
                                  ),
                          ),

                          const SizedBox(height: 16),

                          // Primary group
                          if (!collapsed) const _RailGroupLabel('WORK'),
                          for (final dest in _primary)
                            _RailItem(
                              destination: dest,
                              selected: _isActive(location, dest.route),
                              collapsed: collapsed,
                            ),

                          const SizedBox(height: 8),
                          if (!collapsed) const _RailGroupLabel('PLAN'),
                          for (final dest in _secondary)
                            _RailItem(
                              destination: dest,
                              selected: _isActive(location, dest.route),
                              collapsed: collapsed,
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Collapse / expand toggle — desktop only, sits above the user.
                  if (canToggle && onToggle != null)
                    _CollapseToggle(collapsed: collapsed, onToggle: onToggle!),

                  // Settings entry — a standard rail item so it matches the nav
                  // above (icon + label expanded, icon-only collapsed).
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: _RailItem(
                      destination: const _Destination(
                        '/settings',
                        'nav.settings',
                        LucideIcons.settings,
                      ),
                      selected: _isActive(location, '/settings'),
                      collapsed: collapsed,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Desktop rail collapse/expand control. Full-width labelled row when expanded,
/// a centered icon button when collapsed. Sits just above the user button.
class _CollapseToggle extends StatelessWidget {
  const _CollapseToggle({required this.collapsed, required this.onToggle});

  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final icon = collapsed
        ? LucideIcons.panelLeftOpen
        : LucideIcons.panelLeftClose;
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: _RailIconButton(
          icon: icon,
          active: false,
          tooltip: context.t('nav.expandSidebar'),
          onTap: onToggle,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          hoverColor: Colors.white.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.railFaint),
                const SizedBox(width: 10),
                Text(
                  context.t('nav.collapse'),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.railFaint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RailGroupLabel extends StatelessWidget {
  const _RailGroupLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: AppTheme.fontMono,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: AppColors.railFaint,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.collapsed,
  });

  final _Destination destination;
  final bool selected;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: collapsed ? 8 : 10,
        vertical: 2,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Clean amber edge indicator (3×18, rounded) — sits just outside
          // the tile's left edge like the prototype's `::before` bar.
          if (selected && !collapsed)
            Positioned(
              left: -10,
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () => context.go(destination.route),
              borderRadius: BorderRadius.circular(8),
              hoverColor: Colors.white.withValues(alpha: 0.06),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: collapsed ? null : double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: collapsed ? 10 : 12,
                  vertical: 9,
                ),
                decoration: selected
                    ? BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      )
                    : null,
                child: collapsed
                    ? Tooltip(
                        message: context.t(destination.labelKey),
                        preferBelow: false,
                        child: Icon(
                          destination.icon,
                          size: 20,
                          color: selected
                              ? AppColors.accent
                              : AppColors.railFaint,
                        ),
                      )
                    : Row(
                        children: [
                          Icon(
                            destination.icon,
                            size: 18,
                            color: selected
                                ? AppColors.accent
                                : AppColors.railFaint,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            context.t(destination.labelKey),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: selected
                                  ? AppColors.railInk
                                  : AppColors.railFaint,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailIconButton extends StatelessWidget {
  const _RailIconButton({
    required this.icon,
    required this.active,
    required this.onTap,
    this.amber = false,
    this.tooltip,
  });

  final IconData icon;
  final bool active;
  final bool amber;
  final String? tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final child = Material(
      color: amber ? AppColors.accent : Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            icon,
            size: 20,
            color: amber ? const Color(0xFF2A2410) : AppColors.railFaint,
          ),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: child) : child;
  }
}

// ─────────────────────── Desktop / tablet floating topbar ──────────────────
// A full-width floating glass bar: brand mark + wordmark (left), a centred ⌘K
// search pill, and the notification bell + avatar (→ settings) on the right.
// The compact shell keeps its own overlay glass app bar (_GlassTopBar).

class _GlassFloatingTopBar extends StatelessWidget {
  const _GlassFloatingTopBar({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final user = context.select((AuthBloc bloc) => bloc.state.user);
    return Container(
      height: _kTopBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.hairline),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2D2B55).withValues(alpha: dark ? .34 : .10),
            blurRadius: 26,
            spreadRadius: -10,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Tooltip(
            message: context.t('nav.dashboard'),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.go('/dashboard'),
                // Only the signet swaps; the wordmark stays. The shell is the
                // product you are working in, and the mark beside it says whose
                // instance it is — dropping "hinata" here would leave the app
                // itself unnamed on the one surface that is always on screen.
                // Bounded hard: this Row sits beside an Expanded search field,
                // so an unclamped logo would squeeze it on a narrow window.
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OrgLogo(
                      height: 28,
                      maxWidth: 108,
                      fallback: HexMark(
                        size: 26,
                        color: dark ? AppColors.accent : AppColors.navy,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Text(
                      'hinata',
                      style: TextStyle(
                        fontFamily: AppTheme.fontBrand,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Expanded(
            child: Center(
              child: _TopSearchField(compact: false, maxWidth: 520),
            ),
          ),
          const SizedBox(width: 6),
          _NotificationBell(active: location.startsWith('/notifications')),
          const SizedBox(width: 10),
          _AvatarMenuButton(
            name: user?.displayName ?? '?',
            imageUrl: user?.avatarUrl,
          ),
        ],
      ),
    );
  }
}

/// The top-right avatar on the desktop / tablet topbar. Tapping it opens a
/// Liquid-Glass options menu anchored beneath the avatar with quick account
/// actions — edit the profile inline (no detour through Settings) or sign out.
class _AvatarMenuButton extends StatefulWidget {
  const _AvatarMenuButton({required this.name, this.imageUrl});

  final String name;
  final String? imageUrl;

  @override
  State<_AvatarMenuButton> createState() => _AvatarMenuButtonState();
}

class _AvatarMenuButtonState extends State<_AvatarMenuButton> {
  final GlobalKey _avatarKey = GlobalKey();

  Rect? _anchorRect() {
    final box = _avatarKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _openMenu() async {
    final choice = await showGlassOptions<String>(
      context,
      title: context.t('account.title'),
      anchorRect: _anchorRect(),
      options: [
        (
          value: 'profile',
          child: _menuRow(LucideIcons.pencil, context.t('account.editProfile')),
        ),
        (
          value: 'logout',
          child: _menuRow(
            LucideIcons.logOut,
            context.t('account.signOut'),
            danger: true,
          ),
        ),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'profile':
        await _editProfile();
      case 'logout':
        context.read<AuthBloc>().add(const LogoutRequested());
    }
  }

  /// Opens the profile-edit modal directly (fetches the fresh [Me] first) and
  /// keeps the shell avatar / name in sync on save — mirrors the account
  /// screen's edit flow so both entry points behave identically.
  Future<void> _editProfile() async {
    final repo = context.read<AccountRepository>();
    final authBloc = context.read<AuthBloc>();
    final savedToast = context.t('account.profileUpdated');
    final Me me;
    try {
      me = await repo.meAccount();
    } on ApiFailure catch (failure) {
      if (mounted) {
        showGlassToast(
          context,
          context.t(failure.message),
          kind: GlassToastKind.error,
        );
      }
      return;
    }
    if (!mounted) return;
    final saved = await showEditProfile(context, repo, me);
    if (saved != null && mounted) {
      authBloc.add(const AuthChecked());
      showGlassToast(context, savedToast);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.t('account.title'),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _openMenu,
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: AppAvatar(
              key: _avatarKey,
              name: widget.name,
              imageUrl: widget.imageUrl,
              radius: 18,
            ),
          ),
        ),
      ),
    );
  }
}

/// A leading-icon + label row for the avatar options menu; [danger] tints the
/// destructive sign-out entry.
Widget _menuRow(IconData icon, String label, {bool danger = false}) {
  return Builder(
    builder: (context) {
      final color = danger ? AppColors.danger : AppColors.ink;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 13.5, color: color)),
        ],
      );
    },
  );
}

/// Slim contextual bar shown on sub-pages under the floating topbar: a back
/// button + the page's title (published via [PageChrome]).
class _SubPageBar extends StatelessWidget {
  const _SubPageBar({required this.location, required this.titleKey});

  final String location;
  final String titleKey;

  @override
  Widget build(BuildContext context) {
    final chrome = PageChromeScope.of(context);
    final title = chrome.titleFor(location) ?? context.t(titleKey);
    final override = chrome.onBackFor(location);
    final actions = chrome.actionsFor(location);
    // A page may dock a toolbar (search + filters) below the title row; on wide
    // this flows as a normal row above the content (no overlay blur to share).
    final bottom = chrome.bottomFor(location);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 24, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: () => _handleBack(context, location, override),
                visualDensity: VisualDensity.compact,
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: Icon(
                  LucideIcons.arrowLeft,
                  size: 20,
                  color: AppColors.inkSoft,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              for (final action in actions) ...[
                const SizedBox(width: 8),
                _WidePageAction(action: action),
              ],
            ],
          ),
        ),
        if (bottom != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 24, 0),
            child: bottom,
          ),
      ],
    );
  }
}

/// A sub-page's [PageAction] rendered in the wide sub-page bar: an icon+label
/// pill — amber-filled when [PageAction.primary], otherwise a hairline-outlined
/// surface pill. While [PageAction.busy] it shows a spinner and ignores taps.
class _WidePageAction extends StatelessWidget {
  const _WidePageAction({required this.action});

  final PageAction action;

  @override
  Widget build(BuildContext context) {
    final primary = action.primary;
    final dark = Theme.of(context).brightness == Brightness.dark;

    // On native, a real iOS-26 glass pill (its own layer); on web, a frosted
    // surface pill (nested backdrop blur pixelates on Skia). Primary actions get
    // an amber glyph so the CTA still reads clearly on the translucent bar.
    final fg = primary
        ? AppColors.accentStrong
        : (dark ? AppColors.inkDark : AppColors.ink);
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (action.busy)
            SizedBox(
              width: 15,
              height: 15,
              child: HiveLoader(size: 15, strokeWidth: 2, color: fg),
            )
          else
            Icon(action.icon, size: 15, color: fg),
          const SizedBox(width: 7),
          Text(
            action.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );

    if (isNativeApp) {
      return GlassButton.custom(
        onTap: action.busy ? () {} : (action.onTap ?? () {}),
        height: 40,
        shape: const LiquidRoundedSuperellipse(borderRadius: 20),
        useOwnLayer: true,
        settings: dark ? kNavGlassDark : kNavGlassLight,
        glowColor: AppColors.accent,
        stretch: 0.15,
        child: content,
      );
    }
    return FrostedSurface(
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      dark: dark,
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: action.busy ? null : action.onTap,
          child: content,
        ),
      ),
    );
  }
}

/// Pill global-search field. Collapses to a single icon button on compact.
class _TopSearchField extends StatelessWidget {
  const _TopSearchField({required this.compact, this.maxWidth = 300});

  final bool compact;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _TopIconButton(
        icon: LucideIcons.search,
        tooltip: context.t('appbar.search'),
        onTap: () => openGlobalSearch(context),
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 38),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          side: BorderSide(color: AppColors.hairline),
        ),
        child: InkWell(
          onTap: () => openGlobalSearch(context),
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              children: [
                Icon(LucideIcons.search, size: 16, color: AppColors.inkFaint),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    context.t('appbar.search'),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
                  ),
                ),
                const SizedBox(width: 9),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: Text(
                    searchShortcutLabel,
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontSize: 11,
                      color: AppColors.inkFaint,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 38×38 ghost icon button matching the prototype's `.icon-btn`.
class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.active = false,
    this.child,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool active;

  /// Optional overlay (e.g. the unread dot) painted above the icon.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: active ? AppColors.surface : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        side: BorderSide(
          color: active ? AppColors.hairline : Colors.transparent,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        hoverColor: AppColors.surface,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: active ? AppColors.ink : AppColors.inkSoft,
              ),
              ?child,
            ],
          ),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: button) : button;
  }
}
