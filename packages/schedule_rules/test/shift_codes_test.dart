import 'package:schedule_rules/schedule_rules.dart';
import 'package:test/test.dart';

void main() {
  final month = DateTime(2027, 3);
  final day = DateTime(2027, 3, 4);
  const section = ScheduleSection(id: 'days', name: 'Days');
  const row = ScheduleRow(
    staffMemberId: 'nurse',
    displayName: 'Nurse',
    sectionId: 'days',
  );

  test(
    'Manager changes hours without changing an existing Schedule cell',
    () async {
      final database = InMemoryScheduleDatabase(
        sections: const [section],
        rows: const [row],
        editors: const {'manager'},
        releasedMonths: {month},
      );
      final manager = ScheduleRules.inMemory(database, actingAs: 'manager');
      await manager.saveCell(
        SaveCell(
          staffMemberId: 'nurse',
          sectionId: 'days',
          date: day,
          shiftCode: '7A',
        ),
      );

      await manager.saveShiftCode(
        const LegendCode(
          '7A',
          startTime: '08:00',
          endTime: '20:00',
          isWorking: true,
        ),
        originalCode: '7A',
      );

      final grid = await manager.monthGrid(month);
      expect(grid.shiftCodeFor('nurse', day), '7A');
      expect(
        bookPageHtml(grid, codes: await manager.shiftCodes()),
        contains('<strong>7A</strong> 8A–8P'),
      );
      expect(
        (await manager.shiftCodes())
            .firstWhere((code) => code.code == '7A')
            .isWorking,
        isTrue,
      );
      await expectLater(manager.deleteShiftCode('7A'), throwsStateError);

      await manager.saveShiftCode(
        const LegendCode(
          'DAY',
          startTime: '09:00',
          endTime: '21:00',
          isWorking: true,
        ),
        originalCode: '7A',
      );
      expect((await manager.monthGrid(month)).shiftCodeFor('nurse', day), '7A');
      expect(
        (await manager.shiftCodes()).any((code) => code.code == 'DAY'),
        isTrue,
      );
      expect(
        (await manager.shiftCodes()).any((code) => code.code == '7A'),
        isFalse,
      );
    },
  );

  test('Manager adds a code and changes whether it counts as worked', () async {
    final database = InMemoryScheduleDatabase(
      sections: const [section],
      rows: const [row],
      editors: const {'manager'},
    );
    final manager = ScheduleRules.inMemory(database, actingAs: 'manager');
    await manager.saveShiftCode(
      const LegendCode('CUSTOM', meaning: 'Training', isWorking: false),
    );
    expect(
      isWorkingShift('CUSTOM', codes: await manager.shiftCodes()),
      isFalse,
    );
    await manager.saveShiftCode(
      const LegendCode('CUSTOM', meaning: 'Coverage', isWorking: true),
      originalCode: 'CUSTOM',
    );
    expect(isWorkingShift('CUSTOM', codes: await manager.shiftCodes()), isTrue);
    await manager.deleteShiftCode('CUSTOM');
    expect(
      (await manager.shiftCodes()).any((code) => code.code == 'CUSTOM'),
      isFalse,
    );
  });
}
