import 'package:schedule_rules/schedule_rules.dart';
import 'package:test/test.dart';

void main() {
  final day = DateTime(2026, 10, 12);
  final next = DateTime(2026, 10, 13);
  late InMemoryScheduleDatabase database;
  late ScheduleRules manager;
  late ScheduleRules staff;
  late DateTime now;

  setUp(() async {
    now = DateTime(2026, 9, 19, 10);
    database = InMemoryScheduleDatabase(
      sections: const [ScheduleSection(id: 'rn', name: 'RN')],
      rows: const [
        ScheduleRow(
          staffMemberId: 'staff',
          displayName: 'Test Staff',
          sectionId: 'rn',
        ),
      ],
      names: const {'manager': 'Test Manager'},
      editors: const {'manager'},
      clock: () => now,
      releasedMonths: {DateTime(2026, 10)},
    );
    manager = ScheduleRules.inMemory(database, actingAs: 'manager');
    staff = ScheduleRules.inMemory(database, actingAs: 'staff');
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'staff',
        sectionId: 'rn',
        date: day,
        shiftCode: '7A',
      ),
    );
    database.markAllAnnounced();
  });

  test(
    'request opens an email draft and remains unconfirmed until Staff confirms',
    () async {
      final email = await staff.requestOff(
        RequestOffDraft(dates: [next, day, next], reason: 'Family event'),
      );
      expect(email.to, 'manager@example.test');
      expect(
        email.body,
        'Test Staff requests off on 2026-10-12, 2026-10-13.\nReason: Family event',
      );
      expect(
        (await manager.approvalQueue()).single.emailCopyConfirmed,
        isFalse,
      );
      expect(await manager.unreadRequestOffNotices(), 1);
      await manager.acknowledgeRequestOffNotices();
      expect(await manager.unreadRequestOffNotices(), 0);
      await staff.confirmRequestOffEmail(email.requestId);
      expect((await manager.approvalQueue()).single.emailCopyConfirmed, isTrue);
      expect((await staff.myRequestsOff()).single.submittedAt, now);
    },
  );

  test(
    'approval writes R/O, marks a scheduled day short, and keeps history',
    () async {
      final email = await staff.requestOff(RequestOffDraft(dates: [day, next]));
      now = DateTime(2026, 9, 20, 11);
      await manager.decideRequestOff(
        email.requestId,
        RequestOffDecision.approved,
        reason: 'Okay',
      );
      final grid = await manager.monthGrid(DateTime(2026, 10));
      expect(grid.shiftCodeFor('staff', day), 'R/O');
      expect(grid.shiftCodeFor('staff', next), 'R/O');
      expect(grid.shortShiftsOn('rn', day).single.shiftCode, '7A');
      expect(grid.shortShiftsOn('rn', next), isEmpty);
      expect(
        (await manager.changeLog(DateTime(2026, 10))).last.newShiftCode,
        'R/O',
      );
      expect(await manager.approvalQueue(), isEmpty);
      final history = (await staff.myRequestsOff()).single;
      expect(history.decision, RequestOffDecision.approved);
      expect(history.decisionReason, 'Okay');
      expect(history.decidedAt, now);
      expect(await staff.unreadRequestOffNotices(), 1);
    },
  );

  test('decline preserves the Schedule and records the reason', () async {
    final email = await staff.requestOff(RequestOffDraft(dates: [day]));
    await manager.decideRequestOff(
      email.requestId,
      RequestOffDecision.declined,
      reason: 'Coverage',
    );
    expect(
      (await manager.monthGrid(DateTime(2026, 10))).shiftCodeFor('staff', day),
      '7A',
    );
    expect((await staff.myRequestsOff()).single.decisionReason, 'Coverage');
    await expectLater(
      manager.decideRequestOff(email.requestId, RequestOffDecision.approved),
      throwsStateError,
    );
  });

  test('Staff cannot decide and only the requester confirms email', () async {
    final email = await staff.requestOff(RequestOffDraft(dates: [day]));
    await expectLater(
      staff.decideRequestOff(email.requestId, RequestOffDecision.approved),
      throwsA(isA<ScheduleEditRefused>()),
    );
    await expectLater(
      manager.confirmRequestOffEmail(email.requestId),
      throwsStateError,
    );
  });
}
