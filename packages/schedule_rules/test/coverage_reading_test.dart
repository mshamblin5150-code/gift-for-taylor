import 'package:schedule_rules/schedule_rules.dart';
import 'package:test/test.dart';

void main() {
  final month = DateTime(2026, 10);
  final third = DateTime(2026, 10, 3);
  final ninth = DateTime(2026, 10, 9);
  final fourteenth = DateTime(2026, 10, 14);

  Future<MonthGrid> grid() => ScheduleRules.inMemory(
    InMemoryScheduleDatabase(sections: const []),
    actingAs: 'manager',
  ).monthGrid(month);

  SectionStaffing staffing({
    CoveragePool pool = CoveragePool.nurses,
    CoverageWindow window = CoverageWindow.day,
    required DateTime date,
    int? minimum,
    int onFloor = 0,
    int shortfall = 0,
    int floorShortfall = 0,
    int open = 0,
    JobRole? floorRole = JobRole.rn,
  }) => SectionStaffing(
    pool: pool,
    coverageWindow: window,
    date: date,
    minimum: minimum,
    rnFloor: null,
    workingCount: onFloor,
    rnCount: 0,
    openCount: open,
    rnOpenCount: 0,
    shortCount: minimum == null ? null : shortfall,
    rnShortCount: minimum == null ? null : floorShortfall,
    unpostedCount: minimum == null ? null : shortfall - open,
    floorRole: floorRole,
  );

  test('visible pools require a minimum or Open shift', () async {
    final empty = CoverageReading(await grid(), [staffing(date: third)]);
    expect(empty.visiblePools, isEmpty);
    expect(empty.dayPools(third), [CoveragePool.nurses]);

    final dated = CoverageReading(await grid(), [
      staffing(date: third, minimum: 2, onFloor: 2),
    ]);
    expect(dated.visiblePools, [CoveragePool.nurses]);
    expect(dated.day(CoveragePool.nurses, third).state, CoverageState.covered);
    expect(dated.day(CoveragePool.nurses, ninth).state, CoverageState.notSet);

    final opened = CoverageReading(await grid(), [
      staffing(date: fourteenth, open: 1),
    ]);
    expect(opened.visiblePools, [CoveragePool.nurses]);
  });

  test('band sums Shortfall across windows and compares Open shifts', () async {
    final reading = CoverageReading(await grid(), [
      staffing(date: third, minimum: 3, shortfall: 2, open: 1),
      staffing(
        date: third,
        window: CoverageWindow.night,
        minimum: 2,
        shortfall: 1,
        open: 1,
      ),
      staffing(date: ninth, minimum: 0, open: 4),
    ]);
    expect(reading.day(CoveragePool.nurses, third).bandNumber, 3);
    expect(reading.day(CoveragePool.nurses, third).state, CoverageState.short);
    expect(reading.day(CoveragePool.nurses, ninth).bandNumber, 4);
    expect(reading.day(CoveragePool.nurses, ninth).state, CoverageState.short);
  });

  test('summaries retain the floor within a mixed Shortfall', () async {
    final reading = CoverageReading(await grid(), [
      staffing(
        date: third,
        minimum: 3,
        onFloor: 1,
        shortfall: 2,
        floorShortfall: 1,
      ),
      staffing(date: ninth, minimum: 1, shortfall: 1, floorShortfall: 1),
      staffing(
        date: fourteenth,
        minimum: 1,
        shortfall: 1,
        floorShortfall: 0,
        floorRole: null,
      ),
    ]);
    expect(
      reading
          .day(CoveragePool.nurses, third)
          .window(CoverageWindow.day)
          .summary,
      'Short 2 nursing, 1 RN',
    );
    expect(
      reading
          .day(CoveragePool.nurses, ninth)
          .window(CoverageWindow.day)
          .summary,
      'Short 1 RN',
    );
    expect(
      reading
          .day(CoveragePool.nurses, fourteenth)
          .window(CoverageWindow.day)
          .summary,
      'Short 1 nursing',
    );
    expect(
      reading
          .day(CoveragePool.nurses, third)
          .window(CoverageWindow.night)
          .summary,
      'not set',
    );
  });

  test(
    'Open shift without a minimum is short without acknowledgement',
    () async {
      final reading = CoverageReading(await grid(), [
        staffing(date: fourteenth, open: 1),
      ]);
      expect(
        reading.day(CoveragePool.nurses, fourteenth).state,
        CoverageState.short,
      );
      expect(reading.shortfallDays, isEmpty);
      expect(reading.openShiftDays, [fourteenth]);
    },
  );

  test(
    'a day with Shortfall and Open shift appears only as Shortfall',
    () async {
      final reading = CoverageReading(await grid(), [
        staffing(date: third, minimum: 2, shortfall: 1, open: 1),
      ]);
      expect(reading.shortfallDays, [third]);
      expect(reading.openShiftDays, isEmpty);
    },
  );

  test(
    'fresh staffing takes precedence over an older grid Open shift',
    () async {
      final database = InMemoryScheduleDatabase(
        sections: const [],
        releasedMonths: {month},
      );
      await OpenShiftRules(database.openShiftStoreFor('manager'))
          .postOpenShifts(fourteenth, '7A', CoveragePool.nurses, 1);
      final olderGrid = await ScheduleRules.inMemory(
        database,
        actingAs: 'manager',
      ).monthGrid(month);
      final reading = CoverageReading(olderGrid, [
        staffing(date: fourteenth, minimum: 0, open: 0),
      ]);
      expect(reading.openShiftDays, isEmpty);
      expect(reading.day(CoveragePool.nurses, fourteenth).bandNumber, 0);
    },
  );

  test('reading trusts supplied server Shortfall over raw counts', () async {
    final reading = CoverageReading(await grid(), [
      staffing(date: third, minimum: 4, onFloor: 0, shortfall: 0),
    ]);
    expect(reading.day(CoveragePool.nurses, third).bandNumber, 0);
    expect(
      reading.day(CoveragePool.nurses, third).state,
      CoverageState.covered,
    );
    expect(reading.shortfallDays, isEmpty);
  });
}
