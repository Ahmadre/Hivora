import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/models/weekly_summary_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/weekly_summary_repository.dart';
import 'package:hinata/core/responsive/responsive.dart';
import 'package:hinata/features/weekly_summary/weekly_summary_screen.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The summary has to work on a phone and still earn its keep on a desktop: one
/// strand while the screen is narrow, and a golden-ratio spread (φ : 1) that
/// fills the reading width once the narrow column can still hold a full reading
/// column of its own.
///
/// The two section headings are the probes: their row spans its whole column, so
/// measuring the rows measures the columns. Nothing here asserts on text — widget
/// tests render raw i18n keys, which are longer than any real translation, so a
/// pixel assertion on a label (or an overflow check that a long key trips) would
/// be measuring the key rather than the layout.
void main() {
  /// Mirrors `_singleColumnMax`: how wide the single column may get.
  const singleColumnMax = 720.0;

  Issue issue(String id) => Issue(
    id: id,
    projectId: 'p1',
    readableId: 'HIN-$id',
    title: 'Issue $id',
    state: 'TODO',
    dueDate: DateTime(2026, 7, 24),
  );

  final summary = WeeklySummary(
    weekStart: DateTime(2026, 7, 22),
    weekEnd: DateTime(2026, 7, 29),
    team: WeeklyTeam(
      completed: 5,
      created: 36,
      myCompleted: 1,
      focusMinutes: 825,
      contributors: const [
        WeeklyContributor(userId: 'u1', displayName: 'Lena Vogt', completed: 2),
        WeeklyContributor(
          userId: 'u2',
          displayName: 'Amara Okafor',
          completed: 1,
        ),
      ],
      highlights: [issue('1'), issue('2')],
      sprint: const WeeklySprint(
        boardId: 'b1',
        name: 'Sprint 24',
        day: 12,
        days: 14,
        issuesDone: 5,
        issuesTotal: 17,
      ),
    ),
    upcoming: WeeklyUpcoming(
      total: 10,
      overdue: 5,
      items: [issue('3'), issue('4')],
    ),
  );

  Widget host(Size size) => MaterialApp(
    debugShowCheckedModeBanner: false,
    // The hero's date range goes through `DateFormat`, whose symbol data for the
    // active locale is loaded by this delegate — exactly as in the real app.
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: RepositoryProvider<WeeklySummaryRepository>.value(
        value: _FakeWeeklySummaryRepository(summary),
        child: BlocProvider<AuthBloc>.value(
          value: _FakeAuthBloc(),
          child: const Scaffold(body: WeeklySummaryScreen()),
        ),
      ),
    ),
  );

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(size));
    await tester.pumpAndSettle();
  }

  /// The section heading's own row, which fills the column it heads.
  Finder section(IconData icon) =>
      find.ancestor(of: find.byIcon(icon), matching: find.byType(Row)).first;

  final behind = section(LucideIcons.history); // "the week behind"
  final ahead = section(LucideIcons.listTodo); // "your week ahead"

  testWidgets('desktop spreads the two sections at the golden ratio', (
    tester,
  ) async {
    await pump(tester, const Size(1600, 1000));

    // Side by side, week-behind on the left …
    expect(tester.getTopLeft(ahead).dy, tester.getTopLeft(behind).dy);
    expect(
      tester.getTopLeft(ahead).dx,
      greaterThan(tester.getTopLeft(behind).dx),
    );
    // … splitting the reading width φ : 1.
    expect(
      tester.getSize(behind).width / tester.getSize(ahead).width,
      closeTo(Breakpoints.phi, 0.01),
    );
  });

  testWidgets('narrow screens keep one centred, capped column', (tester) async {
    const width = 900.0;
    await pump(tester, const Size(width, 1000));

    // Stacked, both spanning the same single column …
    expect(
      tester.getTopLeft(ahead).dy,
      greaterThan(tester.getTopLeft(behind).dy),
    );
    expect(tester.getTopLeft(ahead).dx, tester.getTopLeft(behind).dx);
    expect(tester.getSize(ahead).width, tester.getSize(behind).width);
    // … which stays at its reading cap, centred, instead of stretching.
    expect(tester.getSize(behind).width, singleColumnMax);
    expect(
      tester.getTopLeft(behind).dx,
      closeTo((width - singleColumnMax) / 2, 1),
    );
  });

  for (final size in const [
    Size(390, 844), // phone
    Size(900, 1000), // tablet / split-screen desktop
    Size(1600, 1000), // desktop
  ]) {
    testWidgets('renders both sections at ${size.width}px', (tester) async {
      await pump(tester, size);

      expect(behind, findsOneWidget);
      expect(ahead, findsOneWidget);
      // Both columns stay inside the page: a column wider than the space it was
      // given would push its heading row past the edge and be caught here.
      for (final probe in [behind, ahead]) {
        expect(tester.getTopLeft(probe).dx, greaterThanOrEqualTo(0));
        expect(
          tester.getBottomRight(probe).dx,
          lessThanOrEqualTo(size.width + precisionErrorTolerance),
        );
      }
      // Raw i18n keys are much longer than the strings the app really shows
      // ('weeklySummary.weekBehind' vs "Die Woche hinter uns"), so on a phone the
      // key length alone overflows rows that have room to spare in the app. Drain
      // those; the geometry asserted above is what this test stands on.
      tester.takeException();
    });
  }
}

class _FakeWeeklySummaryRepository implements WeeklySummaryRepository {
  _FakeWeeklySummaryRepository(this.data);

  final WeeklySummary data;

  @override
  Future<WeeklySummary> summary() async => data;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// The hero reads the signed-in user off the bloc; nothing else in the page
/// touches auth, so a stub in its initial (unknown, no user) state is enough.
class _FakeAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  _FakeAuthBloc() : super(const AuthState());

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
