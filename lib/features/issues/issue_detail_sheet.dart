import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/widgets/hex_mark.dart';
import '../../core/widgets/hive_loader.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show ProgressiveBlur, ProgressiveBlurDirection;
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wolt_modal_sheet/wolt_modal_sheet.dart';

import '../../core/api/api_client.dart';
import '../../core/api/sse_connection.dart';
import '../../core/repositories/comment_repository.dart';
import '../../core/repositories/domain_providers.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/repositories/media_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/sprint_repository.dart';
import '../../core/repositories/user_repository.dart';
import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/events/issue_events.dart';
import '../../core/i18n/i18n.dart';
import '../../core/util/file_download.dart';
import '../../core/util/reader_time_zone.dart';
import '../../core/util/share_origin.dart';
import '../../core/lexical/hinata_document.dart';
import '../../core/lexical/hinata_editor.dart';
import '../../core/lexical/hinata_editor_controller.dart';
import '../../core/lexical/hinata_editor_tools.dart';
import '../../core/lexical/hinata_lexical.dart';
import '../../core/lexical/hinata_markdown_preview.dart';
import '../../core/lexical/hinata_outline.dart';
import '../../core/models/core_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/models/work_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/hue_colors.dart';
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/user_pronouns.dart';
import '../../core/widgets/markdown_toolbar.dart';
import '../../core/widgets/soft_card.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;

import 'comments/comment_attach.dart';
import 'comments/comment_copy.dart';
import 'comments/comment_thread.dart';
import 'comments/glass_comment_composer.dart';
import 'comments/voice/voice_recorder.dart' show VoiceRecording;
import 'issue_move_wizard.dart';
import '../git/widgets/deployment_panel.dart';
import '../git/widgets/development_summary.dart';
import '../knowledge/data/knowledge_models.dart' show KbArticle, lucideIcon;
import '../knowledge/data/knowledge_repository.dart';
import '../knowledge/knowledge_tokens.dart';
import '../knowledge/markdown/mention_field.dart';
import '../knowledge/markdown/smart_link_resolver.dart';
import '../sprint/modals/estimate_dialog.dart' show showStoryPointsDialog;
import '../sprint/modals/glass_modal.dart'
    show
        GlassField,
        GlassInfoLine,
        GlassModalFooter,
        GlassModalHeader,
        GlassOptionRow,
        GlassToastKind,
        glassInputDecoration,
        glassWoltSurface,
        kGlassPopoverBreakpoint,
        showGlassErrorToast,
        showGlassToast,
        showGlassAnchoredPopover,
        showGlassBottomSheet,
        showGlassDatePicker,
        showGlassModal,
        showGlassOptions;
import 'attachments/attachments_section.dart';
import 'email_reply/email_reply_sheet.dart';
import 'epic_search_popover.dart';
import 'issue_filter.dart' show kIssuePriorityCodes;
import 'issue_form.dart' show showIssueForm;
import 'issue_links_section.dart';
import 'watch/issue_watch_cubit.dart';
import 'watch/issue_watch_menu.dart';
import 'issue_labels.dart';
import 'issue_link_resolver.dart';
import 'work_log_sheet.dart';

part 'issue_detail_sheet.view.dart';
part 'issue_detail_sheet.dialogs.dart';
part 'issue_detail_sheet.create.dart';
part 'issue_detail_sheet.widgets.dart';
part 'issue_detail_sheet.clone.dart';
part 'issue_detail_sheet.export.dart';

/// Row height of the full-screen route's pinned top bar (below the status bar).
/// Shared so [IssueDetailScreen] can offset its scroll content by exactly this
/// much and the bar's blur region lines up with where the content begins.
const double kRouteTopBarHeight = 52;

/// The project's configured colour for a workflow-state name, or null to fall
/// back to the global state palette (`AppColors.stateColor`).
Color? _projStateColor(Project? project, String state) {
  final hue = project?.hueForState(state);
  return hue == null ? null : hueColor(hue);
}

