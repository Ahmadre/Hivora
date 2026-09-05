import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'
    show GlassContainer, GlassQuality, LiquidRoundedSuperellipse;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/repositories/admin_repository.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/audit_models.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/glass_popup_menu.dart';
import '../../../core/widgets/hive_empty_state.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/user_pronouns.dart';
import '../../search/search_tokens.dart';
import '../../shell/page_chrome.dart';
import '../../sprint/modals/glass_modal.dart'
    show showGlassToast, GlassToastKind;
import '../glass_filter_bar.dart';

part 'admin_audit_section.filters.dart';
part 'admin_audit_section.timeline.dart';
part 'admin_audit_section.detail.dart';

/// Docked-toolbar height on compact: search row + gap + chip row.
const double _kAuditDockHeight = kAdminPillHeight * 2 + 8;

/// The admin **Audit log** — a live, filtered, infinite-scrolling timeline of
/// security-relevant events (sign-ins, role changes, settings updates…).
///
/// Self-contained: it owns its scroll, pagination and filter state, so the
/// admin shell renders it directly inside its content [Expanded] rather than
/// wrapping it in the shared `SingleChildScrollView` other sections use.
///
/// Data comes from `GET /api/v1/admin/audit` (newest-first, server-paginated);
/// entries are grouped under day headers and rendered as a vertical timeline
/// with severity-tinted glyphs. Tapping a row opens a liquid-glass detail sheet.
class AdminAuditSection extends StatefulWidget {
  const AdminAuditSection({super.key, this.onBack});

  /// Compact only: the shell back handler. When set, the section owns its own
  /// [PageChrome] so it can dock the filter bar into the glass app bar.
  final VoidCallback? onBack;

  @override
  State<AdminAuditSection> createState() => _AdminAuditSectionState();
}

class _AdminAuditSectionState extends State<AdminAuditSection> {
  static const int _perPage = 30;

  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  // Loaded data (accumulated across pages).
  final List<AuditEntry> _items = [];
  // Flattened render rows: either a [_DayHeader] or an [AuditEntry].
  List<Object> _rows = const [];
  int _total = 0;
  int _loadedPage = 0;

  // Filters.
  String _query = '';
  AuditCategory _category = AuditCategory.unknown;
  AuditSeverity _severity = AuditSeverity.unknown;
  AuditOutcome _outcome = AuditOutcome.unknown;

  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _error = false;
  // Monotonic token so a stale in-flight request can't overwrite newer state
  // (e.g. fast filter changes).
  int _requestId = 0;

  bool get _hasFilters =>
      _query.isNotEmpty ||
      _category != AuditCategory.unknown ||
      _severity != AuditSeverity.unknown ||
      _outcome != AuditOutcome.unknown;

