import 'package:er_schedule/schedule/month_grid_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:schedule_rules_testing/schedule_rules_testing.dart';

import 'support/app_dependencies.dart';
import 'support/repair.dart';

void main() {
  const section = ScheduleSection(id: 'nurses', name: 'Nurses');
  const recorder = ScheduleRow(
    staffMemberId: 'recorder',
    displayName: 'Recorder RN',
    sectionId: 'nurses',
  );
  const colleague = ScheduleRow(
    staffMemberId: 'colleague',
    displayName: 'Colleague RN',
    sectionId: 'nurses',
  );
  final month = DateTime(2026, 9);
  final day = DateTime(2026, 9, 18);
  late InMemoryScheduleDatabase database;

  Future<void> seedDatabase({Map<String, Grants> grants = const {}}) async {
    database = InMemoryScheduleDatabase(
      sections: const [section],
      rows: const [recorder, colleague],
      grants: grants,
      releasedMonths: {month},
    );
    database.seedOnFloorNow('recorder', true);
    final manager = scheduleRulesInMemory(database, actingAs: 'manager');
    await manager.store.saveShiftCode(
      const LegendCode(
        '7A',
        hours: '7A–7P',
        startTime: '07:00',
        endTime: '19:00',
        isWorking: true,
      ),
    );
    for (final id in ['recorder', 'colleague']) {
      await manager.saveCell(
        SaveCell(
          staffMemberId: id,
          sectionId: section.id,
          date: day,
          shiftCode: '7A',
        ),
      );
    }
    database.markAllAnnounced();
  }

  setUp(seedDatabase);

  Future<void> pumpSchedule(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MonthGridPage(
          swapStore: emptySwapStore('recorder'),
          giveawayStore: emptyGiveawayStore('recorder'),
          staffGateway: emptyStaffGateway(),
          rules: scheduleRulesInMemory(database, actingAs: 'recorder'),
          access: database.accessFor('recorder'),
          month: month,
          staffMemberId: 'recorder',
          noticeGateway: const NoopNoticeGateway(),
          repairController: noopRepairController(),
          undeliveredInvitationLog: FakeUndeliveredInvitationLog(),
          now: () => day,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openMonthCell(WidgetTester tester) async {
    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cell-colleague-2026-09-18')));
    await tester.pumpAndSettle();
  }

  testWidgets('on-floor Staff records a colleague Call-in from the Month', (
    tester,
  ) async {
    database.seedCallInPostedCount(2);
    await pumpSchedule(tester);
    await openMonthCell(tester);

    expect(find.text('Colleague RN'), findsWidgets);
    expect(find.text('Friday, September 18'), findsOneWidget);
    expect(find.text('Shift: 7A'), findsOneWidget);
    await tester.tap(find.text('Record a Call-in'));
    await tester.pumpAndSettle();

    expect(find.text('C/I'), findsWidgets);
    expect(
      find.text('Call-in recorded. 2 Open shifts were posted.'),
      findsOneWidget,
    );
  });

  testWidgets('off-floor Staff sees why recording is unavailable', (
    tester,
  ) async {
    database.seedOnFloorNow('recorder', false);
    await pumpSchedule(tester);
    await openMonthCell(tester);

    expect(
      find.text('You must be working now to record a Call-in.'),
      findsOneWidget,
    );
    expect(find.text('Record a Call-in'), findsNothing);
  });

  testWidgets('a non-working target cell opens and names the reason', (
    tester,
  ) async {
    await scheduleRulesInMemory(database, actingAs: 'manager').saveCell(
      SaveCell(
        staffMemberId: 'colleague',
        sectionId: section.id,
        date: day,
        shiftCode: 'X',
      ),
    );
    await pumpSchedule(tester);
    await openMonthCell(tester);

    expect(
      find.text('This cell has no working Shift to call in from.'),
      findsOneWidget,
    );
    expect(
      find.text('There are no actions available for this cell.'),
      findsOneWidget,
    );
  });

  testWidgets('a withdrawable Call-in restores its previous Shift', (
    tester,
  ) async {
    await database.storeFor('recorder').recordCallIn('colleague', day);
    await pumpSchedule(tester);
    await openMonthCell(tester);

    await tester.tap(find.text('Withdraw the Call-in'));
    await tester.pumpAndSettle();

    expect(find.text('7A'), findsWidgets);
    expect(
      find.text('Call-in withdrawn. The previous Shift was restored.'),
      findsOneWidget,
    );
  });

  testWidgets('a settled Call-in names why withdrawal is unavailable', (
    tester,
  ) async {
    await database.storeFor('recorder').recordCallIn('colleague', day);
    database.settleCallIn('colleague', day);
    await pumpSchedule(tester);
    await openMonthCell(tester);

    expect(
      find.text(
        'This Call-in is settled because an Open shift was filled, so it cannot be withdrawn.',
      ),
      findsOneWidget,
    );
    expect(find.text('Withdraw the Call-in'), findsNothing);
  });

  testWidgets('a zero-gap Call-in says why no Open shift was posted', (
    tester,
  ) async {
    await pumpSchedule(tester);
    await openMonthCell(tester);
    await tester.tap(find.text('Record a Call-in'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Call-in recorded. The day still meets its minimum, so no Open shift was posted.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the Day colleague entry reaches the Staff cell sheet', (
    tester,
  ) async {
    await pumpSchedule(tester);
    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Colleague RN'));
    await tester.pumpAndSettle();

    expect(find.text('Record a Call-in'), findsOneWidget);
  });

  testWidgets(
    'a Night scheduler can use Staff actions outside their sections',
    (tester) async {
      await seedDatabase(
        grants: {
          'recorder': Grants(nightSchedulerSectionIds: {'other-section'}),
        },
      );
      await pumpSchedule(tester);
      await openMonthCell(tester);

      expect(find.text('Record a Call-in'), findsOneWidget);
    },
  );

  testWidgets('the Person entry reaches the Staff cell sheet', (tester) async {
    await pumpSchedule(tester);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Colleague RN').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fri 18'));
    await tester.pumpAndSettle();

    expect(find.text('Record a Call-in'), findsOneWidget);
  });
}