/// A shareable, clean (non-`#`) URL that resolves to the issue — both as a
/// verified deep link into the app and as a normal web route. On web we use the
/// origin the app is served from; on native we derive the public web origin from
/// the configured API server ([apiBaseUrl]) using the convention that the API
/// lives at `api.<domain>` and the web app + App Links at `<domain>`.
String issueWebLink(String apiBaseUrl, String id) {
  if (kIsWeb) {
    try {
      return '${Uri.base.origin}/issues/$id';
    } catch (_) {
      return '/issues/$id';
    }
  }
  final api = Uri.tryParse(apiBaseUrl);
  if (api == null || api.host.isEmpty) return '/issues/$id';
  final host = api.host.startsWith('api.') ? api.host.substring(4) : api.host;
  final origin = Uri(
    scheme: api.scheme,
    host: host,
    port: api.hasPort ? api.port : null,
  );
  return '$origin/issues/$id';
}

/// Centered dialog that can grow much wider than the wolt default so the
/// two-column issue detail has room on desktop.
class _WideDialogType extends WoltDialogType {
  const _WideDialogType();

  @override
  BoxConstraints layoutModal(Size availableSize) {
    const pad = 48.0;
    final width = math.min(
      940.0,
      math.max(360.0, availableSize.width - pad * 2),
    );
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      minHeight: 0,
      maxHeight: math.max(360, availableSize.height * 0.88),
    );
  }
}

