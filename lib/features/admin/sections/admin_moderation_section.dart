import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/blocs/paged_cubit.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_bulk_bar.dart';
import '../../../core/widgets/glass_popup_menu.dart';
import '../../../core/widgets/hive_empty_state.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../sprint/modals/glass_modal.dart'
    show
        GlassModalFooter,
        GlassModalHeader,
        GlassToastKind,
        glassInputDecoration,
        kGlassPopoverBreakpoint,
        showGlassErrorToast,
        showGlassModal,
        showGlassToast;
import '../admin_form_helpers.dart';
import '../glass_filter_bar.dart';
import '../moderation/moderation_models.dart';
import '../moderation/moderation_repository.dart';

part 'admin_moderation_section.policy.dart';
part 'admin_moderation_section.queue.dart';

/// Widest the policy form is allowed to stretch — the same cap the admin shell
/// puts on every other settings section, applied here because this section
/// bypasses that wrapper to own its scroll.
const double _kFormMax = 1400;

/// The admin **Moderation** section: the content policy on top, the moderator's
/// work queue below it.
///
/// The two belong on one screen because they are the same decision seen twice —
/// every threshold above changes what lands in the list below, and an admin
/// re-tuning a threshold wants to see the backlog it produces without
/// navigating away.
///
/// The policy half follows the shared draft + save-bar pattern: it mutates
/// `settings['moderation']` in place and the admin shell's Save action PUTs the
/// whole settings document. The queue half owns its own pagination, which is
/// why this section is rendered directly by the shell instead of inside the
/// shared `SingleChildScrollView` — an infinite list nested in a parent scroll
/// view has unbounded height and never pages.
class AdminModerationSection extends StatefulWidget {
  const AdminModerationSection({super.key, required this.settings});

  /// The admin settings draft, shared with every other section.
  final Map<String, dynamic> settings;

  @override
  State<AdminModerationSection> createState() => _AdminModerationSectionState();
}

/// Which of the two queues is on screen.
enum _QueueTab { flagged, reports }

class _AdminModerationSectionState extends State<AdminModerationSection> {
  static const int _pageSize = 25;

  late final AdminModerationRepository _repo;
  late final PagedCubit<ModerationRecord> _records;
  late final PagedCubit<ContentReport> _reports;

  final ScrollController _scroll = ScrollController();

  /// Ids picked for a bulk decision. Cleared on every filter, tab and reload
  /// change, so a decision can never reach rows the moderator can no longer see.
  final Set<String> _selected = <String>{};

  _QueueTab _tab = _QueueTab.flagged;

  // Filters. `null` means "no filter"; both queues open on the backlog, which
  // is the only view a moderator actually works from.
  ModerationReviewState? _recordState = ModerationReviewState.open;
  ContentReportState? _reportState = ContentReportState.open;
  ModerationSurfaceKind? _surface;
  ModerationCategoryKind? _category;

  /// True while a decision is in flight, so the row actions and the bulk bar
  /// cannot fire twice for the same item.
  bool _deciding = false;

  @override
  void initState() {
    super.initState();
    _repo = AdminModerationRepository(context.read<ApiClient>());
    // The fetchers read the filter fields at call time rather than capturing
    // them, so a filter change is just `load()`. That also puts the stale-page
    // guard where it belongs: `PagedCubit.load` bumps a monotonic token, which
    // is the same defence `admin_audit_section.dart` spells out by hand — a
    // slower page for the previous filter is dropped instead of overwriting the
    // newer one.
    _records = PagedCubit<ModerationRecord>(
      (page, size) => _repo.records(
        state: _recordState,
        surface: _surface,
        category: _category,
        page: page,
        size: size,
      ),
      pageSize: _pageSize,
      keyOf: (record) => record.id,
    )..load();
    // Not loaded up-front: most visits never open the reports tab, and the
    // request would be spent on a list nobody looked at.
    _reports = PagedCubit<ContentReport>(
      (page, size) =>
          _repo.reports(state: _reportState, page: page, size: size),
      pageSize: _pageSize,
      keyOf: (report) => report.id,
    );
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _records.close();
    _reports.close();
    super.dispose();
  }

