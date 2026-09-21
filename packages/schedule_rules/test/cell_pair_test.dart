import 'package:schedule_rules_testing/schedule_rules_testing.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:test/test.dart';

void main() {
  const days = ScheduleSection(id: 'days', name: 'Days');
  const nights = ScheduleSection(id: 'nights', name: 'Nights');
  const dayNurse = ScheduleRow(
    staffMemberId: 'day',
    displayName: 'Day RN',
    sectionId: 'days',
  );
  const nightNurse = ScheduleRow(
    staffMemberId: 'night',
    displayName: 'Night RN',
    sectionId: 'nights',
  );
  final date = DateTime(2026, 9, 18);
  late InMemoryScheduleDatabase database;
  late ScheduleRules manager;

  SaveCell cell(ScheduleRow row, String code) => SaveCell(
    staffMemberId: row.staffMemberId,
    sectionId: row.sectionId,
    date: date,
    shiftCode: code,
  );

  setUp(() async {
    database = InMemoryScheduleDatabase(
      sections: const [days, nights],
      rows: const [dayNurse, nightNurse],
      grants: {'manager': Grants(manager: true)},
      releasedMonths: {DateTime(2026, 9)},
    );
    manager = scheduleRulesInMemory(database, actingAs: 'manager');
    await manager.saveCell(cell(dayNurse, '7A'));
    await manager.saveCell(cell(nightNurse, 'X'));
  });

  test('a drop swaps codes and records both Schedule changes', () async {
    final before = (await manager.changeLog(date)).length;
    await manager.store.writeCellPair(
      SaveCellPair(
        first: cell(dayNurse, 'X'),
        second: cell(nightNurse, '7A'),
        expectedFirstCode: '7A',
        expectedSecondCode: 'X',
      ),
    );
    final grid = await manager.monthGrid(date);
    expect(grid.shiftCodeFor('day', date), 'X');
    expect(grid.shiftCodeFor('night', date), '7A');
    expect((await manager.changeLog(date)).length, before + 2);
  });

  test('copying across days leaves the source in place', () async {
    final nextDay = DateTime(2026, 9, 19);
    await manager.store.writeCellPair(
      SaveCellPair(
        first: cell(dayNurse, '7A'),
        second: SaveCell(
          staffMemberId: 'day',
          sectionId: 'days',
          date: nextDay,
          shiftCode: '7A',
        ),
        expectedFirstCode: '7A',
        expectedSecondCode: '',
      ),
    );
    final grid = await manager.monthGrid(date);
    expect(grid.shiftCodeFor('day', date), '7A');
    expect(grid.shiftCodeFor('day', nextDay), '7A');
  });
}
