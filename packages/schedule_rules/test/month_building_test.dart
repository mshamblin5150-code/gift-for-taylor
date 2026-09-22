import 'package:schedule_rules_testing/schedule_rules_testing.dart';
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

  late InMemoryScheduleDatabase database;
  late ScheduleRules manager;

  setUp(() {
    database = InMemoryScheduleDatabase(
      sections: const [days, nights],
      rows: const [dayNurse, nightNurse],
      grants: {'manager': Grants(manager: true)},
    );
    manager = scheduleRulesInMemory(database, actingAs: 'manager');
  });

  Future<void> save(ScheduleRow row, DateTime date, String code) {
    return manager.saveCell(
      SaveCell(
        staffMemberId: row.staffMemberId,
        sectionId: row.sectionId,
        date: date,
        shiftCode: code,
      ),
    );
  }

  /// Fills every day of [month] for the Day RN with a code naming its date.
  Future<void> fillWithDates(DateTime month) async {
    final last = DateTime(month.year, month.month + 1, 0).day;
    for (var day = 1; day <= last; day++) {
      await save(dayNurse, DateTime(month.year, month.month, day), '$day');
    }
  }

  /// The source day each day of [next] was copied from.
  Future<List<int>> copiedFrom(DateTime next) async {
    final grid = await manager.monthGrid(next);
    return [
      for (final day in grid.days)
        int.parse(grid.shiftCodeFor('rn-1', day) ?? '0'),
    ];
  }

  group('Start next month', () {
    test('copies each day from the same weekday of the same week', () async {
      // October 2026 has 31 days from a Thursday; November 2026 has 30 from
      // a Sunday.
      await fillWithDates(DateTime(2026, 10));

      await manager.startNextMonth(DateTime(2026, 10));

      final sources = await copiedFrom(DateTime(2026, 11));
      expect(sources.take(7), [4, 5, 6, 7, 8, 9, 10]);
      expect(sources.sublist(28), [4 + 28 - 7, 5 + 28 - 7]);
      for (final (index, source) in sources.indexed) {
        expect(
          DateTime(2026, 10, source).weekday,
          DateTime(2026, 11, index + 1).weekday,
        );
      }
    });

    test('a fifth week repeats the fourth after a four-week month', () async {
      // February 2027 is exactly four weeks from a Monday; March 2027 has 31
      // days from a Monday.
      await fillWithDates(DateTime(2027, 2));

      await manager.startNextMonth(DateTime(2027, 2));

      final sources = await copiedFrom(DateTime(2027, 3));
      expect(sources.take(28), List.generate(28, (index) => index + 1));
      expect(sources.sublist(28), [22, 23, 24]);
    });

    test('a shorter month drops the last days of a longer one', () async {
      // January 2027 has 31 days from a Friday; February 2027 has 28 from a
      // Monday.
      await fillWithDates(DateTime(2027, 1));

      await manager.startNextMonth(DateTime(2027, 1));

      final sources = await copiedFrom(DateTime(2027, 2));
      expect(sources, List.generate(28, (index) => index + 4));
    });

    test('rolls over the year', () async {
      // December 2026 has 31 days from a Tuesday; January 2027 has 31 from a
      // Friday.
      await fillWithDates(DateTime(2026, 12));

      await manager.startNextMonth(DateTime(2026, 12));

      final sources = await copiedFrom(DateTime(2027, 1));
      expect(sources.take(3), [4, 5, 6]);
      expect(sources.sublist(28), [4 + 21, 5 + 21, 6 + 21]);
      for (final (index, source) in sources.indexed) {
        expect(
          DateTime(2026, 12, source).weekday,
          DateTime(2027, 1, index + 1).weekday,
        );
      }
    });

    test('clears R/O, H, S/L and A/L and keeps other codes', () async {
      // November 2 2026 is copied from October 5, and so on.
      await save(dayNurse, DateTime(2026, 10, 5), 'R/O');
      await save(dayNurse, DateTime(2026, 10, 6), ' h ');
      await save(dayNurse, DateTime(2026, 10, 7), 'S/L');
      await save(dayNurse, DateTime(2026, 10, 8), 'a/l');
      await save(dayNurse, DateTime(2026, 10, 9), '4P-8A');
      await save(nightNurse, DateTime(2026, 10, 5), 'N');
      await save(nightNurse, DateTime(2026, 10, 6), 'X');

      await manager.startNextMonth(DateTime(2026, 10));

      final grid = await manager.monthGrid(DateTime(2026, 11));
      String code(ScheduleRow row, int day) =>
          grid.shiftCodeFor(row.staffMemberId, DateTime(2026, 11, day)) ?? '';
      expect(
        [for (var day = 2; day <= 6; day++) code(dayNurse, day)],
        ['', '', '', '', '4P-8A'],
      );
      expect(code(nightNurse, 2), 'N');
      expect(code(nightNurse, 3), 'X');
    });
  });
}
