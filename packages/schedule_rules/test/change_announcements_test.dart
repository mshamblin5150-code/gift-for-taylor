import 'package:schedule_rules_testing/schedule_rules_testing.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:test/test.dart';

void main() {
  const days = ScheduleSection(id: 'days', name: 'State dayshift RN');
  const nights = ScheduleSection(id: 'nights', name: 'PRN nightshift RN');
  const dana = ScheduleRow(
    staffMemberId: 'rn-1',
    displayName: 'Dana Reyes',
    sectionId: 'days',
    cellNumber: '5550100',
  );
  const sam = ScheduleRow(
    staffMemberId: 'rn-2',
    displayName: 'Sam Ortiz',
    sectionId: 'nights',
    cellNumber: '5550101',
  );
  const lee = ScheduleRow(
    staffMemberId: 'rn-3',
    displayName: 'Lee Park',
    sectionId: 'days',
    cellNumber: '5550102',
  );
  final september = DateTime(2026, 9);

  late InMemoryScheduleDatabase database;
  late ScheduleRules manager;

  setUp(() {
    database = InMemoryScheduleDatabase(
      grants: {
        'manager': Grants(manager: true),
        'night-scheduler': Grants(nightSchedulerSectionIds: {'nights'}),
      },
      sections: const [days, nights],
      rows: const [dana, lee, sam],
      releasedMonths: {september},
    );
    manager = scheduleRulesInMemory(database, actingAs: 'manager');
  });

  Future<void> save(ScheduleRow row, int day, String code) {
    return manager.saveCell(
      SaveCell(
        staffMemberId: row.staffMemberId,
        sectionId: row.sectionId,
        date: DateTime(2026, 9, day),
        shiftCode: code,
      ),
    );
  }

  /// Publishes a starting month: everyone works 7A on the 18th and 19th.
  Future<void> publishStartingMonth() async {
    for (final row in [dana, lee, sam]) {
      await save(row, 18, '7A');
      await save(row, 19, '7A');
    }
    database.markAllAnnounced();
  }

  test('with no unannounced changes the tray is empty', () async {
    await publishStartingMonth();

    final announcement = await manager.changeAnnouncement(september);

    expect(announcement.isEmpty, isTrue);
    expect(announcement.changeCount, 0);
    expect(announcement.people, isEmpty);
    expect(announcement.groupMessage, isNull);
  });

  test('only people whose own shifts changed are listed', () async {
    await publishStartingMonth();
    await save(dana, 18, 'X');
    await save(dana, 19, 'N');

    final announcement = await manager.changeAnnouncement(september);

    expect(announcement.changeCount, 2);
    final person = announcement.people.single;
    expect(person.row.displayName, 'Dana Reyes');
    expect(person.cellNumber, '5550100');
    expect(
      person.changedDays.map(
        (day) => '${day.date.day} ${day.oldShiftCode}->${day.newShiftCode}',
      ),
      ['18 7A->X', '19 7A->N'],
    );
  });

  test('one message per person lists each changed day, new and old', () async {
    await publishStartingMonth();
    await save(dana, 19, 'N');
    await save(dana, 18, 'X');

    final announcement = await manager.changeAnnouncement(september);

    expect(
      announcement.people.single.message,
      'Hi Dana Reyes, ER Schedule change:\n'
      'Fri 9/18: off (was 7A)\n'
      'Sat 9/19: N (was 7A)',
    );
  });

  test('one Swap groups its changed days and names the cause', () async {
    await publishStartingMonth();
    await save(dana, 18, 'X');
    await save(dana, 19, 'N');
    final changes = await manager.changeLog(september);
    database.seedScheduleChanges([
      for (final change in changes.where((change) => !change.announced))
        ScheduleChange(
          id: change.id,
          staffMemberId: change.staffMemberId,
          date: change.date,
          oldShiftCode: change.oldShiftCode,
          newShiftCode: change.newShiftCode,
          changedBy: change.changedBy,
          changedByName: change.changedByName,
          changedAt: change.changedAt,
          announced: false,
          swapId: 'swap-1',
        ),
    ]);

    expect(
      (await manager.changeAnnouncement(september)).people.single.message,
      'Hi Dana Reyes, ER Schedule change:\n'
      'Swap:\n'
      '  Fri 9/18: off (was 7A)\n'
      '  Sat 9/19: N (was 7A)',
    );
  });

  test('one Giveaway groups its changed days and names the cause', () async {
    await publishStartingMonth();
    await save(dana, 18, 'X');
    await save(dana, 19, 'N');
    final changes = await manager.changeLog(september);
    database.seedScheduleChanges([
      for (final change in changes.where((change) => !change.announced))
        ScheduleChange(
          id: change.id,
          staffMemberId: change.staffMemberId,
          date: change.date,
          oldShiftCode: change.oldShiftCode,
          newShiftCode: change.newShiftCode,
          changedBy: change.changedBy,
          changedByName: change.changedByName,
          changedAt: change.changedAt,
          announced: false,
          giveawayId: 'giveaway-1',
        ),
    ]);

    expect(
      (await manager.changeAnnouncement(september)).people.single.message,
      'Hi Dana Reyes, ER Schedule change:\n'
      'Giveaway:\n'
      '  Fri 9/18: off (was 7A)\n'
      '  Sat 9/19: N (was 7A)',
    );
  });

  test('interleaved Swap days stay grouped by Swap', () async {
    await publishStartingMonth();
    await save(dana, 20, '7A');
    database.markAllAnnounced();
    await save(dana, 18, 'X');
    await save(dana, 19, 'N');
    await save(dana, 20, 'X');
    final changes = await manager.changeLog(september);
    database.seedScheduleChanges([
      for (final change in changes.where((change) => !change.announced))
        ScheduleChange(
          id: change.id,
          staffMemberId: change.staffMemberId,
          date: change.date,
          oldShiftCode: change.oldShiftCode,
          newShiftCode: change.newShiftCode,
          changedBy: change.changedBy,
          changedByName: change.changedByName,
          changedAt: change.changedAt,
          announced: false,
          swapId: change.date.day == 19 ? 'swap-2' : 'swap-1',
        ),
    ]);

    expect(
      (await manager.changeAnnouncement(september)).people.single.message,
      'Hi Dana Reyes, ER Schedule change:\n'
      'Swap:\n'
      '  Fri 9/18: off (was 7A)\n'
      '  Sun 9/20: off (was 7A)\n'
      'Swap:\n'
      '  Sat 9/19: N (was 7A)',
    );
  });

  test('several edits to one cell announce only the net change', () async {
    await publishStartingMonth();
    await save(sam, 18, 'X');
    await save(sam, 18, 'S/L');

    final day = (await manager.changeAnnouncement(september))
        .people
        .single
        .changedDays
        .single;

    expect(day.oldShiftCode, '7A');
    expect(day.newShiftCode, 'S/L');
  });

  test('a cell restored to its announced value has no net change', () async {
    await publishStartingMonth();
    await save(sam, 18, 'X');
    await save(sam, 18, '7A');

    final announcement = await manager.changeAnnouncement(september);
    expect(announcement.isEmpty, isTrue);
    expect(announcement.hasPendingChanges, isTrue);
  });

  test('a Call-in followed by off announces one change from 7P to X', () async {
    await save(sam, 18, '7P');
    database.markAllAnnounced();
    await save(sam, 18, 'C/I');
    await save(sam, 18, 'X');

    final announcement = await manager.changeAnnouncement(september);
    expect(announcement.changeCount, 1);
    final day = announcement.people.single.changedDays.single;
    expect(day.oldShiftCode, '7P');
    expect(day.newShiftCode, 'X');
    expect(announcement.people.single.message, contains('off (was 7P)'));
  });

  test(
    'a multi-step reversal leaves another day in the announcement',
    () async {
      await publishStartingMonth();
      await save(sam, 18, 'C/I');
      await save(sam, 18, 'X');
      await save(sam, 18, '7A');
      await save(sam, 19, 'X');

      final announcement = await manager.changeAnnouncement(september);
      expect(announcement.changeCount, 1);
      final changedDay = announcement.people.single.changedDays.single;
      expect(changedDay.date.day, 19);
      expect(changedDay.oldShiftCode, '7A');
      expect(changedDay.newShiftCode, 'X');
    },
  );

  test('a blank cell reads as blank in the message', () async {
    await save(lee, 3, 'MM');

    expect(
      (await manager.changeAnnouncement(september)).people.single.message,
      'Hi Lee Park, ER Schedule change:\nThu 9/3: MM (was blank)',
    );
  });

  test(
    'a multi-person change has one group message to everyone affected',
    () async {
      await publishStartingMonth();
      await save(sam, 19, 'X');
      await save(dana, 18, 'R/O');
      await save(lee, 18, '16D');

      final announcement = await manager.changeAnnouncement(september);

      expect(announcement.people.map((person) => person.row.displayName), [
        'Dana Reyes',
        'Lee Park',
        'Sam Ortiz',
      ]);
      expect(announcement.groupRecipients, ['5550100', '5550102', '5550101']);
      expect(
        announcement.groupMessage,
        'ER Schedule changes:\n'
        'Dana Reyes:\n'
        'Fri 9/18: R/O (was 7A)\n'
        'Lee Park:\n'
        'Fri 9/18: 16D (was 7A)\n'
        'Sam Ortiz:\n'
        'Sat 9/19: off (was 7A)',
      );
    },
  );

  test('a one-person change has no group message', () async {
    await publishStartingMonth();
    await save(dana, 18, 'X');

    final announcement = await manager.changeAnnouncement(september);

    expect(announcement.groupMessage, isNull);
    expect(announcement.groupRecipients, isEmpty);
  });

  test('one text fallback has no group text', () async {
    final noCell = InMemoryScheduleDatabase(
      grants: {'manager': Grants(manager: true)},
      sections: const [days],
      releasedMonths: {september},
      rows: const [
        dana,
        ScheduleRow(
          staffMemberId: 'rn-4',
          displayName: 'Kim',
          sectionId: 'days',
        ),
      ],
    );
    final rules = scheduleRulesInMemory(noCell, actingAs: 'manager');
    for (final id in ['rn-1', 'rn-4']) {
      await rules.saveCell(
        SaveCell(
          staffMemberId: id,
          sectionId: 'days',
          date: DateTime(2026, 9, 18),
          shiftCode: 'X',
        ),
      );
    }

    final announcement = await rules.changeAnnouncement(september);

    expect(announcement.people.map((person) => person.cellNumber), [
      '5550100',
      null,
    ]);
    expect(announcement.groupRecipients, isEmpty);
    expect(announcement.groupMessage, isNull);
  });

  test('Change announcement includes only editable Section rows', () async {
    await publishStartingMonth();
    await save(dana, 18, 'X');
    await save(sam, 19, 'N');

    final scheduler = scheduleRulesInMemory(
      database,
      actingAs: 'night-scheduler',
    );
    final announcement = await scheduler.changeAnnouncement(september);
    expect(announcement.people.map((person) => person.row.displayName), [
      'Sam Ortiz',
    ]);
  });
}
