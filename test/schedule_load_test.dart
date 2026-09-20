import 'package:er_schedule/schedule/month_grid_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

/// The Schedule opens on several backend calls, but only the grid and the
/// unannounced tray are the Schedule. Section staffing is an adjunct, and an
/// app deployed ahead of its database is how it goes missing.
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
    await pumpGrid(tester, openShiftRules: OpenShiftRules(_NoStaffingStore()));

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

/// A database that has not learned about staffing minimums yet.
final class _NoStaffingStore implements OpenShiftStore {
  @override
  Future<List<SectionStaffing>> staffingForMonth(DateTime month) =>
      throw StateError(
        'Could not find the function public.section_staffing_for_month',
      );

  @override
  Stream<void> updates() => const Stream<void>.empty();

  @override
  Future<List<OpenShift>> openShifts() => throw UnimplementedError();

  @override
  Future<List<OpenShiftPickup>> pickups() => throw UnimplementedError();

  @override
  Future<void> requestPickup(String openShiftId) => throw UnimplementedError();

  @override
  Future<void> approvePickup(String pickupId) => throw UnimplementedError();

  @override
  Future<void> setWeekdayMinimum(String sectionId, int weekday, int minimum) =>
      throw UnimplementedError();

  @override
  Future<void> setDateMinimum(String sectionId, DateTime date, int? minimum) =>
      throw UnimplementedError();

  @override
  Future<int> postOpenShifts(
    String sectionId,
    DateTime date,
    String shiftCode,
    JobRole jobRole,
    int count, {
    bool fillGap = false,
  }) => throw UnimplementedError();
}
