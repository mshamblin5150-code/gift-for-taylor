import 'package:schedule_rules/schedule_rules.dart';
import 'package:test/test.dart';

void main() {
  const days = ScheduleSection(id: 'days', name: 'State dayshift RN');
  const nights = ScheduleSection(id: 'nights', name: 'PRN nightshift RN');
  const dayNurse = ScheduleRow(
    staffMemberId: 'rn-1',
    displayName: 'Day RN',
    sectionId: 'days',
  );
  const secondDayNurse = ScheduleRow(
    staffMemberId: 'rn-2',
    displayName: 'Second day RN',
    sectionId: 'days',
  );
  const nightNurse = ScheduleRow(
    staffMemberId: 'rn-3',
    displayName: 'Night RN',
    sectionId: 'nights',
  );
  final september = DateTime(2026, 9);
  final october = DateTime(2026, 10);
  final november = DateTime(2026, 11);

  late DateTime now;
  late InMemoryScheduleDatabase database;
  late ScheduleRules manager;

  setUp(() {
    now = DateTime(2026, 9, 18, 9, 30);
    database = InMemoryScheduleDatabase(
      sections: const [days, nights],
      rows: const [dayNurse, secondDayNurse, nightNurse],
      clock: () => now,
    );
    manager = ScheduleRules.inMemory(database, actingAs: 'manager');
  });

  Future<void> save(String staffMemberId, DateTime date, String code) {
    return manager.saveCell(
      SaveCell(
        staffMemberId: staffMemberId,
        sectionId: staffMemberId == 'rn-3' ? 'nights' : 'days',
        date: date,
        shiftCode: code,
      ),
    );
  }

  group('Last day', () {
    setUp(() async {
      await save('rn-1', DateTime(2026, 9, 29), '7A');
      await save('rn-1', DateTime(2026, 9, 30), '7A');
      await save('rn-1', DateTime(2026, 10, 1), 'X');
      await save('rn-1', DateTime(2026, 10, 2), '16D');
      await save('rn-1', DateTime(2026, 10, 3), 'R/O');
      database.markAllAnnounced();
    });

    test('keeps shifts through the Last day and clears later ones', () async {
      await manager.setLastDay(
        SetLastDay(staffMemberId: 'rn-1', lastDay: DateTime(2026, 9, 30)),
      );

      final sept = await manager.monthGrid(september);
      final oct = await manager.monthGrid(october);
      expect(sept.shiftCodeFor('rn-1', DateTime(2026, 9, 29)), '7A');
      expect(sept.shiftCodeFor('rn-1', DateTime(2026, 9, 30)), '7A');
      expect(oct.shiftCodeFor('rn-1', DateTime(2026, 10, 1)) ?? '', '');
      expect(oct.shiftCodeFor('rn-1', DateTime(2026, 10, 2)) ?? '', '');
      expect(oct.shiftCodeFor('rn-1', DateTime(2026, 10, 3)) ?? '', '');
    });

    test(
      'marks a cleared working shift short in its pool and window',
      () async {
        await manager.changeJobRole(
          ChangeJobRole(
            staffMemberId: 'rn-1',
            jobRole: JobRole.rn,
            from: DateTime(2026, 1),
          ),
        );
        await manager.setLastDay(
          SetLastDay(staffMemberId: 'rn-1', lastDay: DateTime(2026, 9, 30)),
        );

        final oct = await manager.monthGrid(october);
        final short = oct.shortShiftsOn(
          CoveragePool.nurses,
          CoverageWindow.day,
          DateTime(2026, 10, 2),
        );
        expect(short.single.shiftCode, '16D');
        expect(short.single.staffMemberId, 'rn-1');
        // Days off and requested-off days leave no hole.
        expect(
          oct.shortShiftsOn(
            CoveragePool.nurses,
            CoverageWindow.day,
            DateTime(2026, 10, 1),
          ),
          isEmpty,
        );
        expect(
          oct.shortShiftsOn(
            CoveragePool.nurses,
            CoverageWindow.day,
            DateTime(2026, 10, 3),
          ),
          isEmpty,
        );
        expect(oct.shortShifts, hasLength(1));
      },
    );

    test('every cleared cell is written to the change log', () async {
      await manager.setLastDay(
        SetLastDay(staffMemberId: 'rn-1', lastDay: DateTime(2026, 9, 30)),
      );

      final cleared = (await manager.changeLog(october))
          .where((change) => !change.announced)
          .toList();
      expect(cleared.map((change) => change.oldShiftCode), ['X', '16D', 'R/O']);
      expect(cleared.every((change) => change.newShiftCode == ''), isTrue);
      expect(cleared.every((change) => change.changedBy == 'manager'), isTrue);
    });

    test(
      'the row stays through the Last day, then leaves later months',
      () async {
        await manager.setLastDay(
          SetLastDay(staffMemberId: 'rn-1', lastDay: DateTime(2026, 10, 1)),
        );

        final oct = await manager.monthGrid(october);
        final row = oct.rows.singleWhere((row) => row.staffMemberId == 'rn-1');
        expect(row.lastDay, DateTime(2026, 10, 1));
        expect(oct.isOnSchedule(row, DateTime(2026, 10, 1)), isTrue);
        expect(oct.isOnSchedule(row, DateTime(2026, 10, 2)), isFalse);
        expect(
          oct.rowsOn(DateTime(2026, 10, 2)).map((day) => day.row.staffMemberId),
          isNot(contains('rn-1')),
        );
        expect(
          (await manager.monthGrid(november)).rows.map((r) => r.staffMemberId),
          isNot(contains('rn-1')),
        );
      },
    );

    test('past months keep the person as they were', () async {
      await manager.setLastDay(
        SetLastDay(staffMemberId: 'rn-1', lastDay: DateTime(2026, 9, 30)),
      );

      final sept = await manager.monthGrid(september);
      expect(sept.rowsIn('days').map((row) => row.displayName), [
        'Day RN',
        'Second day RN',
      ]);
      expect(
        (await manager.changeLog(september)).map((c) => c.staffMemberId),
        everyElement('rn-1'),
      );
    });

    test('no cell after the Last day can be saved', () async {
      await manager.setLastDay(
        SetLastDay(staffMemberId: 'rn-1', lastDay: DateTime(2026, 9, 30)),
      );

      await expectLater(
        save('rn-1', DateTime(2026, 10, 5), '7A'),
        throwsA(isA<StateError>()),
      );
      await save('rn-1', DateTime(2026, 9, 30), 'S/L');
      expect(
        (await manager.monthGrid(september))
            .shiftCodeFor('rn-1', DateTime(2026, 9, 30)),
        'S/L',
      );
    });

    test('is logged and can be set only once', () async {
      await manager.setLastDay(
        SetLastDay(staffMemberId: 'rn-1', lastDay: DateTime(2026, 9, 30)),
      );

      final change = (await manager.staffChanges()).single;
      expect(change.kind, StaffChangeKind.lastDay);
      expect(change.staffMemberId, 'rn-1');
      expect(change.effectiveFrom, DateTime(2026, 9, 30));
      expect(change.changedBy, 'manager');
      await expectLater(
        manager.setLastDay(
          SetLastDay(staffMemberId: 'rn-1', lastDay: DateTime(2026, 10, 30)),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('the Manager cannot set her own Last day', () async {
      final own = ScheduleRules.inMemory(database, actingAs: 'rn-2');

      await expectLater(
        own.setLastDay(
          SetLastDay(staffMemberId: 'rn-2', lastDay: DateTime(2026, 9, 30)),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('reactivation', () {
    setUp(() async {
      await save('rn-1', DateTime(2026, 9, 10), '7A');
      await manager.setLastDay(
        SetLastDay(staffMemberId: 'rn-1', lastDay: DateTime(2026, 9, 15)),
      );
    });

    test('restores the same person, with their history connected', () async {
      await manager.reactivate(
        Reactivate(
          staffMemberId: 'rn-1',
          sectionId: 'nights',
          firstDay: DateTime(2026, 11, 1),
        ),
      );

      final nov = await manager.monthGrid(november);
      final row = nov.rows.singleWhere((row) => row.staffMemberId == 'rn-1');
      expect(row.sectionId, 'nights');
      expect(row.lastDay, isNull);
      expect(nov.rowsIn('nights').last.staffMemberId, 'rn-1');
      expect(
        (await manager.monthGrid(october)).rows.map((r) => r.staffMemberId),
        isNot(contains('rn-1')),
      );
      final sept = await manager.monthGrid(september);
      expect(sept.shiftCodeFor('rn-1', DateTime(2026, 9, 10)), '7A');
      // The month they left still ends at their old Last day.
      expect(
        sept.rows.singleWhere((row) => row.staffMemberId == 'rn-1').lastDay,
        DateTime(2026, 9, 15),
      );
      await expectLater(
        save('rn-1', DateTime(2026, 9, 20), '7A'),
        throwsA(isA<StateError>()),
      );
      expect(
        (await manager.staffChanges()).last.kind,
        StaffChangeKind.reactivated,
      );
    });

    test('must start after their Last day', () async {
      await expectLater(
        manager.reactivate(
          Reactivate(
            staffMemberId: 'rn-1',
            sectionId: 'days',
            firstDay: DateTime(2026, 9, 15),
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('only someone off the Staff list can be reactivated', () async {
      await expectLater(
        manager.reactivate(
          Reactivate(
            staffMemberId: 'rn-2',
            sectionId: 'days',
            firstDay: DateTime(2026, 10, 1),
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Section change', () {
    test(
      'a mid-month move places the row in the new Section for that month',
      () async {
        await save('rn-1', DateTime(2026, 10, 5), '7A');
        await save('rn-1', DateTime(2026, 10, 20), '7A');

        await manager.changeSection(
          ChangeSection(
            staffMemberId: 'rn-1',
            sectionId: 'nights',
            from: DateTime(2026, 10, 15),
          ),
        );

        final sept = await manager.monthGrid(september);
        final oct = await manager.monthGrid(october);
        expect(sept.rowsIn('days').map((row) => row.staffMemberId), [
          'rn-1',
          'rn-2',
        ]);
        expect(oct.rowsIn('days').map((row) => row.staffMemberId), ['rn-2']);
        expect(oct.rowsIn('nights').map((row) => row.staffMemberId), [
          'rn-3',
          'rn-1',
        ]);
        // Already-scheduled shifts stay for her to adjust.
        expect(oct.shiftCodeFor('rn-1', DateTime(2026, 10, 5)), '7A');
        expect(oct.shiftCodeFor('rn-1', DateTime(2026, 10, 20)), '7A');
        await manager.saveCell(
          SaveCell(
            staffMemberId: 'rn-1',
            sectionId: 'nights',
            date: DateTime(2026, 10, 20),
            shiftCode: '7P',
          ),
        );
        expect(
          (await manager.monthGrid(october))
              .shiftCodeFor('rn-1', DateTime(2026, 10, 20)),
          '7P',
        );
      },
    );

    test('is logged with the old and new Section', () async {
      await manager.changeSection(
        ChangeSection(
          staffMemberId: 'rn-1',
          sectionId: 'nights',
          from: DateTime(2026, 10, 15),
        ),
      );

      final change = (await manager.staffChanges()).single;
      expect(change.kind, StaffChangeKind.section);
      expect(change.oldValue, 'State dayshift RN');
      expect(change.newValue, 'PRN nightshift RN');
      expect(change.effectiveFrom, DateTime(2026, 10, 15));
      expect(change.changedAt, now);
    });

    test('cannot start before their current Section did', () async {
      await manager.changeSection(
        ChangeSection(
          staffMemberId: 'rn-1',
          sectionId: 'nights',
          from: DateTime(2026, 10, 15),
        ),
      );

      await expectLater(
        manager.changeSection(
          ChangeSection(
            staffMemberId: 'rn-1',
            sectionId: 'days',
            from: DateTime(2026, 10, 1),
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('a Last day before a planned move drops the move', () async {
      await manager.changeSection(
        ChangeSection(
          staffMemberId: 'rn-1',
          sectionId: 'nights',
          from: DateTime(2026, 11, 1),
        ),
      );
      await manager.setLastDay(
        SetLastDay(staffMemberId: 'rn-1', lastDay: DateTime(2026, 10, 10)),
      );

      final oct = await manager.monthGrid(october);
      expect(
        oct.rows.singleWhere((row) => row.staffMemberId == 'rn-1').sectionId,
        'days',
      );
      expect(
        (await manager.monthGrid(november)).rows.map((r) => r.staffMemberId),
        isNot(contains('rn-1')),
      );
    });
  });

  group('role change', () {
    test('takes effect from the chosen date and is logged', () async {
      await manager.changeJobRole(
        ChangeJobRole(
          staffMemberId: 'rn-1',
          jobRole: JobRole.lpn,
          from: DateTime(2026, 9, 1),
        ),
      );
      await manager.changeJobRole(
        ChangeJobRole(
          staffMemberId: 'rn-1',
          jobRole: JobRole.rn,
          from: DateTime(2026, 10, 15),
        ),
      );

      expect(await manager.jobRoleOn('rn-1', DateTime(2026, 8, 31)), isNull);
      expect(
        await manager.jobRoleOn('rn-1', DateTime(2026, 10, 14)),
        JobRole.lpn,
      );
      expect(
        await manager.jobRoleOn('rn-1', DateTime(2026, 10, 15)),
        JobRole.rn,
      );
      final changes = await manager.staffChanges();
      expect(changes.map((change) => change.kind), [
        StaffChangeKind.jobRole,
        StaffChangeKind.jobRole,
      ]);
      expect(changes.last.oldValue, 'LPN');
      expect(changes.last.newValue, 'RN');
    });
  });

  test('someone who may not edit cannot change the Staff list', () async {
    final restricted = InMemoryScheduleDatabase(
      sections: const [days],
      rows: const [dayNurse, secondDayNurse],
      editors: const {'manager'},
    );
    final staffMember = ScheduleRules.inMemory(restricted, actingAs: 'rn-2');

    await expectLater(
      staffMember.setLastDay(
        SetLastDay(staffMemberId: 'rn-1', lastDay: DateTime(2026, 9, 30)),
      ),
      throwsA(isA<ScheduleEditRefused>()),
    );
    await expectLater(
      staffMember.changeSection(
        ChangeSection(
          staffMemberId: 'rn-1',
          sectionId: 'days',
          from: DateTime(2026, 9, 30),
        ),
      ),
      throwsA(isA<ScheduleEditRefused>()),
    );
  });

  test('working shifts are every code but blank, X, R/O, H and S/L', () {
    expect(isWorkingShift('7A'), isTrue);
    expect(isWorkingShift('4P-8A'), isTrue);
    for (final code in ['', ' ', 'X', 'x', 'R/O', 'H', 'S/L']) {
      expect(isWorkingShift(code), isFalse, reason: code);
    }
  });
}
