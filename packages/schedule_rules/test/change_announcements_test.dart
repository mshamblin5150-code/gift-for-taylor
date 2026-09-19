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
      sections: const [days, nights],
      rows: const [dana, lee, sam],
    );
    manager = ScheduleRules.inMemory(database, actingAs: 'manager');
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

  test('a cell changed back to its published value is not announced', () async {
    await publishStartingMonth();
    await save(sam, 18, 'X');
    await save(sam, 18, '7A');

    expect((await manager.changeAnnouncement(september)).isEmpty, isTrue);
  });

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

  test('someone with no cell number is left out of the group text', () async {
    final noCell = InMemoryScheduleDatabase(
      sections: const [days],
      rows: const [
        dana,
        ScheduleRow(
          staffMemberId: 'rn-4',
          displayName: 'Kim',
          sectionId: 'days',
        ),
      ],
    );
    final rules = ScheduleRules.inMemory(noCell, actingAs: 'manager');
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
    expect(announcement.groupRecipients, ['5550100']);
    expect(announcement.groupMessage, contains('Kim:'));
  });

  test('mark announced clears the tray and the highlights', () async {
    await publishStartingMonth();
    await save(dana, 18, 'X');
    await save(sam, 19, 'N');

    await manager.markAnnounced(await manager.changeAnnouncement(september));

    expect((await manager.changeAnnouncement(september)).isEmpty, isTrue);
    final grid = await manager.monthGrid(september);
    expect(grid.isUnannounced('rn-1', DateTime(2026, 9, 18)), isFalse);
    expect(grid.shiftCodeFor('rn-1', DateTime(2026, 9, 18)), 'X');
    expect(
      (await manager.changeLog(september)).every((change) => change.announced),
      isTrue,
    );
  });

  test('a change saved after the tray was read stays unannounced', () async {
    await publishStartingMonth();
    await save(dana, 18, 'X');
    final announcement = await manager.changeAnnouncement(september);
    await save(sam, 19, 'N');

    await manager.markAnnounced(announcement);

    final remaining = await manager.changeAnnouncement(september);
    expect(remaining.people.single.row.displayName, 'Sam Ortiz');
  });

  test('only a scheduler may mark changes announced', () async {
    final restricted = InMemoryScheduleDatabase(
      sections: const [days],
      rows: const [dana],
      editors: const {'manager'},
    );
    final scheduler = ScheduleRules.inMemory(restricted, actingAs: 'manager');
    await scheduler.saveCell(
      SaveCell(
        staffMemberId: 'rn-1',
        sectionId: 'days',
        date: DateTime(2026, 9, 18),
        shiftCode: 'X',
      ),
    );
    final announcement = await scheduler.changeAnnouncement(september);

    await expectLater(
      ScheduleRules.inMemory(
        restricted,
        actingAs: 'rn-1',
      ).markAnnounced(announcement),
      throwsA(isA<ScheduleEditRefused>()),
    );
    expect((await scheduler.changeAnnouncement(september)).isEmpty, isFalse);
  });
}
