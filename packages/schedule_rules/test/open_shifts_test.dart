import 'package:schedule_rules/schedule_rules.dart';
import 'package:test/test.dart';

void main() {
  final day = DateTime(2026, 10, 12);
  late InMemoryScheduleDatabase database;
  late ScheduleRules manager;
  late OpenShiftRules managerShifts;

  setUp(() async {
    database = InMemoryScheduleDatabase(
      sections: const [
        ScheduleSection(id: 'nursing', name: 'Nursing'),
        ScheduleSection(id: 'other-nursing', name: 'Other nursing'),
        ScheduleSection(id: 'cna', name: 'CNA'),
        ScheduleSection(id: 'clerk', name: 'Unit clerks'),
      ],
      rows: const [
        ScheduleRow(
          staffMemberId: 'original',
          displayName: 'Original RN',
          sectionId: 'nursing',
        ),
        ScheduleRow(
          staffMemberId: 'lpn',
          displayName: 'LPN',
          sectionId: 'nursing',
        ),
        ScheduleRow(
          staffMemberId: 'other',
          displayName: 'Other RN',
          sectionId: 'nursing',
        ),
        ScheduleRow(staffMemberId: 'cna', displayName: 'CNA', sectionId: 'cna'),
        ScheduleRow(
          staffMemberId: 'clerk',
          displayName: 'Clerk',
          sectionId: 'clerk',
        ),
      ],
      editors: const {'manager'},
      releasedMonths: {DateTime(2026, 10)},
    );
    manager = ScheduleRules.inMemory(database, actingAs: 'manager');
    managerShifts = OpenShiftRules(database.openShiftStoreFor('manager'));
    for (final (id, role) in [
      ('original', JobRole.rn),
      ('lpn', JobRole.lpn),
      ('other', JobRole.rn),
      ('cna', JobRole.cna),
      ('clerk', JobRole.unitClerk),
    ]) {
      await manager.changeJobRole(
        ChangeJobRole(
          staffMemberId: id,
          jobRole: role,
          from: DateTime(2026, 1),
        ),
      );
    }
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'original',
        sectionId: 'nursing',
        date: day,
        shiftCode: '7A',
      ),
    );
    final request = await ScheduleRules.inMemory(
      database,
      actingAs: 'original',
    ).requestOff(RequestOffDraft(dates: [day]));
    await manager.decideRequestOff(
      request.requestId,
      RequestOffDecision.approved,
    );
  });

  test(
    'nurses share Open shifts; CNA and unit clerk do not see nursing shifts',
    () async {
      expect(
        await OpenShiftRules(database.openShiftStoreFor('lpn')).openShifts(),
        hasLength(1),
      );
      expect(
        await OpenShiftRules(database.openShiftStoreFor('cna')).openShifts(),
        isEmpty,
      );
      expect(
        await OpenShiftRules(database.openShiftStoreFor('clerk')).openShifts(),
        isEmpty,
      );
      expect((await managerShifts.openShifts()).single.shiftCode, '7A');
    },
  );

  test(
    'Manager can decline a pending pickup without filling its Open shift',
    () async {
      final shift = (await managerShifts.openShifts()).single;
      final staff = OpenShiftRules(database.openShiftStoreFor('lpn'));
      await staff.requestPickup(shift.id);
      final pickup = (await staff.pickups()).single;
      await expectLater(staff.declinePickup(pickup.id), throwsStateError);
      await managerShifts.declinePickup(pickup.id, reason: 'Coverage changed');
      expect((await staff.pickups()).single.status, PickupStatus.declined);
      expect((await managerShifts.openShifts()).single.id, shift.id);
      await expectLater(
        managerShifts.approvePickup(pickup.id),
        throwsStateError,
      );
    },
  );

  test('CNA and unit clerk each see only Open shifts in their role', () async {
    for (final (id, section, code) in [
      ('cna', 'cna', '7C'),
      ('clerk', 'clerk', '7U'),
    ]) {
      await manager.saveCell(
        SaveCell(
          staffMemberId: id,
          sectionId: section,
          date: day,
          shiftCode: code,
        ),
      );
      final request = await ScheduleRules.inMemory(
        database,
        actingAs: id,
      ).requestOff(RequestOffDraft(dates: [day]));
      await manager.decideRequestOff(
        request.requestId,
        RequestOffDecision.approved,
      );
    }
    expect(
      (await OpenShiftRules(
        database.openShiftStoreFor('lpn'),
      ).openShifts()).map((shift) => shift.shiftCode),
      ['7A'],
    );
    expect(
      (await OpenShiftRules(
        database.openShiftStoreFor('cna'),
      ).openShifts()).map((shift) => shift.shiftCode),
      ['7C'],
    );
    expect(
      (await OpenShiftRules(
        database.openShiftStoreFor('clerk'),
      ).openShifts()).map((shift) => shift.shiftCode),
      ['7U'],
    );
  });

  test(
    'pickup waits for Manager; approval assigns shift and clears short mark',
    () async {
      final lpn = OpenShiftRules(database.openShiftStoreFor('lpn'));
      final open = (await lpn.openShifts()).single;
      await lpn.requestPickup(open.id);
      expect((await lpn.pickups()).single.status, PickupStatus.pending);
      expect(
        (await manager.monthGrid(DateTime(2026, 10))).shiftCodeFor('lpn', day),
        isNot('7A'),
      );
      await expectLater(
        lpn.approvePickup((await lpn.pickups()).single.id),
        throwsStateError,
      );
      await managerShifts.approvePickup(
        (await managerShifts.pickups()).single.id,
      );
      final grid = await manager.monthGrid(DateTime(2026, 10));
      expect(grid.shiftCodeFor('lpn', day), '7A');
      expect(grid.shortShiftsOn(RolePool.nurses, CoverageWindow.day, day), isEmpty);
      expect(await managerShifts.openShifts(), isEmpty);
      expect((await lpn.pickups()).single.status, PickupStatus.approved);
    },
  );

  test('pickup refuses a colleague already scheduled that day', () async {
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'lpn',
        sectionId: 'nursing',
        date: day,
        shiftCode: '7P',
      ),
    );
    final lpn = OpenShiftRules(database.openShiftStoreFor('lpn'));
    await expectLater(
      lpn.requestPickup((await lpn.openShifts()).single.id),
      throwsStateError,
    );
  });

  test('approving one pickup closes competing requests', () async {
    final lpn = OpenShiftRules(database.openShiftStoreFor('lpn'));
    final other = OpenShiftRules(database.openShiftStoreFor('other'));
    final open = (await lpn.openShifts()).single;
    await lpn.requestPickup(open.id);
    await other.requestPickup(open.id);
    await managerShifts.approvePickup((await lpn.pickups()).single.id);
    expect((await other.pickups()).single.status, PickupStatus.declined);
  });

  test(
    'a night nurse picking up a night code counts in the night nursing pool',
    () async {
      await manager.changeSection(
        ChangeSection(
          staffMemberId: 'lpn',
          sectionId: 'other-nursing',
          from: day,
        ),
      );
      await managerShifts.setWeekdayMinimum(RolePool.nurses, CoverageWindow.night, day.weekday % 7, 1, 0);
      await managerShifts.postOpenShifts(day, '7P', RolePool.nurses, 1);
      final lpn = OpenShiftRules(database.openShiftStoreFor('lpn'));
      final posted = (await lpn.openShifts())
          .where((shift) => shift.shiftCode == '7P')
          .single;
      await lpn.requestPickup(posted.id);
      await managerShifts.approvePickup((await lpn.pickups()).single.id);
      final staffing = await managerShifts.staffingForMonth(day);
      expect(
        staffing
            .singleWhere(
              (item) => item.pool == RolePool.nurses &&
                  item.coverageWindow == CoverageWindow.night && item.date == day,
            )
            .workingCount,
        1,
      );
      expect(
        staffing
            .singleWhere(
              (item) => item.pool == RolePool.nurses &&
                  item.coverageWindow == CoverageWindow.day && item.date == day,
            )
            .workingCount,
        0,
      );
    },
  );

  test(
    'a Last day posts later working shifts using the departing role',
    () async {
      final later = DateTime(2026, 10, 13);
      await manager.saveCell(
        SaveCell(
          staffMemberId: 'original',
          sectionId: 'nursing',
          date: later,
          shiftCode: '7P',
        ),
      );
      await manager.setLastDay(
        SetLastDay(staffMemberId: 'original', lastDay: day),
      );
      final visible = await OpenShiftRules(database.openShiftStoreFor('lpn'))
          .openShifts();
      expect(
        visible.where((shift) => shift.date == later).single.shiftCode,
        '7P',
      );
    },
  );

  test('a CNA shortfall appears in its pool while nursing is covered', () async {
    await managerShifts.setWeekdayMinimum(
        RolePool.nurses, CoverageWindow.day, day.weekday % 7, 1, 0);
    await managerShifts.setWeekdayMinimum(
        RolePool.cna, CoverageWindow.day, day.weekday % 7, 1, 0);
    await manager.saveCell(SaveCell(
        staffMemberId: 'other', sectionId: 'nursing', date: day,
        shiftCode: '7A'));
    final staffing = await managerShifts.staffingForMonth(day);
    final nurses = staffing.singleWhere((item) => item.date == day &&
        item.pool == RolePool.nurses && item.coverageWindow == CoverageWindow.day);
    final cna = staffing.singleWhere((item) => item.date == day &&
        item.pool == RolePool.cna && item.coverageWindow == CoverageWindow.day);
    expect(nurses.shortCount, 0);
    expect(cna.shortCount, 1);
  });

  test('the RN floor is short with enough LPNs on days', () async {
    await managerShifts.setWeekdayMinimum(
        RolePool.nurses, CoverageWindow.day, day.weekday % 7, 2, 1);
    await manager.changeJobRole(ChangeJobRole(
        staffMemberId: 'other', jobRole: JobRole.lpn, from: day));
    for (final id in ['lpn', 'other']) {
      await manager.saveCell(SaveCell(
          staffMemberId: id, sectionId: 'nursing', date: day,
          shiftCode: '7A'));
    }
    final nurses = (await managerShifts.staffingForMonth(day)).singleWhere(
        (item) => item.date == day && item.pool == RolePool.nurses &&
            item.coverageWindow == CoverageWindow.day);
    expect(nurses.workingCount, 2);
    expect(nurses.rnCount, 0);
    expect(nurses.shortCount, 1);
    expect(nurses.rnShortCount, 1);
  });

  test('an unset pool is distinguishable from a zero minimum', () async {
    final cna = (await managerShifts.staffingForMonth(day)).singleWhere(
        (item) => item.date == day && item.pool == RolePool.cna &&
            item.coverageWindow == CoverageWindow.day);
    expect(cna.minimum, isNull);
    expect(cna.shortCount, isNull);
    await managerShifts.setDateMinimum(
        RolePool.cna, CoverageWindow.day, day, 0, 0);
    final zero = (await managerShifts.staffingForMonth(day)).singleWhere(
        (item) => item.date == day && item.pool == RolePool.cna &&
            item.coverageWindow == CoverageWindow.day);
    expect(zero.minimum, 0);
    expect(zero.shortCount, 0);
  });
}
