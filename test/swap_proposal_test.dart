import 'package:er_schedule/schedule/messages_composer.dart';
import 'package:er_schedule/schedule/month_grid_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:schedule_rules_testing/schedule_rules_testing.dart';

import 'support/app_dependencies.dart';
import 'support/repair.dart';

void main() {
  const section = ScheduleSection(id: 'nurses', name: 'Nurses');
  const requester = ScheduleRow(
    staffMemberId: 'requester',
    displayName: 'Requester RN',
    sectionId: 'nurses',
    cellNumber: '5551112222',
    hasAcceptedInvite: true,
  );
  const colleague = ScheduleRow(
    staffMemberId: 'colleague',
    displayName: 'Colleague RN',
    sectionId: 'nurses',
    hasAcceptedInvite: true,
  );
  final month = DateTime(2026, 9);
  final now = DateTime(2026, 9, 10, 8);
  final requesterDay = DateTime(2026, 9, 11);
  final colleagueDay = DateTime(2026, 9, 14);

  late InMemoryScheduleDatabase schedule;
  late InMemorySwapDatabase swaps;
  late _RecordingMessagesComposer messages;

  Future<void> seedFixture({
    ScheduleRow colleagueRow = colleague,
    bool released = true,
    bool nightScheduler = false,
    bool managerAccount = false,
  }) async {
    schedule = InMemoryScheduleDatabase(
      sections: const [section],
      rows: [requester, colleagueRow],
      grants: {
        if (!released) 'requester': Grants(administrator: true),
        if (nightScheduler)
          'requester': Grants(nightSchedulerSectionIds: {'nurses'}),
        if (managerAccount) 'requester': Grants(manager: true),
      },
      releasedMonths: released ? {month} : const {},
    );
    final manager = scheduleRulesInMemory(schedule, actingAs: 'manager');
    await manager.store.saveShiftCode(
      const LegendCode('7A', hours: '7A–7P', isWorking: true),
    );
    await manager.store.saveShiftCode(
      const LegendCode('7P', hours: '7P–7A', isWorking: true),
    );
    await manager.saveCell(
      SaveCell(
        staffMemberId: requester.staffMemberId,
        sectionId: section.id,
        date: requesterDay,
        shiftCode: '7A',
      ),
    );
    await manager.saveCell(
      SaveCell(
        staffMemberId: colleague.staffMemberId,
        sectionId: section.id,
        date: colleagueDay,
        shiftCode: '7P',
      ),
    );
    schedule.markAllAnnounced();
    swaps = InMemorySwapDatabase(
      shifts: {
        (requester.staffMemberId, requesterDay): '7A',
        (colleague.staffMemberId, colleagueDay): '7P',
      },
      cellNumbers: {colleague.staffMemberId: '5553334444'},
    );
    messages = _RecordingMessagesComposer();
  }

  setUp(seedFixture);

  Future<void> pumpSchedule(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MonthGridPage(
          rules: scheduleRulesInMemory(schedule, actingAs: 'requester'),
          access: schedule.accessFor('requester'),
          month: month,
          staffMemberId: 'requester',
          swapStaffMemberId: 'requester',
          swapStore: swaps.storeFor('requester'),
          giveawayStore: emptyGiveawayStore('requester'),
          messagesComposer: messages,
          noticeGateway: const NoopNoticeGateway(),
          repairController: noopRepairController(),
          undeliveredInvitationLog: FakeUndeliveredInvitationLog(),
          now: () => now,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpManagerSchedule(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MonthGridPage(
          rules: scheduleRulesInMemory(schedule, actingAs: 'requester'),
          access: schedule.accessFor('requester'),
          month: month,
          swapStore: swaps.storeFor('requester'),
          giveawayStore: emptyGiveawayStore('requester'),
          noticeGateway: const NoopNoticeGateway(),
          repairController: noopRepairController(),
          undeliveredInvitationLog: FakeUndeliveredInvitationLog(),
          now: () => now,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openColleagueCell(WidgetTester tester) async {
    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cell-colleague-2026-09-14')));
    await tester.pumpAndSettle();
  }

  Future<void> openRequesterCell(WidgetTester tester) async {
    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cell-requester-2026-09-11')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Staff proposes a Swap from a colleague working cell with their shift fixed',
    (tester) async {
      await pumpSchedule(tester);
      await openColleagueCell(tester);

      await tester.tap(find.text('Propose a Swap'));
      await tester.pumpAndSettle();

      expect(find.text('Colleague RN'), findsWidgets);
      expect(find.text('Sep 14 — 7P'), findsOneWidget);
      expect(find.text('Choose my shift'), findsOneWidget);

      await tester.tap(find.text('Choose my shift'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sep 11 — 7A'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Propose'));
      await tester.pumpAndSettle();

      final proposed = (await swaps.storeFor('requester').swaps()).single;
      expect(proposed.colleagueId, 'colleague');
      expect(proposed.requesterShifts.single.date, requesterDay);
      expect(proposed.colleagueShifts.single.date, colleagueDay);
      expect(messages.numbers, ['5553334444']);
      expect(
        messages.body,
        'Hi Colleague RN, can we Swap my Sep 11 7A for your Sep 14 7P? '
        'Please answer in the ER Schedule app.',
      );
    },
  );

  testWidgets('Night scheduler can choose either editing or proposing a Swap', (
    tester,
  ) async {
    await seedFixture(nightScheduler: true);
    await pumpSchedule(tester);
    await openColleagueCell(tester);

    expect(find.text('Edit Shift'), findsOneWidget);
    expect(find.text('Propose a Swap'), findsOneWidget);

    await tester.tap(find.text('Propose a Swap'));
    await tester.pumpAndSettle();
    expect(find.text('Choose my shift'), findsOneWidget);
    expect(find.text('Sep 14 — 7P'), findsOneWidget);
  });

  testWidgets('a multi-day Swap accumulates from a colleague cell', (
    tester,
  ) async {
    final requesterDayTwo = DateTime(2026, 9, 12);
    final colleagueDayTwo = DateTime(2026, 9, 15);
    final manager = scheduleRulesInMemory(schedule, actingAs: 'manager');
    await manager.saveCell(
      SaveCell(
        staffMemberId: requester.staffMemberId,
        sectionId: section.id,
        date: requesterDayTwo,
        shiftCode: '7A',
      ),
    );
    await manager.saveCell(
      SaveCell(
        staffMemberId: colleague.staffMemberId,
        sectionId: section.id,
        date: colleagueDayTwo,
        shiftCode: '7P',
      ),
    );
    schedule.markAllAnnounced();
    swaps = InMemorySwapDatabase(
      shifts: {
        (requester.staffMemberId, requesterDay): '7A',
        (requester.staffMemberId, requesterDayTwo): '7A',
        (colleague.staffMemberId, colleagueDay): '7P',
        (colleague.staffMemberId, colleagueDayTwo): '7P',
      },
    );

    await pumpSchedule(tester);
    await openColleagueCell(tester);
    await tester.tap(find.text('Propose a Swap'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose my shift'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sep 11 — 7A'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(TextButton, 'Add another shift').first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sep 12 — 7A'));
    await tester.pumpAndSettle();

    expect(find.text("Pick 1 more of Colleague RN's shift."), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Add another shift').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sep 15 — 7P'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Propose'));
    await tester.pumpAndSettle();

    final proposed = (await swaps.storeFor('requester').swaps()).single;
    expect(proposed.requesterShifts.map((shift) => shift.date), [
      requesterDay,
      requesterDayTwo,
    ]);
    expect(proposed.colleagueShifts.map((shift) => shift.date), [
      colleagueDay,
      colleagueDayTwo,
    ]);
  });

  testWidgets(
    'a multi-day Swap can start from the requester own working cell',
    (tester) async {
      final requesterDayTwo = DateTime(2026, 9, 13);
      final colleagueDayTwo = DateTime(2026, 9, 15);
      final manager = scheduleRulesInMemory(schedule, actingAs: 'manager');
      await manager.saveCell(
        SaveCell(
          staffMemberId: requester.staffMemberId,
          sectionId: section.id,
          date: requesterDayTwo,
          shiftCode: '7A',
        ),
      );
      await manager.saveCell(
        SaveCell(
          staffMemberId: colleague.staffMemberId,
          sectionId: section.id,
          date: colleagueDayTwo,
          shiftCode: '7P',
        ),
      );
      schedule.markAllAnnounced();
      swaps = InMemorySwapDatabase(
        shifts: {
          (requester.staffMemberId, requesterDay): '7A',
          (requester.staffMemberId, requesterDayTwo): '7A',
          (colleague.staffMemberId, colleagueDay): '7P',
          (colleague.staffMemberId, colleagueDayTwo): '7P',
        },
        cellNumbers: {colleague.staffMemberId: '5553334444'},
      );

      await pumpSchedule(tester);
      await openRequesterCell(tester);
      await tester.tap(find.text('Swap these'));
      await tester.pumpAndSettle();

      expect(find.text('Sep 11 — 7A'), findsOneWidget);
      expect(find.text('Colleague RN'), findsWidgets);
      await tester.tap(
        find.widgetWithText(TextButton, 'Add another shift').first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Already selected'), findsOneWidget);
      await tester.tap(find.text('Sep 13 — 7A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Choose Colleague RN's shift"));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sep 14 — 7P'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(TextButton, 'Add another shift').last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sep 15 — 7P'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Propose'));
      await tester.pumpAndSettle();

      final proposed = (await swaps.storeFor('requester').swaps()).single;
      expect(proposed.requesterShifts.map((shift) => shift.date), [
        requesterDay,
        requesterDayTwo,
      ]);
      expect(proposed.colleagueShifts.map((shift) => shift.date), [
        colleagueDay,
        colleagueDayTwo,
      ]);
      expect(
        messages.body,
        'Hi Colleague RN, can we Swap my Sep 11 and 13 7A for your '
        'Sep 14–15 7P? Please answer in the ER Schedule app.',
      );
    },
  );

  testWidgets('own-cell entry discloses when no colleague can take the set', (
    tester,
  ) async {
    await scheduleRulesInMemory(schedule, actingAs: 'manager').saveCell(
      SaveCell(
        staffMemberId: colleague.staffMemberId,
        sectionId: section.id,
        date: requesterDay,
        shiftCode: '7P',
      ),
    );
    schedule.markAllAnnounced();

    await pumpSchedule(tester);
    await openRequesterCell(tester);
    await tester.tap(find.text('Swap these'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No one colleague can take all these days. This would need two separate Swaps, and either can be declined on its own.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Manager-linked Staff edits without a Swap proposal action', (
    tester,
  ) async {
    await seedFixture(managerAccount: true);
    await pumpManagerSchedule(tester);

    await tester.tap(find.byKey(const ValueKey('cell-colleague-2026-09-14')));
    await tester.pumpAndSettle();

    expect(find.text('Other Shift code'), findsOneWidget);
    expect(find.text('Propose a Swap'), findsNothing);
  });

  testWidgets('a non-working colleague cell names why Swap is unavailable', (
    tester,
  ) async {
    await scheduleRulesInMemory(schedule, actingAs: 'manager').saveCell(
      SaveCell(
        staffMemberId: colleague.staffMemberId,
        sectionId: section.id,
        date: colleagueDay,
        shiftCode: 'X',
      ),
    );

    await pumpSchedule(tester);
    await openColleagueCell(tester);

    expect(
      find.text('This day is not a working Shift for Colleague RN.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Propose a Swap'), findsNothing);
  });

  testWidgets('a colleague not in the app names why Swap is unavailable', (
    tester,
  ) async {
    await seedFixture(
      colleagueRow: const ScheduleRow(
        staffMemberId: 'colleague',
        displayName: 'Colleague RN',
        sectionId: 'nurses',
        cellNumber: '5553334444',
      ),
    );

    await pumpSchedule(tester);
    await openColleagueCell(tester);

    expect(find.text('Colleague RN is not in the app yet.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Propose a Swap'), findsNothing);
  });

  testWidgets('an unreleased month names why Swap is unavailable', (
    tester,
  ) async {
    await seedFixture(released: false);

    await pumpSchedule(tester);
    await openColleagueCell(tester);

    expect(find.text('This Schedule month is not released.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Propose a Swap'), findsNothing);
  });

  testWidgets('the offered working shift can come from another month', (
    tester,
  ) async {
    final october = DateTime(2026, 10);
    final octoberDay = DateTime(2026, 10, 2);
    schedule = InMemoryScheduleDatabase(
      sections: const [section],
      rows: const [requester, colleague],
      releasedMonths: {month, october},
    );
    final manager = scheduleRulesInMemory(schedule, actingAs: 'manager');
    await manager.store.saveShiftCode(
      const LegendCode('7A', hours: '7A–7P', isWorking: true),
    );
    await manager.store.saveShiftCode(
      const LegendCode('7P', hours: '7P–7A', isWorking: true),
    );
    await manager.saveCell(
      SaveCell(
        staffMemberId: requester.staffMemberId,
        sectionId: section.id,
        date: octoberDay,
        shiftCode: '7A',
      ),
    );
    await manager.saveCell(
      SaveCell(
        staffMemberId: colleague.staffMemberId,
        sectionId: section.id,
        date: colleagueDay,
        shiftCode: '7P',
      ),
    );
    schedule.markAllAnnounced();
    swaps = InMemorySwapDatabase(
      shifts: {
        (requester.staffMemberId, octoberDay): '7A',
        (colleague.staffMemberId, colleagueDay): '7P',
      },
      cellNumbers: {colleague.staffMemberId: '5553334444'},
    );

    await pumpSchedule(tester);
    await openColleagueCell(tester);
    await tester.tap(find.text('Propose a Swap'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose my shift'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog).last,
        matching: find.byTooltip('Next month'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oct 2 — 7A'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Propose'));
    await tester.pumpAndSettle();

    final proposed = (await swaps.storeFor('requester').swaps()).single;
    expect(proposed.requesterShifts.single.date, octoberDay);
    expect(proposed.colleagueShifts.single.date, colleagueDay);
  });
}

final class _RecordingMessagesComposer implements MessagesComposer {
  List<String>? numbers;
  String? body;

  @override
  Future<void> open(List<String> cellNumbers, String message) async {
    numbers = cellNumbers;
    body = message;
  }
}
