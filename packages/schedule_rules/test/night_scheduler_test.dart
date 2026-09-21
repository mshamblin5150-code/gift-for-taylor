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
      editors: const {'manager'},
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

  test('a Staff member edits nothing until given the role', () async {
    expect(database.accessFor('rn-3').editableSections.isEmpty, isTrue);
    await expectLater(
      save(nightScheduler, nightNurse, 'N'),
      throwsA(isA<ScheduleEditRefused>()),
    );
  });

  test('the Manager edits every Section', () async {
    final editable = database.accessFor('manager').editableSections;

    expect(editable.contains('days'), isTrue);
    expect(editable.contains('night-cna'), isTrue);
  });

  test('the Manager gives the role with chosen Sections', () async {
    await manager.store.assignNightScheduler('rn-3', {'nights', 'night-cna'});

    expect(await manager.store.nightSchedulers(), [
      isA<NightScheduler>()
          .having((it) => it.staffMemberId, 'staffMemberId', 'rn-3')
          .having((it) => it.sectionIds, 'sectionIds', {'nights', 'night-cna'}),
    ]);
    final editable = database.accessFor('rn-3').editableSections;
    expect(editable.contains('nights'), isTrue);
    expect(editable.contains('night-cna'), isTrue);
    expect(editable.contains('days'), isFalse);
  });

  test('the Night scheduler edits only assigned Sections', () async {
    await manager.store.assignNightScheduler('rn-3', {'nights'});

    await save(nightScheduler, nightNurse, 'N');
    await expectLater(
      save(nightScheduler, dayNurse, 'X'),
      throwsA(isA<ScheduleEditRefused>()),
    );
    await expectLater(
      save(nightScheduler, nightAide, 'N'),
      throwsA(isA<ScheduleEditRefused>()),
    );

    final grid = await manager.monthGrid(september);
    expect(grid.shiftCodeFor('rn-2', september18), 'N');
    expect(grid.shiftCodeFor('rn-1', september18), isNull);
  });

  test('a Night scheduler edit is live, unannounced and logged under their '
      'name', () async {
    await manager.store.assignNightScheduler('rn-3', {'nights'});

    await save(nightScheduler, nightNurse, '7P');

    final grid = await manager.monthGrid(september);
    expect(grid.shiftCodeFor('rn-2', september18), '7P');
    expect(grid.isUnannounced('rn-2', september18), isTrue);
    final entry = (await manager.changeLog(september)).single;
    expect(entry.changedBy, 'rn-3');
    expect(entry.changedByName, 'Charge RN');
    expect(entry.changedAt, now);
  });

  test('the Night scheduler cannot confirm or hand out the role', () async {
    await manager.store.assignNightScheduler('rn-3', {'nights'});

    expect(database.accessFor('rn-3').canRunSchedule, isFalse);
    await expectLater(
      nightScheduler.store.assignNightScheduler('rn-2', {'nights'}),
      throwsA(isA<ScheduleEditRefused>()),
    );
  });

  test('the Manager overrides a Night scheduler edit', () async {
    await manager.store.assignNightScheduler('rn-3', {'nights'});
    await save(nightScheduler, nightNurse, '7P');

    await save(manager, nightNurse, 'N');

    final grid = await manager.monthGrid(september);
    expect(grid.shiftCodeFor('rn-2', september18), 'N');
    final log = await manager.changeLog(september);
    expect(log.map((entry) => entry.changedByName), [
      'Charge RN',
      'The Manager',
    ]);
    expect(log.last.oldShiftCode, '7P');
  });

  test('changing the Sections replaces them', () async {
    await manager.store.assignNightScheduler('rn-3', {'nights', 'night-cna'});

    await manager.store.assignNightScheduler('rn-3', {'night-cna'});

    final editable = database.accessFor('rn-3').editableSections;
    expect(editable.contains('nights'), isFalse);
    expect(editable.contains('night-cna'), isTrue);
  });

  test('the role needs at least one Section', () async {
    await expectLater(
      manager.store.assignNightScheduler('rn-3', {}),
      throwsArgumentError,
    );
  });

  test('removing the role stops their edits', () async {
    await manager.store.assignNightScheduler('rn-3', {'nights'});

    await manager.store.removeNightScheduler('rn-3');

    expect(await manager.store.nightSchedulers(), isEmpty);
    await expectLater(
      save(nightScheduler, nightNurse, 'N'),
      throwsA(isA<ScheduleEditRefused>()),
    );
  });

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
