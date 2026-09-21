import 'package:schedule_rules_testing/schedule_rules_testing.dart';
import 'package:er_schedule/schedule/month_grid_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

void main() {
  const days = ScheduleSection(id: 'days', name: 'State dayshift RN');
  const nights = ScheduleSection(id: 'nights', name: 'PRN nightshift RN');
  const dayNurse = ScheduleRow(
    staffMemberId: 'rn-1',
    displayName: 'Day RN',
    sectionId: 'days',
  );
  const nightNurse = ScheduleRow(
    staffMemberId: 'rn-2',
    displayName: 'Night RN',
    sectionId: 'nights',
  );
  const chargeNurse = ScheduleRow(
    staffMemberId: 'rn-3',
    displayName: 'Charge RN',
    sectionId: 'nights',
  );
  final september = DateTime(2026, 9);
  final september18 = DateTime(2026, 9, 18);

  late DateTime now;
  late InMemoryScheduleDatabase database;
  late ScheduleRules manager;

  setUp(() {
    now = DateTime(2026, 9, 18, 21);
    database = InMemoryScheduleDatabase(
      sections: const [days, nights],
      rows: const [dayNurse, nightNurse, chargeNurse],
      editors: const {'manager'},
      names: const {'manager': 'The Manager'},
      releasedMonths: {september},
      clock: () => now,
    );
    manager = scheduleRulesInMemory(database, actingAs: 'manager');
  });

  Future<void> pumpGrid(
    WidgetTester tester, {
    required String actingAs,
    DateTime? month,
  }) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MonthGridPage(
          access: database.accessFor(actingAs),
          rules: scheduleRulesInMemory(database, actingAs: actingAs),
          month: month ?? september,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder cell(String staffMemberId, DateTime date) => find.byKey(
    ValueKey('cell-$staffMemberId-${date.toIso8601String().substring(0, 10)}'),
  );

  Future<void> save(ScheduleRules rules, ScheduleRow row, String code) {
    return rules.saveCell(
      SaveCell(
        staffMemberId: row.staffMemberId,
        sectionId: row.sectionId,
        date: september18,
        shiftCode: code,
      ),
    );
  }

  testWidgets('the Night scheduler edits only assigned Sections', (
    tester,
  ) async {
    await manager.store.assignNightScheduler('rn-3', {'nights'});
    await pumpGrid(tester, actingAs: 'rn-3');

    expect(find.byTooltip('Night scheduler'), findsNothing);
    await tester.tap(find.byTooltip('More destinations'));
    await tester.pumpAndSettle();
    expect(find.text('Change log'), findsOneWidget);
    await tester.tap(find.text('Change log'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(cell('rn-1', september18));
    await tester.pumpAndSettle();
    expect(find.text('Other Shift code'), findsNothing);

    await tester.tap(cell('rn-2', september18));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '7P'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: cell('rn-2', september18), matching: find.text('7P')),
      findsOneWidget,
    );
  });

  testWidgets(
    'the Night scheduler drafts assigned Sections before Month release',
    (tester) async {
      await manager.store.assignNightScheduler('rn-3', {'nights'});
      final october = DateTime(2026, 10);
      await manager.startEmptyMonth(october);
      final october16 = DateTime(2026, 10, 16);
      await pumpGrid(tester, actingAs: 'rn-3', month: october);

      expect(find.textContaining("hasn't been released"), findsNothing);
      expect(cell('rn-2', october16), findsOneWidget);
      expect(find.text('Release month'), findsNothing);
      expect(find.text('Start from September'), findsNothing);
      expect(find.text('Start empty month'), findsNothing);

      await tester.tap(cell('rn-1', october16));
      await tester.pumpAndSettle();
      expect(find.text('Other Shift code'), findsNothing);

      await tester.tap(cell('rn-2', october16));
      await tester.pumpAndSettle();
      expect(find.text('Other Shift code'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '7P');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: cell('rn-2', october16), matching: find.text('7P')),
        findsOneWidget,
      );

      await tester.tap(find.text('Person'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Night RN').last);
      await tester.pumpAndSettle();
      expect(find.text('Sat 17'), findsOneWidget);
    },
  );

  testWidgets('the Manager filters the change log by person', (tester) async {
    await manager.store.assignNightScheduler('rn-3', {'nights'});
    await save(manager, dayNurse, '7A');
    await save(
      scheduleRulesInMemory(database, actingAs: 'rn-3'),
      nightNurse,
      'N',
    );
    await pumpGrid(tester, actingAs: 'manager');

    await tester.tap(find.byTooltip('More destinations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change log'));
    await tester.pumpAndSettle();

    expect(find.text('Day RN · Fri 18: blank → 7A'), findsOneWidget);
    expect(find.text('Night RN · Fri 18: blank → N'), findsOneWidget);
    expect(find.textContaining('Charge RN · Sep 18'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Charge RN').last);
    await tester.pumpAndSettle();

    expect(find.text('Day RN · Fri 18: blank → 7A'), findsNothing);
    expect(find.text('Night RN · Fri 18: blank → N'), findsOneWidget);
  });
}
