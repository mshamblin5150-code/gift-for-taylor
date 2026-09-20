import 'package:er_schedule/schedule/month_grid_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const days = ScheduleSection(id: 'days', name: 'State dayshift RN');
  const nights = ScheduleSection(id: 'nights', name: 'PRN nightshift RN');
  const empty = ScheduleSection(id: 'empty', name: 'Unit clerks');
  final september = DateTime(2026, 9);
  final october = DateTime(2026, 10);
  late InMemoryScheduleDatabase database;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = InMemoryScheduleDatabase(
      sections: const [days, nights, empty],
      rows: const [
        ScheduleRow(
          staffMemberId: 'day',
          displayName: 'Day RN',
          sectionId: 'days',
        ),
        ScheduleRow(
          staffMemberId: 'night',
          displayName: 'Night RN',
          sectionId: 'nights',
        ),
      ],
      editors: const {'manager'},
      releasedMonths: {september, october},
    );
  });

  Future<void> pumpSchedule(
    WidgetTester tester, {
    String person = 'manager',
    DateTime? month,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MonthGridPage(
          key: ValueKey('$person-${month ?? september}'),
          rules: ScheduleRules.inMemory(database, actingAs: person),
          viewerId: person,
          month: month ?? september,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder band(String id) => find.byKey(ValueKey('section-name-$id'));
  Finder dayBand(String id) => find.byKey(ValueKey('section-days-$id'));
  Finder dayCell(String staffId) =>
      find.byKey(ValueKey('cell-$staffId-2026-09-01'));

  testWidgets('any viewer can fold rows while both bands stay aligned', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpSchedule(tester, person: 'day');
    expect(dayCell('day'), findsOneWidget);
    expect(dayCell('night'), findsOneWidget);
    expect(tester.getSize(band('days')).height, 48);
    final expanded = tester.getSemantics(band('days'));
    expect(expanded.label, 'State dayshift RN');
    expect(expanded.value, 'Expanded');
    expect(expanded.hint, 'Collapse Section');
    expect(expanded.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

    await tester.tap(band('days'));
    await tester.pumpAndSettle();

    expect(dayCell('day'), findsNothing);
    expect(find.text('Day RN'), findsNothing);
    expect(dayCell('night'), findsOneWidget);
    expect(band('days'), findsOneWidget);
    expect(dayBand('days'), findsOneWidget);
    final collapsed = tester.getSemantics(band('days'));
    expect(collapsed.value, 'Collapsed');
    expect(collapsed.hint, 'Expand Section');
    expect(
      tester.getTopLeft(band('days')).dy,
      tester.getTopLeft(dayBand('days')).dy,
    );
    expect(
      tester.getTopLeft(band('nights')).dy,
      tester.getTopLeft(dayBand('nights')).dy,
    );
    expect(
      tester.getTopLeft(band('nights')).dy,
      tester.getBottomLeft(band('days')).dy,
    );

    await tester.tap(band('days'));
    await tester.pumpAndSettle();
    expect(dayCell('day'), findsOneWidget);
    expect(
      tester.getTopLeft(band('nights')).dy,
      tester.getTopLeft(dayBand('nights')).dy,
    );
    semantics.dispose();
  });

  testWidgets('empty Section keeps its inert band without a triangle', (
    tester,
  ) async {
    await pumpSchedule(tester);
    expect(band('empty'), findsOneWidget);
    expect(dayBand('empty'), findsOneWidget);
    expect(
      find.descendant(of: band('empty'), matching: find.byType(Icon)),
      findsNothing,
    );
    await tester.tap(band('empty'));
    await tester.pumpAndSettle();
    expect(band('empty'), findsOneWidget);
  });

  testWidgets(
    'choice persists across months and restart for one account only',
    (tester) async {
      await pumpSchedule(tester);
      await tester.tap(band('days'));
      await tester.pumpAndSettle();
      expect(dayCell('day'), findsNothing);

      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('Day RN'), findsNothing);
      expect(band('days'), findsOneWidget);

      await pumpSchedule(tester, month: october);
      expect(find.text('Day RN'), findsNothing);
      await pumpSchedule(tester, person: 'day', month: october);
      expect(find.text('Day RN'), findsOneWidget);
      await pumpSchedule(tester);
      expect(dayCell('day'), findsNothing);
    },
  );

  testWidgets('an empty month does not forget a Section choice', (
    tester,
  ) async {
    await pumpSchedule(tester);
    await tester.tap(band('days'));
    await tester.pumpAndSettle();

    database = InMemoryScheduleDatabase(
      sections: const [days, nights, empty],
      rows: const [
        ScheduleRow(
          staffMemberId: 'night',
          displayName: 'Night RN',
          sectionId: 'nights',
        ),
      ],
      editors: const {'manager'},
      releasedMonths: {october},
    );
    await pumpSchedule(tester, month: october);
    expect(band('days'), findsOneWidget);
    expect(
      find.descendant(of: band('days'), matching: find.byType(Icon)),
      findsNothing,
    );

    database = InMemoryScheduleDatabase(
      sections: const [days, nights, empty],
      rows: const [
        ScheduleRow(
          staffMemberId: 'day',
          displayName: 'Day RN',
          sectionId: 'days',
        ),
      ],
      editors: const {'manager'},
      releasedMonths: {september},
    );
    await pumpSchedule(tester);
    expect(dayCell('day'), findsNothing);
  });

  testWidgets('rapid disclosure taps restore the latest choice', (
    tester,
  ) async {
    await pumpSchedule(tester);
    await tester.tap(band('days'));
    await tester.pump();
    await tester.tap(band('days'));
    await tester.pump();
    await tester.tap(band('days'));
    await tester.pump();

    await pumpSchedule(tester, month: october);
    expect(find.text('Day RN'), findsNothing);
  });
}
