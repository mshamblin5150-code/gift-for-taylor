import 'package:schedule_rules_testing/schedule_rules_testing.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:test/test.dart';

void main() {
  const days = ScheduleSection(id: 'days', name: 'State dayshift RN');
  const dayNurse = ScheduleRow(
    staffMemberId: 'rn-1',
    displayName: 'Day RN',
    sectionId: 'days',
  );
  final october = DateTime(2026, 10);
  final october1 = DateTime(2026, 10, 1);

  late InMemoryScheduleDatabase database;
  late ScheduleRules manager;

  setUp(() {
    database = InMemoryScheduleDatabase(
      sections: const [days],
      rows: const [dayNurse],
      grants: {'manager': Grants(manager: true)},
    );
    database.loadFromPage(october, [
      ScheduleCell(
        staffMemberId: 'rn-1',
        sectionId: 'days',
        date: october1,
        shiftCode: '4P-8A',
      ),
    ]);
    manager = scheduleRulesInMemory(database, actingAs: 'manager');
  });

  test('the loaded month waits for the Manager to check it', () async {
    final grid = await manager.monthGrid(october);

    expect(
      (await manager.store.monthsAwaitingConfirmation()).firstOrNull,
      october,
    );
    expect(grid.awaitingConfirmation, isTrue);
    expect(grid.shiftCodeFor('rn-1', october1), '4P-8A');
    expect(await manager.changeLog(october), isEmpty);
  });

  test('a correction during review is logged like any other edit', () async {
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'rn-1',
        sectionId: 'days',
        date: october1,
        shiftCode: '7P',
      ),
    );

    final change = (await manager.changeLog(october)).single;
    expect(change.oldShiftCode, '4P-8A');
    expect(change.newShiftCode, '7P');
    expect(change.changedBy, 'manager');
  });

  test('confirming ends the review and leaves no change to announce', () async {
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'rn-1',
        sectionId: 'days',
        date: october1,
        shiftCode: '7P',
      ),
    );

    await manager.store.confirmLoadedMonth(october);

    final grid = await manager.monthGrid(october);
    expect(grid.awaitingConfirmation, isFalse);
    expect(grid.isUnannounced('rn-1', october1), isFalse);
    expect(grid.shiftCodeFor('rn-1', october1), '7P');
    expect(
      (await manager.store.monthsAwaitingConfirmation()).firstOrNull,
      isNull,
    );
  });

  test('only the Manager may confirm the month', () async {
    final staffMember = scheduleRulesInMemory(database, actingAs: 'rn-1');

    await expectLater(
      staffMember.store.confirmLoadedMonth(october),
      throwsA(isA<ScheduleEditRefused>()),
    );
    expect(
      (await manager.store.monthsAwaitingConfirmation()).firstOrNull,
      october,
    );
  });
}