/// Opens the issue detail as a responsive wolt modal sheet (bottom sheet on
/// phones, wide centered dialog on desktop). The readable id + actions live in
/// the modal's own top bar; [onChanged] fires whenever the issue is edited or
/// deleted so the caller can refresh its list.
Future<void> showIssueDetailSheet(
  BuildContext context, {
  required String issueId,
  VoidCallback? onChanged,
  String? targetCommentId,
}) {
  final auth = context.read<AuthBloc>();
  final header = ValueNotifier<Issue?>(null);
  final bodyKey = GlobalKey<IssueDetailBodyState>();
  final apiBaseUrl = context.read<IssueRepository>().apiBaseUrl;
  final issueRepo = context.read<IssueRepository>();
  // Captured once here (not inside the rebuilding trailingNavBarWidget
  // builder below) — that builder's closure otherwise re-reads the outer
  // `context` on every `header` update, which can be deactivated by the time
  // a later rebuild fires (e.g. after maximize navigates away and the sheet
  // is minimized again), throwing "Looking up a deactivated widget's
  // ancestor is unsafe".
  final emailReplyEnabled =
      context.read<AppConfigBloc>().state.meta?.isFlagEnabled('emailReply') ??
      false;
  // Own the sheet's scroll controller so the body can animate the feed to the
  // newest comment after posting (phone: the whole sheet scrolls).
  final sheetScroll = ScrollController();
  // Bumped by the body whenever the sticky composer's appearance changes (e.g.
  // entering/leaving inline comment editing) so the sticky bar — a separate
  // subtree from the body — rebuilds to reflect it.
  final composerRev = ValueNotifier<int>(0);

  return WoltModalSheet.show<void>(
    context: context,
    // Push onto the root navigator so the sheet covers the floating glass
    // bottom-nav instead of rendering behind it (the shell nav is a Positioned
    // sibling inside the ShellRoute's nested navigator).
    useRootNavigator: true,
    useSafeArea: false,
    barrierDismissible: true,
    pageContentDecorator: glassWoltSurface,
    modalTypeBuilder: (ctx) => MediaQuery.sizeOf(ctx).width >= 760
        ? const _WideDialogType()
        : WoltModalType.bottomSheet(),
    pageListBuilder: (modalContext) => [
      WoltModalSheetPage(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        // Keyboard must not shrink/resize the sheet content.
        resizeToAvoidBottomInset: false,
        scrollController: sheetScroll,
        hasTopBarLayer: true,
        isTopBarLayerAlwaysVisible: true,
        leadingNavBarWidget: ValueListenableBuilder<Issue?>(
          valueListenable: header,
          builder: (_, issue, _) => issue == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(left: 16.0),
                  child: CopyLinkId(
                    type: issue.type,
                    readableId: issue.readableId,
                    link: issueWebLink(apiBaseUrl, issue.linkId),
                    glyphSize: 24,
                    fontSize: 16,
                  ),
                ),
        ),
        // Rebuilt via the header notifier once the body has loaded the issue
        // and its delete permission, so the action shows the right affordance
        // (trash for admins/leads/team admins, archive for everyone else,
        // restore for archived issues).
        trailingNavBarWidget: ValueListenableBuilder<Issue?>(
          valueListenable: header,
          builder: (_, issue, _) => _SheetActions(
            onMaximize: () {
              final router = GoRouter.of(modalContext);
              Navigator.of(modalContext).maybePop();
              router.push(
                '/issues/$issueId',
                extra: IssueRouteArgs(fromModal: true, onChanged: onChanged),
              );
            },
            onDelete: () => bodyKey.currentState?.confirmDeleteIssue(),
            onExport: (anchor) => bodyKey.currentState?.exportIssue(anchor),
            onClone: () => bodyKey.currentState?.cloneIssue(),
            onMove: () => bodyKey.currentState?.moveIssue(),
            onClose: () => Navigator.of(modalContext).maybePop(),
            canDelete: bodyKey.currentState?.canDelete ?? false,
            archived: issue?.archived ?? false,
            // Read per build (not captured): the body owns the watch cubit and
            // only has one once it has loaded the issue — which is what pushes
            // the `header` update this builder is running for.
            watch: bodyKey.currentState?.watchMenu,
            // Reply-by-email: only for email-sourced issues, gated on the flag.
            onReply: issue != null && issue.isEmailSourced && emailReplyEnabled
                ? () => showEmailReplySheet(
                    modalContext,
                    issue: issue,
                    repo: issueRepo,
                  )
                : null,
          ),
        ),
        // On a phone bottom sheet the comment composer floats here, pinned above
        // the scrolling feed; the wide dialog keeps it inline (returns nothing).
        // Providers are re-supplied because the sticky bar sits outside the
        // body's provider scope (the MentionField reads the repository).
        stickyActionBar: MultiRepositoryProvider(
          providers: [
            ...domainRepositoryProviders(context),
            BlocProvider.value(value: auth),
          ],
          child: ValueListenableBuilder<Issue?>(
            valueListenable: header,
            builder: (ctx, issue, _) {
              final state = bodyKey.currentState;
              if (issue == null || state == null) {
                return const SizedBox.shrink();
              }
              // Rebuild on composer-state changes (edit banner, mode) too.
              return ValueListenableBuilder<int>(
                valueListenable: composerRev,
                builder: (ctx, _, _) {
                  // The sheet doesn't resize for the keyboard — instead lift
                  // the composer so it sits directly above it, like the
                  // full-screen route. Read the RAW view inset (MediaQuery is
                  // unreliable inside Wolt's Scaffold); didChangeMetrics bumps
                  // composerRev as the keyboard moves, so this re-evaluates.
                  final view = View.of(ctx);
                  final keyboard =
                      view.viewInsets.bottom / view.devicePixelRatio;
                  return Padding(
                    padding: EdgeInsets.only(bottom: keyboard),
                    child: state.buildFloatingComposer(
                      ctx,
                      // Keyboard up → flush above it (home indicator hidden).
                      deviceSafeArea: keyboard <= 0,
                    ),
                  );
                },
              );
            },
          ),
        ),
        child: MultiRepositoryProvider(
          providers: [
            ...domainRepositoryProviders(context),
            BlocProvider.value(value: auth),
          ],
          child: IssueDetailBody(
            key: bodyKey,
            issueId: issueId,
            onChanged: onChanged,
            header: header,
            sheetScroll: sheetScroll,
            composerRev: composerRev,
            floatingComposer: true,
            targetCommentId: targetCommentId,
          ),
        ),
      ),
    ],
  ).whenComplete(() {
    // Wolt can complete this future (sheet "closed") a beat before the page's
    // element subtree actually unmounts, leaving the body briefly mounted and
    // still registered as a WidgetsBindingObserver. Tell it to stop writing to
    // `header`/`composerRev` BEFORE we dispose them, else a `didChangeMetrics`
    // landing in that window throws "ValueNotifier used after disposed".
    bodyKey.currentState?.detachHostChannels();
    header.dispose();
    // NOTE: do NOT dispose `sheetScroll` here — Wolt's animated switcher takes
    // ownership of the page's `scrollController` and disposes it itself
    // (WoltModalSheetAnimatedSwitcher.dispose). Disposing it again crashes with
    // "A ScrollController was used after being disposed", which then cascades
    // into a storm of null-check errors from the half-torn-down widget tree.
    composerRev.dispose();
  });
}

