import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/widgets/hive_loader.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wolt_modal_sheet/wolt_modal_sheet.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/domain_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../sprint/modals/glass_modal.dart'
    show glassWoltSurface, showGlassConfirm;
import 'issue_detail_sheet.dart';

/// Centered create-issue dialog for wider screens — mirrors the issue detail
/// sheet's modal chrome and width so the two-column create layout has room.
class _CreateDialogType extends WoltDialogType {
  const _CreateDialogType();

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

/// Opens the *create* issue form with the same modern Wolt modal chrome as the
/// issue detail sheet: bottom sheet on phones, wide centered dialog on desktop,
/// a persistent top bar (title + close), the same two-column layout, and a
/// pinned (sticky) save button that gates on validation, shows a loading state,
/// then an animated check. On success the freshly created issue is opened in
/// the detail sheet.
Future<Issue?> showIssueForm(
  BuildContext context, {
  String? projectId,
  String? initialState,
  String? initialSprintId,
  String? parentId,
  String? forcedType,
  String? initialAssigneeId,
}) async {
  final controller = IssueCreateController();

  final created = await WoltModalSheet.show<Issue?>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    // A stray tap on the barrier (common on desktop) shouldn't silently throw
    // away a typed draft — confirm first when the form has unsaved content.
    onModalDismissedWithBarrierTap: () async {
      final nav = Navigator.of(context, rootNavigator: true);
      if (!(controller.hasDraft?.call() ?? false)) {
        nav.pop();
        return;
      }
      final discard = await showGlassConfirm(
        context,
        icon: LucideIcons.triangleAlert,
        title: context.t('issues.discardDraftTitle'),
        message: context.t('issues.discardDraftMessage'),
        confirmLabel: context.t('issues.discardDraft'),
        confirmIcon: LucideIcons.trash2,
        destructive: true,
      );
      if (discard == true) nav.pop();
    },
    // Let our own sticky save bar own the bottom safe-area inset. Wolt's
    // default (useSafeArea: true) wraps the whole page in SafeArea, which on top
    // of the save bar's own SafeArea double-counts the home indicator — that
    // pushed the button up off the modal bottom and cut the last field off.
    useSafeArea: false,
    pageContentDecorator: glassWoltSurface,
    modalTypeBuilder: (ctx) => MediaQuery.sizeOf(ctx).width >= 760
        ? const _CreateDialogType()
        : WoltModalType.bottomSheet(),
    pageListBuilder: (modalContext) => [
      WoltModalSheetPage(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        hasTopBarLayer: true,
        isTopBarLayerAlwaysVisible: true,
        topBarTitle: Text(
          context.t('issues.new'),
          style: const TextStyle(
            fontFamily: AppTheme.fontBrand,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        trailingNavBarWidget: Container(
          margin: const EdgeInsetsDirectional.only(end: 12),
          child: IconButton(
            onPressed: () => Navigator.of(modalContext).maybePop(),
            icon: Icon(LucideIcons.x, color: AppColors.inkSoft),
          ),
        ),
        stickyActionBar: _CreateSaveBar(controller: controller),
        child: MultiRepositoryProvider(
          providers: domainRepositoryProviders(context),
          child: IssueCreateBody(
            controller: controller,
            projectId: projectId,
            initialState: initialState,
            initialSprintId: initialSprintId,
            parentId: parentId,
            forcedType: forcedType,
            initialAssigneeId: initialAssigneeId,
            onCreated: (issue) => Navigator.of(modalContext).pop(issue),
          ),
        ),
      ),
    ],
  );

  controller.dispose();

  // On success, take the user straight into the new issue's detail view.
  if (created != null && context.mounted) {
    await showIssueDetailSheet(context, issueId: created.id);
  }
  return created;
}

/// Pinned save button at the bottom of the create modal. The button stays
/// pressable (so a tap can surface form-validation errors); it shows a spinner
/// while saving and an animated green check on success. Colour + content
/// transitions are animated.
class _CreateSaveBar extends StatelessWidget {
  const _CreateSaveBar({required this.controller});

  final IssueCreateController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final phase = controller.phase;
        final success = phase == IssueCreatePhase.success;
        // Only block re-taps while a save is in flight or already done.
        final pressable = phase == IssueCreatePhase.idle;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              height: 50,
              decoration: BoxDecoration(
                color: success ? AppColors.success : AppColors.navy,
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: pressable ? () => controller.submit?.call() : null,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: anim,
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: switch (phase) {
                        IssueCreatePhase.saving => const SizedBox(
                          key: ValueKey('saving'),
                          width: 22,
                          height: 22,
                          child: HiveLoader(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        IssueCreatePhase.success => const Icon(
                          LucideIcons.check,
                          key: ValueKey('success'),
                          size: 26,
                          color: Colors.white,
                        ),
                        IssueCreatePhase.idle => Text(
                          context.t('common.save'),
                          key: const ValueKey('idle'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
