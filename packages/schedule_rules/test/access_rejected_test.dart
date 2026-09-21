import 'package:schedule_rules_testing/schedule_rules_testing.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:test/test.dart';

void main() {
  test('the next in-memory write fails once with the injected error', () async {
    final database = InMemoryScheduleDatabase(
      sections: const [ScheduleSection(id: 'days', name: 'Days')],
      rows: const [
        ScheduleRow(
          staffMemberId: 'nurse',
          displayName: 'Nurse',
          sectionId: 'days',
        ),
      ],
      grants: {'manager': Grants(manager: true)},
    );
    final manager = scheduleRulesInMemory(database, actingAs: 'manager');
    final action = SaveCell(
      staffMemberId: 'nurse',
      sectionId: 'days',
      date: DateTime(2026, 9, 21),
      shiftCode: '7A',
    );
    const rejected = AccessRejected();
    database.failNext(InMemoryStoreCall.writeCell, rejected);

    await expectLater(manager.saveCell(action), throwsA(same(rejected)));
    await manager.saveCell(action);

    final grid = await manager.monthGrid(DateTime(2026, 9));
    expect(grid.shiftCodeFor('nurse', action.date), '7A');
  });
}