/// Arguments handed to the `/issues/:id` route via GoRouter `extra` when the
/// user promotes the modal sheet to the full-page view ("full screen"). They
/// let the page know it may shrink back to the modal ([fromModal]) and carry
/// the caller's refresh callback so list views still update from full screen.
class IssueRouteArgs {
  const IssueRouteArgs({this.fromModal = false, this.onChanged});

  final bool fromModal;
  final VoidCallback? onChanged;
}

/// Full-screen · delete · close — rendered in the wolt top bar. The copy-link
/// affordance now lives on the readable-id chip (see [CopyLinkId]); the leading
/// action here promotes the sheet to the full-page `/issues/:id` view.
class _SheetActions extends StatelessWidget {
  const _SheetActions({
    required this.onMaximize,
    required this.onDelete,
    required this.onClose,
    required this.onExport,
    required this.onClone,
    required this.onMove,
    this.onReply,
    this.watch,
    this.canDelete = false,
    this.archived = false,
  });

  final VoidCallback onMaximize;
  final VoidCallback onDelete;

  /// Opens the export submenu, anchored where the "…" menu stood.
  final void Function(Rect anchorRect) onExport;

  /// Opens the clone dialog.
  final VoidCallback onClone;

  /// Opens the move-to-another-project wizard.
  final VoidCallback onMove;
  final VoidCallback onClose;

  /// Non-null only for email-sourced issues with the `emailReply` flag enabled;
  /// opens the reply-by-email composer.
  final VoidCallback? onReply;

  /// The watch section of the "…" menu; null until the body has loaded.
  final IssueWatchMenuData? watch;

  /// Whether the current user may hard-delete (trash icon); regular members
  /// only see the archive affordance, archived issues a restore one.
  final bool canDelete;
  final bool archived;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: context.t('issues.maximize'),
          onPressed: onMaximize,
          icon: Icon(LucideIcons.maximize2, size: 19, color: AppColors.inkSoft),
        ),
        // Secondary actions (watch · clone · move · reply · remove) share one
        // "…" popover so the header keeps a fixed shape regardless of which are
        // available.
        _IssueActionsMenu(
          onReply: onReply,
          onExport: onExport,
          onClone: onClone,
          onMove: onMove,
          onDelete: onDelete,
          canDelete: canDelete,
          archived: archived,
          watch: watch,
        ),
        IconButton(
          tooltip: context.t('common.cancel'),
          onPressed: onClose,
          icon: Icon(LucideIcons.x, size: 20, color: AppColors.inkSoft),
        ),
        const SizedBox(width: 16),
      ],
    );
  }
}

