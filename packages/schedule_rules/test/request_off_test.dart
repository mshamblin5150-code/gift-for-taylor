import 'package:schedule_rules_testing/schedule_rules_testing.dart';
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
    manager = scheduleRulesInMemory(database, actingAs: 'manager');
    staff = scheduleRulesInMemory(database, actingAs: 'staff');
    await manager.store.changeJobRole(
      ChangeJobRole(
        staffMemberId: 'staff',
        jobRole: JobRole.rn,
        from: DateTime(2026, 1),
      ),
    );
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
        (await manager.store.requestsOff(pendingOnly: true))
            .single
            .emailCopyConfirmed,
        isFalse,
      );
      expect(await manager.store.unreadRequestOffNotices(), 1);
      await manager.store.acknowledgeRequestOffNotices();
      expect(await manager.store.unreadRequestOffNotices(), 0);
      await staff.store.confirmRequestOffEmail(email.requestId);
      expect(
        (await manager.store.requestsOff(pendingOnly: true))
            .single
            .emailCopyConfirmed,
        isTrue,
      );
      expect(
        (await staff.store.requestsOff(pendingOnly: false)).single.submittedAt,
        now,
      );
    },
  );

  test(
    'approval writes R/O, marks a scheduled day short, and keeps history',
    () async {
      final email = await staff.requestOff(RequestOffDraft(dates: [day, next]));
      now = DateTime(2026, 9, 20, 11);
      await manager.store.decideRequestOff(
        email.requestId,
        RequestOffDecision.approved,
        'Okay',
      );
      final grid = await manager.monthGrid(DateTime(2026, 10));
      expect(grid.shiftCodeFor('staff', day), 'R/O');
      expect(grid.shiftCodeFor('staff', next), 'R/O');
      expect(
        grid
            .shortShiftsOn(CoveragePool.nurses, CoverageWindow.day, day)
            .single
            .shiftCode,
        '7A',
      );
      expect(
        grid.shortShiftsOn(CoveragePool.nurses, CoverageWindow.day, next),
        isEmpty,
      );
      expect(
        (await manager.changeLog(DateTime(2026, 10))).last.newShiftCode,
        'R/O',
      );
      expect(await manager.store.requestsOff(pendingOnly: true), isEmpty);
      final history = (await staff.store.requestsOff(pendingOnly: false))
          .single;
      expect(history.decision, RequestOffDecision.approved);
      expect(history.decisionReason, 'Okay');
      expect(history.decidedAt, now);
      expect(await staff.store.unreadRequestOffNotices(), 1);
    },
  );

  test('decline preserves the Schedule and records the reason', () async {
    final email = await staff.requestOff(RequestOffDraft(dates: [day]));
    await manager.store.decideRequestOff(
      email.requestId,
      RequestOffDecision.declined,
      'Coverage',
    );
    expect(
      (await manager.monthGrid(DateTime(2026, 10))).shiftCodeFor('staff', day),
      '7A',
    );
    expect(
      (await staff.store.requestsOff(pendingOnly: false)).single.decisionReason,
      'Coverage',
    );
    await expectLater(
      manager.store.decideRequestOff(
        email.requestId,
        RequestOffDecision.approved,
        null,
      ),
      throwsStateError,
    );
  });

  test('Staff cannot decide and only the requester confirms email', () async {
    final email = await staff.requestOff(RequestOffDraft(dates: [day]));
    await expectLater(
      staff.store.decideRequestOff(
        email.requestId,
        RequestOffDecision.approved,
        null,
      ),
      throwsA(isA<ScheduleEditRefused>()),
    );
    await expectLater(
      manager.store.confirmRequestOffEmail(email.requestId),
      throwsStateError,
    );
  });
}