  /// Infinite scroll: pull the next page as the user nears the bottom.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels < position.maxScrollExtent - 480) return;
    switch (_tab) {
      case _QueueTab.flagged:
        _records.loadMore();
      case _QueueTab.reports:
        _reports.loadMore();
    }
  }

  bool get _hasFilters => switch (_tab) {
    _QueueTab.flagged =>
      _recordState != ModerationReviewState.open ||
          _surface != null ||
          _category != null,
    _QueueTab.reports => _reportState != ContentReportState.open,
  };

  Future<void> _reload() {
    _selected.clear();
    return switch (_tab) {
      _QueueTab.flagged => _records.load(),
      _QueueTab.reports => _reports.load(),
    };
  }

  void _selectTab(_QueueTab tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _selected.clear();
    });
    // First visit to the reports tab: nothing has been fetched yet.
    if (tab == _QueueTab.reports && !_reports.state.hasData) _reports.load();
  }

  void _setRecordState(ModerationReviewState? value) {
    if (value == _recordState) return;
    setState(() => _recordState = value);
    _reload();
  }

  void _setReportState(ContentReportState? value) {
    if (value == _reportState) return;
    setState(() => _reportState = value);
    _reload();
  }

  void _setSurface(ModerationSurfaceKind? value) {
    if (value == _surface) return;
    setState(() => _surface = value);
    _reload();
  }

  void _setCategory(ModerationCategoryKind? value) {
    if (value == _category) return;
    setState(() => _category = value);
    _reload();
  }

  void _clearFilters() {
    setState(() {
      _recordState = ModerationReviewState.open;
      _reportState = ContentReportState.open;
      _surface = null;
      _category = null;
    });
    _reload();
  }

  void _toggleSelected(String id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });

  /// Opens the item a row points at. The moderator judges the content in place;
  /// the queue never shows it, because a second store of the worst material in
  /// the product is exactly what the record format exists to avoid.
  void _open(String route) => context.push(route);

  // ── Decisions ──────────────────────────────────────────────────────────

  Future<void> _decideRecords(
    List<String> ids,
    ModerationReviewState state,
  ) async {
    final confirmed = state == ModerationReviewState.confirmed;
    final note = await _askForNote(
      icon: confirmed ? LucideIcons.gavel : LucideIcons.circleCheck,
      title: context.t(
        confirmed
            ? 'moderation.queue.confirm.title'
            : 'moderation.queue.dismiss.title',
      ),
      subtitle: context.t(
        confirmed
            ? 'moderation.queue.confirm.message'
            : 'moderation.queue.dismiss.message',
        variables: {'count': '${ids.length}'},
      ),
      confirmLabel: context.t(
        confirmed
            ? 'moderation.queue.action.confirm'
            : 'moderation.queue.action.dismiss',
      ),
      destructive: confirmed,
    );
    if (note == null) return;
    await _apply(
      ids,
      (id) => _repo.reviewRecord(id, state: state, note: note),
      doneKey: confirmed
          ? 'moderation.queue.done.confirmed'
          : 'moderation.queue.done.dismissed',
    );
  }

  Future<void> _decideReports(
    List<String> ids,
    ContentReportState state,
  ) async {
    final actioned = state == ContentReportState.actioned;
    final note = await _askForNote(
      icon: actioned ? LucideIcons.gavel : LucideIcons.circleCheck,
      title: context.t(
        actioned
            ? 'moderation.queue.uphold.title'
            : 'moderation.queue.rejectReport.title',
      ),
      subtitle: context.t(
        actioned
            ? 'moderation.queue.uphold.message'
            : 'moderation.queue.rejectReport.message',
        variables: {'count': '${ids.length}'},
      ),
      confirmLabel: context.t(
        actioned
            ? 'moderation.queue.action.uphold'
            : 'moderation.queue.action.dismiss',
      ),
      destructive: actioned,
    );
    if (note == null) return;
    await _apply(
      ids,
      (id) => _repo.handleReport(id, state: state, note: note),
      doneKey: actioned
          ? 'moderation.queue.done.actioned'
          : 'moderation.queue.done.dismissed',
    );
  }

  /// Runs [call] for every id and refreshes from the server afterwards.
  ///
  /// The list is refetched rather than patched locally on purpose: a decision
  /// normally moves the row out of the `OPEN` filter, and letting the server say
  /// so keeps the count in the header and the rows on screen telling the same
  /// story — a locally removed row that the write actually failed for would be
  /// invisible until the next visit.
  Future<void> _apply(
    List<String> ids,
    Future<void> Function(String id) call, {
    required String doneKey,
  }) async {
    if (ids.isEmpty || _deciding) return;
    setState(() => _deciding = true);
    try {
      for (final id in ids) {
        await call(id);
      }
      if (mounted) {
        showGlassToast(
          context,
          context.t(doneKey, variables: {'count': '${ids.length}'}),
          kind: GlassToastKind.success,
        );
      }
    } on ApiFailure catch (failure) {
      if (mounted) showGlassErrorToast(context, context.t(failure.message));
    } catch (_) {
      if (mounted) showGlassErrorToast(context, context.t('errors.unexpected'));
    } finally {
      // Both guarded: a decision that outlives the panel (the admin navigated
      // away mid-write) must not emit into a closed cubit.
      if (mounted) {
        setState(() => _deciding = false);
        await _reload();
      }
    }
  }

  /// The decision dialog. Resolves to the moderator's note (possibly empty) or
  /// `null` when they backed out — the note is optional, so an empty string and
  /// a cancel must stay distinguishable.
  Future<String?> _askForNote({
    required IconData icon,
    required String title,
    required String subtitle,
    required String confirmLabel,
    required bool destructive,
  }) async {
    final controller = TextEditingController();
    try {
      return await showGlassModal<String>(
        context,
        width: 460,
        builder: (modalContext) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassModalHeader(icon: icon, title: title, subtitle: subtitle),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    modalContext.t('moderation.queue.note.label'),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 7),
                  TextField(
                    controller: controller,
                    maxLines: 3,
                    minLines: 2,
                    autofocus: true,
                    style: TextStyle(fontSize: 14, color: AppColors.ink),
                    decoration: glassInputDecoration(
                      hint: modalContext.t('moderation.queue.note.hint'),
                    ),
                  ),
                ],
              ),
            ),
            GlassModalFooter(
              confirmLabel: confirmLabel,
              confirmIcon: LucideIcons.check,
              confirmColor: destructive ? AppColors.danger : null,
              // Pops the builder's OWN context: popping the section's context
              // would tear down the route behind the modal instead.
              onConfirm: () =>
                  Navigator.of(modalContext).pop(controller.text.trim()),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  // ── Layout ─────────────────────────────────────────────────────────────

  /// On compact the section scrolls *under* the shell's glass app bar, so it
  /// clears [ResponsiveContext.topGutter] itself; on wide the shell already
  /// insets the pane.
  double get _topInset => context.isCompact ? context.topGutter : 0;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint;
    return switch (_tab) {
      _QueueTab.flagged => BlocBuilder<
        PagedCubit<ModerationRecord>,
        PagedState<ModerationRecord>
      >(
        bloc: _records,
        builder: (context, state) => _scaffold(context, wide, state.total, [
          for (final record in state.items)
            _RecordRow(
              record: record,
              wide: wide,
              busy: _deciding,
              selected: _selected.contains(record.id),
              onToggleSelected: () => _toggleSelected(record.id),
              onOpen: record.route == null
                  ? null
                  : () => _open(record.route!),
              onConfirm: () => _decideRecords([
                record.id,
              ], ModerationReviewState.confirmed),
              onDismiss: () => _decideRecords([
                record.id,
              ], ModerationReviewState.dismissed),
            ),
        ], state),
      ),
      _QueueTab.reports =>
        BlocBuilder<PagedCubit<ContentReport>, PagedState<ContentReport>>(
          bloc: _reports,
          builder: (context, state) => _scaffold(context, wide, state.total, [
            for (final report in state.items)
              _ReportRow(
                report: report,
                wide: wide,
                busy: _deciding,
                selected: _selected.contains(report.id),
                onToggleSelected: () => _toggleSelected(report.id),
                onOpen: report.route == null
                    ? null
                    : () => _open(report.route!),
                onConfirm: () => _decideReports([
                  report.id,
                ], ContentReportState.actioned),
                onDismiss: () => _decideReports([
                  report.id,
                ], ContentReportState.dismissed),
              ),
          ], state),
        ),
    };
  }

  /// The shared frame: policy panel, queue header, [rows], footer — and the
  /// floating bulk bar once anything is selected.
  Widget _scaffold(
    BuildContext context,
    bool wide,
    int total,
    List<Widget> rows,
    PagedState<Object> state,
  ) {
    final gutter = context.pageGutter;
    // With no rows the list still needs one slot — for the loader, the error or
    // the empty state.
    final slotCount = rows.isEmpty ? 1 : rows.length;
    final selecting = _selected.isNotEmpty;

    final list = ListView.builder(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        gutter,
        12 + _topInset,
        gutter,
        16 + context.bottomGutter + (selecting ? 72 : 0),
      ),
      // policy + queue header + rows + footer
      itemCount: 2 + slotCount + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 28),
            // The form is capped like every other admin section's; the queue
            // below is not, because dense rows use the width and sparse fields
            // do not.
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _kFormMax),
                child: _PolicyPanel(settings: widget.settings),
              ),
            ),
          );
        }
        if (index == 1) {
          return _QueueHeader(
            tab: _tab,
            wide: wide,
            total: total,
            loading: state.isLoading,
            hasFilters: _hasFilters,
            recordState: _recordState,
            reportState: _reportState,
            surface: _surface,
            category: _category,
            onTab: _selectTab,
            onRecordState: _setRecordState,
            onReportState: _setReportState,
            onSurface: _setSurface,
            onCategory: _setCategory,
            onClear: _clearFilters,
          );
        }
        if (index == 2 + slotCount) return _footer(context, state);
        if (rows.isEmpty) return _slot(context, state);
        return rows[index - 2];
      },
    );

    return Stack(
      children: [
        // The iOS numeric keypad has no Done key, so the policy fields get the
        // same two ways out the other admin sections have: tap outside, or
        // drag-scroll the body.
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: RefreshIndicator(
            onRefresh: _reload,
            color: AppColors.accentStrong,
            child: list,
          ),
        ),
        if (selecting)
          Positioned(
            left: gutter,
            right: gutter,
            bottom: context.bottomGutter + 12,
            child: Center(child: _bulkBar(context)),
          ),
      ],
    );
  }

  /// The one row that stands in for the whole list while it is loading, broken
  /// or empty. The policy panel above stays usable throughout — a queue that
  /// cannot be reached is no reason to lock an admin out of the thresholds.
  Widget _slot(BuildContext context, PagedState<Object> state) {
    // Error first: a failed first load never sets `hasData`, so testing the
    // loader condition ahead of it would spin forever on an unreachable server.
    if (state.errorKey != null) {
      return _QueueError(message: state.errorKey!, onRetry: _reload);
    }
    if (state.isLoading || !state.hasData) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: HiveLoader()),
      );
    }
    final flagged = _tab == _QueueTab.flagged;
    return HiveEmptyState(
      title: context.t(
        _hasFilters
            ? 'moderation.queue.empty.filtered'
            : (flagged
                  ? 'moderation.queue.empty.flagged.title'
                  : 'moderation.queue.empty.reports.title'),
      ),
      message: _hasFilters
          ? null
          : context.t(
              flagged
                  ? 'moderation.queue.empty.flagged.message'
                  : 'moderation.queue.empty.reports.message',
            ),
      action: _hasFilters
          ? OutlinedButton.icon(
              onPressed: _clearFilters,
              icon: const Icon(LucideIcons.x, size: 15),
              label: Text(context.t('moderation.queue.filter.reset')),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.ink,
                side: BorderSide(color: AppColors.hairline),
              ),
            )
          : null,
    );
  }

  Widget _footer(BuildContext context, PagedState<Object> state) {
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 22),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: HiveLoader(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!state.hasMore && state.items.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.check, size: 13, color: AppColors.inkFaint),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                context.t('moderation.queue.endOfList'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox(height: 8);
  }

  Widget _bulkBar(BuildContext context) {
    final ids = _selected.toList();
    final flagged = _tab == _QueueTab.flagged;
    return GlassBulkBar(
      countLabel: context.t(
        'moderation.queue.selectedCount',
        variables: {'count': '${ids.length}'},
      ),
      clearTooltip: context.t('moderation.queue.clearSelection'),
      onClear: () => setState(_selected.clear),
      actions: [
        GlassBulkAction(
          icon: LucideIcons.gavel,
          label: context.t(
            flagged
                ? 'moderation.queue.action.confirm'
                : 'moderation.queue.action.uphold',
          ),
          danger: true,
          onTap: () => flagged
              ? _decideRecords(ids, ModerationReviewState.confirmed)
              : _decideReports(ids, ContentReportState.actioned),
        ),
        GlassBulkAction(
          icon: LucideIcons.circleCheck,
          label: context.t('moderation.queue.action.dismiss'),
          onTap: () => flagged
              ? _decideRecords(ids, ModerationReviewState.dismissed)
              : _decideReports(ids, ContentReportState.dismissed),
        ),
      ],
    );
  }
}
