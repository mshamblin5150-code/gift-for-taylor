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
      clock: () => now,
    );
    manager = ScheduleRules.inMemory(database, actingAs: 'manager');
  });

  Future<void> pumpGrid(WidgetTester tester, {required String actingAs}) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MonthGridPage(
          rules: ScheduleRules.inMemory(database, actingAs: actingAs),
          month: september,
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

  testWidgets('the Manager gives the Night scheduler role with Sections', (
    tester,
  ) async {
    await pumpGrid(tester, actingAs: 'manager');

    await tester.tap(find.byTooltip('Night scheduler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Give the role'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Charge RN').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckboxListTile, 'PRN nightshift RN'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Charge RN'), findsOneWidget);
    final scheduler = (await manager.nightSchedulers()).single;
    expect(scheduler.staffMemberId, 'rn-3');
    expect(scheduler.sectionIds, {'nights'});

    await tester.tap(find.byTooltip('Remove the role from Charge RN'));
    await tester.pumpAndSettle();

    expect(await manager.nightSchedulers(), isEmpty);
  });

  testWidgets('the Night scheduler edits only assigned Sections', (
    tester,
  ) async {
    await manager.assignNightScheduler('rn-3', {'nights'});
    await pumpGrid(tester, actingAs: 'rn-3');

    expect(find.byTooltip('Night scheduler'), findsNothing);
    expect(find.byTooltip('Change log'), findsNothing);

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

  testWidgets('the Manager filters the change log by person', (tester) async {
    await manager.assignNightScheduler('rn-3', {'nights'});
    await save(manager, dayNurse, '7A');
    await save(
      ScheduleRules.inMemory(database, actingAs: 'rn-3'),
      nightNurse,
      'N',
    );
    await pumpGrid(tester, actingAs: 'manager');

    await tester.tap(find.byTooltip('Change log'));
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
