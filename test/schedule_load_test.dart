import 'package:er_schedule/schedule/month_grid_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

/// The grid is required; Shift codes and Section staffing are adjunct reads.
void main() {
  const days = ScheduleSection(id: 'days', name: 'State dayshift RN');
  const dayNurse = ScheduleRow(
    staffMemberId: 'rn-1',
    displayName: 'Day RN',
    sectionId: 'days',
  );
  final september = DateTime(2026, 9);

  late InMemoryScheduleDatabase database;

  setUp(() {
    database = InMemoryScheduleDatabase(
      sections: const [days],
      rows: const [dayNurse],
      editors: const {'manager'},
      releasedMonths: {september},
    );
  });

  Future<void> pumpGrid(
    WidgetTester tester, {
    OpenShiftRules? openShiftRules,
  }) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MonthGridPage(
          rules: ScheduleRules.inMemory(database, actingAs: 'manager'),
          month: september,
          openShiftRules: openShiftRules,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Section staffing being unavailable still opens the month', (
    tester,
  ) async {
    database.failNext(
      InMemoryStoreCall.staffingForMonth,
      StateError('Could not find public.section_staffing_for_month'),
    );
    await pumpGrid(
      tester,
      openShiftRules: OpenShiftRules(database.openShiftStoreFor('manager')),
    );

    expect(find.text("The Schedule couldn't be loaded."), findsNothing);
    expect(find.text('Day RN'), findsOneWidget);
    expect(find.text('State dayshift RN'), findsOneWidget);
  });

  testWidgets('Shift codes being unavailable still opens the month', (
    tester,
  ) async {
    database.failNext(
      InMemoryStoreCall.shiftCodes,
      StateError('Could not find public.shift_codes'),
    );
    await pumpGrid(tester);

    expect(find.text("The Schedule couldn't be loaded."), findsNothing);
    expect(find.text('Day RN'), findsOneWidget);
    expect(find.text('State dayshift RN'), findsOneWidget);
  });

  testWidgets('a failed month read shows the reason and can be retried', (
    tester,
  ) async {
    database.failNext(
      InMemoryStoreCall.sections,
      StateError('Could not read Schedule sections'),
    );
    await pumpGrid(tester);

    expect(find.text("The Schedule couldn't be loaded."), findsOneWidget);
    expect(
      find.textContaining('Could not read Schedule sections'),
      findsOneWidget,
    );
    expect(find.text('Day RN'), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text("The Schedule couldn't be loaded."), findsNothing);
    expect(find.text('Day RN'), findsOneWidget);
    expect(find.text('State dayshift RN'), findsOneWidget);
  });

  testWidgets('a Schedule with no staffing minimums reads the same', (
    tester,
  ) async {
    await pumpGrid(tester);

    expect(find.text("The Schedule couldn't be loaded."), findsNothing);
    expect(find.text('Day RN'), findsOneWidget);
  });
}
