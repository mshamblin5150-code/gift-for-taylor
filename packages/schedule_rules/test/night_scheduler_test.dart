import 'package:schedule_rules_testing/schedule_rules_testing.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:test/test.dart';

void main() {
  const days = ScheduleSection(id: 'days', name: 'State dayshift RN');
  const nights = ScheduleSection(id: 'nights', name: 'PRN nightshift RN');
  const nightCna = ScheduleSection(id: 'night-cna', name: 'Night CNA');
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
  const scheduler = ScheduleRow(
    staffMemberId: 'rn-3',
    displayName: 'Charge RN',
    sectionId: 'nights',
  );
  const nightAide = ScheduleRow(
    staffMemberId: 'cna-1',
    displayName: 'Night CNA',
    sectionId: 'night-cna',
  );
  final september18 = DateTime(2026, 9, 18);
  final september = DateTime(2026, 9);

  late DateTime now;
  late InMemoryScheduleDatabase database;
  late ScheduleRules manager;
  late ScheduleRules nightScheduler;

  setUp(() {
    now = DateTime(2026, 9, 18, 21);
    database = InMemoryScheduleDatabase(
      sections: const [days, nights, nightCna],
      rows: const [dayNurse, nightNurse, scheduler, nightAide],
      grants: {'manager': Grants(manager: true)},
      names: const {'manager': 'The Manager'},
      clock: () => now,
    );
    manager = scheduleRulesInMemory(database, actingAs: 'manager');
    nightScheduler = scheduleRulesInMemory(database, actingAs: 'rn-3');
  });

  Future<void> save(
    ScheduleRules rules,
    ScheduleRow row,
    String code, {
    DateTime? date,
  }) {
    return rules.saveCell(
      SaveCell(
        staffMemberId: row.staffMemberId,
        sectionId: row.sectionId,
        date: date ?? september18,
        shiftCode: code,
      ),
    );
  }

  group('the change log view', () {
    setUp(() async {
      await manager.store.assignNightScheduler('rn-3', {'nights'});
      now = DateTime(2026, 9, 17, 8);
      await save(manager, dayNurse, '7A');
      now = DateTime(2026, 9, 17, 22);
      await save(nightScheduler, nightNurse, 'N');
      now = DateTime(2026, 9, 18, 23, 30);
      await save(nightScheduler, nightNurse, '7P', date: DateTime(2026, 9, 3));
    });

    test('lists every change newest first', () async {
      final log = await manager.changeLogView(september);

      expect(log.map((entry) => entry.newShiftCode), ['7P', 'N', '7A']);
    });

    test('filters by who made the change', () async {
      final log = await manager.changeLogView(september, changedBy: 'rn-3');

      expect(log.map((entry) => entry.newShiftCode), ['7P', 'N']);
    });

    test('filters by the day the change was made', () async {
      final log = await manager.changeLogView(
        september,
        changedOn: DateTime(2026, 9, 17, 15),
      );

      expect(log.map((entry) => entry.newShiftCode), ['N', '7A']);
    });

    test('combines both filters', () async {
      final log = await manager.changeLogView(
        september,
        changedBy: 'manager',
        changedOn: DateTime(2026, 9, 18),
      );

      expect(log, isEmpty);
    });
  });
}