  bool get _hasMore => _items.length < _total;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 480 &&
        _hasMore &&
        !_loadingMore &&
        !_initialLoading) {
      _load(reset: false);
    }
  }

  Future<void> _load({required bool reset}) async {
    final page = reset ? 1 : _loadedPage + 1;
    final reqId = ++_requestId;

    if (reset) {
      setState(() {
        _initialLoading = true;
        _error = false;
      });
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final repo = context.read<AdminRepository>();
      final result = await repo.auditLog(
        query: _query,
        category: _category,
        severity: _severity,
        outcome: _outcome == AuditOutcome.unknown
            ? null
            : _outcome.name.toUpperCase(),
        page: page,
        perPage: _perPage,
      );
      if (!mounted || reqId != _requestId) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(result.items);
        _total = result.total;
        _loadedPage = result.page;
        _rebuildRows();
        _initialLoading = false;
        _loadingMore = false;
        _error = false;
      });
    } catch (_) {
      if (!mounted || reqId != _requestId) return;
      setState(() {
        _initialLoading = false;
        _loadingMore = false;
        if (reset) _error = true;
      });
    }
  }

  /// Collapse the accumulated [_items] into a flat list with day-break headers.
  void _rebuildRows() {
    final rows = <Object>[];
    DateTime? lastDay;
    for (final e in _items) {
      final day = DateUtils.dateOnly(e.timestamp);
      if (lastDay == null || day != lastDay) {
        rows.add(_DayHeader(day));
        lastDay = day;
      }
      rows.add(e);
    }
    _rows = rows;
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      final next = value.trim();
      if (next == _query) return;
      _query = next;
      _load(reset: true);
    });
  }

  void _setCategory(AuditCategory v) {
    if (v == _category) return;
    setState(() => _category = v);
    _load(reset: true);
  }

  void _setSeverity(AuditSeverity v) {
    if (v == _severity) return;
    setState(() => _severity = v);
    _load(reset: true);
  }

  void _setOutcome(AuditOutcome v) {
    if (v == _outcome) return;
    setState(() => _outcome = v);
    _load(reset: true);
  }

  void _clearFilters() {
    _searchCtrl.clear();
    _debounce?.cancel();
    setState(() {
      _query = '';
      _category = AuditCategory.unknown;
      _severity = AuditSeverity.unknown;
      _outcome = AuditOutcome.unknown;
    });
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final filterBar = _FilterBar(
      searchCtrl: _searchCtrl,
      onSearch: _onSearchChanged,
      category: _category,
      severity: _severity,
      outcome: _outcome,
      total: _total,
      hasFilters: _hasFilters,
      loading: _initialLoading,
      onCategory: _setCategory,
      onSeverity: _setSeverity,
      onOutcome: _setOutcome,
      onClear: _clearFilters,
      compact: compact,
    );

    // Compact: search + chips dock into the glass app bar (the section owns its
    // own PageChrome). Wide: the section lives inside the admin shell's own
    // PageChrome + rail, so the glass filter bar stays in-pane above the timeline.
    if (compact) {
      return PageChrome(
        title: context.t('admin.auditLog'),
        onBack: widget.onBack,
        // The filter bar applies the section gutter itself so its chip row can
        // scroll edge-to-edge; don't double-pad here.
        bottom: filterBar,
        bottomHeight: _kAuditDockHeight,
        child: _buildBody(context),
      );
    }
    return Column(
      children: [
        Padding(padding: const EdgeInsets.only(bottom: 12), child: filterBar),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  /// On compact the timeline scrolls *under* the glass app bar (which now holds
  /// the docked filter bar), so it must clear [context.topGutter]. On wide the
  /// filter bar sits in-pane above the timeline, so no extra inset is needed.
  double _bodyTopInset(BuildContext context) =>
      context.isCompact ? context.topGutter : 0;

  Widget _buildBody(BuildContext context) {
    if (_initialLoading) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(48), child: HiveLoader()),
      );
    }
    if (_error) {
      return _ErrorView(onRetry: () => _load(reset: true));
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(reset: true),
        color: AppColors.accentStrong,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            context.pageGutter,
            24 + _bodyTopInset(context),
            context.pageGutter,
            24 + context.bottomGutter,
          ),
          children: [
            HiveEmptyState(
              title: context.t(
                _hasFilters ? 'audit.empty.filtered' : 'audit.empty.title',
              ),
              message: _hasFilters ? null : context.t('audit.empty.message'),
              action: _hasFilters
                  ? OutlinedButton.icon(
                      onPressed: _clearFilters,
                      icon: const Icon(LucideIcons.x, size: 15),
                      label: Text(context.t('audit.filter.reset')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ink,
                        side: BorderSide(color: AppColors.hairline),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      );
    }

    final gutter = context.pageGutter;
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      color: AppColors.accentStrong,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          gutter,
          12 + _bodyTopInset(context),
          gutter,
          16 + context.bottomGutter,
        ),
        // +1 footer row (load-more spinner / end marker).
        itemCount: _rows.length + 1,
        itemBuilder: (context, index) {
          if (index == _rows.length) return _buildFooter(context);
          final row = _rows[index];
          if (row is _DayHeader) {
            return _DayHeaderRow(day: row.day);
          }
          final entry = row as AuditEntry;
          // Continuous timeline rail unless the next row starts a new day.
          final isLastInGroup =
              index + 1 >= _rows.length || _rows[index + 1] is _DayHeader;
          return _AuditTimelineTile(
            entry: entry,
            isLastInGroup: isLastInGroup,
            onTap: () => showAuditDetailSheet(context, entry),
          );
        },
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    if (_loadingMore) {
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
    if (!_hasMore && _items.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.check, size: 13, color: AppColors.inkFaint),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                context.t('audit.endOfList'),
                style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox(height: 8);
  }
}