/// The readable-id chip with a Jira-style "copy link" affordance.
///
/// Desktop / mouse: hovering near the id fades a copy icon in from the left;
/// clicking it (or the id) copies the shareable issue link and morphs the icon
/// into a green check with a "Copied!" tooltip, reverting after a moment.
///
/// Touch: a single tap on the id copies the link and floats a small hint chip
/// ("Link to HIN-39 copied") just below the id, since there is no hover state.
class CopyLinkId extends StatefulWidget {
  const CopyLinkId({
    super.key,
    required this.type,
    required this.readableId,
    required this.link,
    this.glyphSize = 22,
    this.fontSize = 13,
    this.color,
    this.showGlyph = true,
  });

  final String type;
  final String readableId;
  final String link;
  final double glyphSize;
  final double fontSize;
  final Color? color;

  /// Whether to render the leading type glyph before the id (the modal header
  /// shows it; the route top bar already has a back button and omits it).
  final bool showGlyph;

  @override
  State<CopyLinkId> createState() => _CopyLinkIdState();
}

class _CopyLinkIdState extends State<CopyLinkId> {
  final LayerLink _layerLink = LayerLink();
  bool _hovering = false;
  bool _copied = false;
  Timer? _revertTimer;
  OverlayEntry? _hintEntry;
  Timer? _hintTimer;

  @override
  void dispose() {
    _revertTimer?.cancel();
    _hintTimer?.cancel();
    _removeHint();
    super.dispose();
  }

  void _removeHint() {
    _hintEntry?.remove();
    _hintEntry = null;
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.link));
    setState(() => _copied = true);
    _revertTimer?.cancel();
    _revertTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
    // No hover state means a touch device — surface the inline confirmation
    // chip below the id (desktop relies on the icon morph + tooltip instead).
    if (!_hovering) _showHint();
  }

  void _showHint() {
    _removeHint();
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final id = widget.readableId;
    _hintEntry = OverlayEntry(
      // A transient confirmation toast — it must never intercept pointers, and
      // IgnorePointer also stops the mouse-tracker from hit-testing down into its
      // animated (Transform) subtree mid-relayout (the `!debugNeedsLayout`
      // assert-flood class of bug — see the id-icon note above).
      builder: (_) => Positioned(
        width: 300,
        child: IgnorePointer(
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 30),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _CopiedHintChip(id: id),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_hintEntry!);
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(milliseconds: 2000), _removeHint);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _hovering || _copied;
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _copy,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showGlyph) ...[
                TypeGlyph(type: widget.type, size: widget.glyphSize),
                const SizedBox(width: 10),
              ],
              IdMono(
                widget.readableId,
                color: widget.color ?? AppColors.inkSoft,
                fontSize: widget.fontSize,
              ),
              // Reserved fixed-size slot: the icon fades in on hover (or once
              // copied), so the row width never jumps. Deliberately a plain
              // fade, NOT an AnimatedSlide/Transform: a translating render object
              // (RenderFractionalTranslation) asserts `!debugNeedsLayout` when
              // the web mouse-tracker hit-tests it mid-relayout — while the sheet
              // is loading comments its layout churns every frame, which turned
              // that into an assert flood that hung the app on web/desktop.
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: visible ? 1 : 0,
                  child: Tooltip(
                    message: context.t(
                      _copied ? 'issues.copied' : 'issues.copyLink',
                    ),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: Center(
                        child: _copied
                            ? Container(
                                width: 18,
                                height: 18,
                                decoration: const BoxDecoration(
                                  color: AppColors.success,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  LucideIcons.check,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                LucideIcons.link,
                                size: 16,
                                color: widget.color ?? AppColors.inkSoft,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The floating "Link to HIN-39 copied" chip shown under the id on touch.
class _CopiedHintChip extends StatelessWidget {
  const _CopiedHintChip({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      tween: Tween(begin: 0, end: 1),
      builder: (_, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - t) * -6),
          child: child,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.link, size: 16, color: Colors.white),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  context.t('issues.linkCopiedFor', variables: {'id': id}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
