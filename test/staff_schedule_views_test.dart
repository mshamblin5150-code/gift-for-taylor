import 'package:schedule_rules_testing/schedule_rules_testing.dart';
import 'package:er_schedule/schedule/month_grid_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'support/app_dependencies.dart';
import 'support/repair.dart';

void main() {
  const section = ScheduleSection(id: 'nurses', name: 'Nurses');
  const rows = [
    ScheduleRow(staffMemberId: 'me', displayName: 'Me', sectionId: 'nurses'),
    ScheduleRow(
      staffMemberId: 'night',
      displayName: 'Night RN',
      sectionId: 'nurses',
    ),
    ScheduleRow(
      staffMemberId: 'day',
      displayName: 'Day RN',
      sectionId: 'nurses',
    ),
    ScheduleRow(
      staffMemberId: 'off',
      displayName: 'Off RN',
      sectionId: 'nurses',
    ),
  ];
  final month = DateTime(2026, 9);
  final friday = DateTime(2026, 9, 18);
  final saturday = DateTime(2026, 9, 19);
  late InMemoryScheduleDatabase database;

  setUp(() async {
    database = InMemoryScheduleDatabase(
      sections: const [section],
      rows: rows,
      grants: {'manager': Grants(manager: true)},
      releasedMonths: {month},
    );
    final manager = scheduleRulesInMemory(database, actingAs: 'manager');
    for (final (code, start, end) in [
      ('7P', '19:00', '07:00'),
      ('N', '23:00', '07:00'),
      ('D', '07:00', '15:00'),
    ]) {
      await manager.store.saveShiftCode(
        LegendCode(code, startTime: start, endTime: end, isWorking: true),
      );
    }
    for (final (id, date, code) in [
      ('me', friday, '7P'),
      ('night', friday, 'N'),
      ('day', friday, 'D'),
      ('off', friday, 'X'),
      ('me', saturday, 'X'),
    ]) {
      await manager.saveCell(
        SaveCell(
          staffMemberId: id,
          sectionId: section.id,
          date: date,
          shiftCode: code,
        ),
      );
    }
    database.markAllAnnounced();
  });

  Future<void> pumpSchedule(
    WidgetTester tester, {
    required String actingAs,
    String? staffMemberId,
    String? swapStaffMemberId,
  }) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MonthGridPage(
          swapStore: emptySwapStore(actingAs),
          giveawayStore: emptyGiveawayStore(actingAs),
          noticeGateway: const NoopNoticeGateway(),
          repairController: noopRepairController(),
          undeliveredInvitationLog: FakeUndeliveredInvitationLog(),
          access: database.accessFor(actingAs),
          rules: scheduleRulesInMemory(database, actingAs: actingAs),
          month: month,
          staffMemberId: staffMemberId,
          swapStaffMemberId: swapStaffMemberId,
          now: () => friday,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Staff Day lists only colleagues with overlapping timed shifts', (
    tester,
  ) async {
    await pumpSchedule(tester, actingAs: 'me', staffMemberId: 'me');
    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();

    expect(find.text('Night RN'), findsOneWidget);
    expect(find.textContaining('N (11P–7A)'), findsOneWidget);
    expect(find.textContaining('8 hours together'), findsOneWidget);
    expect(find.text('Day RN'), findsNothing);
    expect(find.text('Off RN'), findsNothing);
  });

  testWidgets('Staff Day says when they are not working', (tester) async {
    await pumpSchedule(tester, actingAs: 'me', staffMemberId: 'me');
    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next day'));
    await tester.pumpAndSettle();

    expect(find.text('You are not working'), findsOneWidget);
    expect(find.text('Night RN'), findsNothing);
  });

  testWidgets('Night scheduler gets Staff Day and their own Person days', (
    tester,
  ) async {
    await pumpSchedule(tester, actingAs: 'me', swapStaffMemberId: 'me');
    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();

    expect(find.text('Night RN'), findsOneWidget);
    expect(find.text('Day RN'), findsNothing);

    await tester.tap(find.text('Person'));
    await tester.pumpAndSettle();
    expect(find.text('Fri 18'), findsOneWidget);
    expect(find.text('Sat 19'), findsNothing);
  });

  testWidgets('Staff Person lists working days and keeps changed highlight', (
    tester,
  ) async {
    await pumpSchedule(tester, actingAs: 'me', staffMemberId: 'me');
    await tester.scrollUntilVisible(find.text('Fri 18'), 400);

    expect(find.text('Fri 18'), findsOneWidget);
    expect(find.text('Sat 19'), findsNothing);
    expect(find.byKey(const ValueKey('changed-me-2026-09-18')), findsOneWidget);
  });

  testWidgets('Manager Day and Person retain full Schedule', (tester) async {
    await pumpSchedule(tester, actingAs: 'manager');
    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();

    expect(find.text('Day RN'), findsOneWidget);
    expect(find.text('Off RN'), findsOneWidget);
    expect(find.text('Nurses'), findsOneWidget);

    await tester.tap(find.text('Person'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Fri 18'), 400);
    expect(find.text('Fri 18'), findsOneWidget);
    expect(find.text('Sat 19'), findsOneWidget);
  });
}
