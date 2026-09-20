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
  const nightNurse = ScheduleRow(
    staffMemberId: 'rn-2',
    displayName: 'Night RN',
    sectionId: 'nights',
  );
  final september18 = DateTime(2026, 9, 18);
  final september = DateTime(2026, 9);

  late DateTime now;
  late InMemoryScheduleDatabase database;
  late ScheduleRules manager;

  setUp(() {
    now = DateTime(2026, 9, 18, 9, 30);
    database = InMemoryScheduleDatabase(
      sections: const [days, nights],
      rows: const [dayNurse, nightNurse],
      clock: () => now,
    );
    manager = ScheduleRules.inMemory(database, actingAs: 'manager');
  });

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

  test('the month grid lists Sections and their rows in order', () async {
    final grid = await manager.monthGrid(september);

    expect(grid.sections.map((section) => section.name), [
      'State dayshift RN',
      'PRN nightshift RN',
    ]);
    expect(grid.rowsIn('nights').single.displayName, 'Night RN');
    expect(grid.days.length, 30);
  });

  test('a saved Shift code is live in the month grid', () async {
    await save(manager, dayNurse, '7A');

    final grid = await manager.monthGrid(september);

    expect(grid.shiftCodeFor('rn-1', september18), '7A');
  });

  test('any typed Shift code is accepted, trimmed', () async {
    await save(manager, dayNurse, '  4P-8A ');

    final grid = await manager.monthGrid(september);

    expect(grid.shiftCodeFor('rn-1', september18), '4P-8A');
  });

  test('a save is visible to another scheduler reading the month', () async {
    final otherScheduler = ScheduleRules.inMemory(
      database,
      actingAs: 'night-scheduler',
    );
    final updates = otherScheduler.monthUpdates(september).first;

    await save(manager, dayNurse, 'N');

    await updates;
    final grid = await otherScheduler.monthGrid(september);
    expect(grid.shiftCodeFor('rn-1', september18), 'N');
  });

  test(
    'every save writes who, which cell, old and new value, and when',
    () async {
      await save(manager, dayNurse, '7A');
      now = DateTime(2026, 9, 18, 10);
      await save(manager, dayNurse, 'X');

      final log = await manager.changeLog(september);

      expect(log.length, 2);
      final latest = log.last;
      expect(latest.changedBy, 'manager');
      expect(latest.staffMemberId, 'rn-1');
      expect(latest.date, september18);
      expect(latest.oldShiftCode, '7A');
      expect(latest.newShiftCode, 'X');
      expect(latest.changedAt, DateTime(2026, 9, 18, 10));
      expect(log.first.oldShiftCode, '');
    },
  );

  test('saving the same Shift code again logs nothing', () async {
    await save(manager, dayNurse, '7A');
    await save(manager, dayNurse, '7A');

    expect((await manager.changeLog(september)).length, 1);
  });

  test(
    'a changed, unannounced cell is highlighted with its published value',
    () async {
      await save(manager, dayNurse, '7A');
      database.markAllAnnounced();
      await save(manager, dayNurse, 'X');
      await save(manager, dayNurse, 'R/O');

      final grid = await manager.monthGrid(september);

      expect(grid.isUnannounced('rn-1', september18), isTrue);
      expect(grid.publishedCodeFor('rn-1', september18), '7A');
      expect(grid.isUnannounced('rn-2', september18), isFalse);
    },
  );

  test(
    'changing a cell back to its published value clears the highlight',
    () async {
      await save(manager, dayNurse, '7A');
      database.markAllAnnounced();
      await save(manager, dayNurse, 'X');
      await save(manager, dayNurse, '7A');

      final grid = await manager.monthGrid(september);

      expect(grid.isUnannounced('rn-1', september18), isFalse);
    },
  );

  test('undo restores the published value and is itself logged', () async {
    await save(manager, dayNurse, '7A');
    database.markAllAnnounced();
    await save(manager, dayNurse, 'X');
    await save(manager, dayNurse, 'S/L');

    await manager.undoCell(
      UndoCell(staffMemberId: 'rn-1', sectionId: 'days', date: september18),
    );

    final grid = await manager.monthGrid(september);
    expect(grid.shiftCodeFor('rn-1', september18), '7A');
    expect(grid.isUnannounced('rn-1', september18), isFalse);
    final undo = (await manager.changeLog(september)).last;
    expect(undo.oldShiftCode, 'S/L');
    expect(undo.newShiftCode, '7A');
  });

  test('undo on a cell with no unannounced change does nothing', () async {
    await save(manager, dayNurse, '7A');
    database.markAllAnnounced();

    await manager.undoCell(
      UndoCell(staffMemberId: 'rn-1', sectionId: 'days', date: september18),
    );

    expect((await manager.changeLog(september)).length, 1);
    expect(
      (await manager.monthGrid(september)).shiftCodeFor('rn-1', september18),
      '7A',
    );
  });

  test('the day view and one-person view read the same cells', () async {
    await save(manager, dayNurse, '7A');
    await save(manager, nightNurse, '7P');

    final grid = await manager.monthGrid(september);

    expect(
      grid
          .rowsOn(september18)
          .map((entry) => '${entry.row.displayName} ${entry.shiftCode}'),
      ['Day RN 7A', 'Night RN 7P'],
    );
    final nightMonth = grid.monthFor('rn-2');
    expect(nightMonth.length, 30);
    expect(nightMonth[17].shiftCode, '7P');
    expect(nightMonth[16].shiftCode, '');
  });

  test('only the Manager may change the Schedule', () async {
    final restricted = InMemoryScheduleDatabase(
      sections: const [days],
      rows: const [dayNurse],
      editors: const {'manager'},
    );
    final staffMember = ScheduleRules.inMemory(restricted, actingAs: 'rn-1');

    await expectLater(
      save(staffMember, dayNurse, 'R/O'),
      throwsA(isA<ScheduleEditRefused>()),
    );
    expect(await staffMember.changeLog(september), isEmpty);

    expect(
      await ScheduleRules.inMemory(
        restricted,
        actingAs: 'manager',
      ).canEditSchedule(),
      isTrue,
    );
    expect(
      await ScheduleRules.inMemory(
        restricted,
        actingAs: 'rn-1',
      ).canEditSchedule(),
      isFalse,
    );
  });

  test('the legend lists every common Shift code with its hours', () {
    expect(shiftLegend.map((code) => code.code), [
      '16D',
      '7A',
      'D',
      'MM',
      '11A',
      '3P',
      '7P',
      'ME',
      'N',
      'X',
      'R/O',
      'H',
      'S/L',
      'C/I',
    ]);
    expect(shiftLegend.firstWhere((code) => code.code == 'ME').hours, '7P–3A');
    expect(shiftLegend.firstWhere((code) => code.code == 'X').hours, isNull);
  });
}
