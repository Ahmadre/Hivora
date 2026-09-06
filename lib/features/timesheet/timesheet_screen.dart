import 'package:flutter/material.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/soft_card.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/timesheet_repository.dart';
import '../../core/repositories/user_repository.dart';

/// Weekly timesheet matrix (user x day), YouTrack-style.
class TimesheetScreen extends StatefulWidget {
  const TimesheetScreen({super.key});

  @override
  State<TimesheetScreen> createState() => _TimesheetScreenState();
}

class _TimesheetScreenState extends State<TimesheetScreen> {
  late DateTime _from;
  late DateTime _to;
  List<TimesheetRow> _rows = const [];
  Map<String, DirectoryUser> _users = const {};
  Map<String, Project> _projects = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = now.subtract(Duration(days: now.weekday - 1));
    _to = _from.add(const Duration(days: 6));
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        context.read<TimesheetRepository>().timesheet(_from, _to),
        context.read<UserRepository>().users(),
        context.read<ProjectRepository>().projects(),
      ]);
      _rows = results[0] as List<TimesheetRow>;
      _users = {
        for (final user in results[1] as List<DirectoryUser>) user.id: user,
      };
      _projects = {
        for (final project in results[2] as List<Project>) project.id: project,
      };
      setState(() => _loading = false);
    } on ApiFailure catch (failure) {
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  void _shiftWeek(int direction) {
    setState(() {
      _from = _from.add(Duration(days: 7 * direction));
      _to = _to.add(Duration(days: 7 * direction));
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final days = [
      for (var i = 0; i <= _to.difference(_from).inDays; i++)
        _from.add(Duration(days: i)),
    ];
    return SingleChildScrollView(
      padding: context.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (context.isCompact) ...[
            PageHead(title: context.t('timesheet.title')),
            const SizedBox(height: 12),
            _weekNav(localizations),
          ] else
            PageHead(
              title: context.t('timesheet.title'),
              actions: [_weekNav(localizations)],
            ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(60),
              child: Center(child: HiveLoader()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Text(
                context.t(_error!),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          else if (_rows.isEmpty)
            HiveEmptyState(
              title: context.t('timesheet.title'),
              message: context.t('timesheet.empty'),
            )
          else
            SoftCard(
              padding: const EdgeInsets.all(8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingTextStyle: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: AppColors.textPrimary,
                  ),
                  columns: [
                    DataColumn(label: Text(context.t('timesheet.member'))),
                    DataColumn(label: Text(context.t('timesheet.project'))),
                    for (final day in days)
                      DataColumn(
                        label: Text(localizations.formatShortDate(day)),
                      ),
                    DataColumn(label: Text(context.t('timesheet.total'))),
                  ],
                  rows: [
                    for (final row in _rows)
                      DataRow(
                        cells: [
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppAvatar(
                                  name: _users[row.userId]?.displayName ?? '?',
                                  pronouns: _users[row.userId]?.pronouns,
                                  radius: 12,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _users[row.userId]?.displayName ?? row.userId,
                                ),
                              ],
                            ),
                          ),
                          DataCell(Text(_projects[row.projectId]?.key ?? '–')),
                          for (final day in days)
                            DataCell(Text(_formatCell(row, day))),
                          DataCell(
                            Text(
                              _formatMinutes(row.totalMinutes),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _weekNav(MaterialLocalizations localizations) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () => _shiftWeek(-1),
          icon: Icon(backChevron(context)),
        ),
        Text(
          '${localizations.formatShortDate(_from)} – ${localizations.formatShortDate(_to)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        IconButton(
          onPressed: () => _shiftWeek(1),
          icon: Icon(forwardChevron(context)),
        ),
      ],
    );
  }

  String _formatCell(TimesheetRow row, DateTime day) {
    final minutes = row.minutesPerDay.entries
        .where(
          (entry) =>
              entry.key.year == day.year &&
              entry.key.month == day.month &&
              entry.key.day == day.day,
        )
        .fold<int>(0, (sum, entry) => sum + entry.value);
    return minutes == 0 ? '–' : _formatMinutes(minutes);
  }

  String _formatMinutes(int minutes) {
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (hours == 0) return '${rest}m';
    return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
  }
}
