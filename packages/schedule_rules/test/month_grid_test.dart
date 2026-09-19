import 'package:schedule_rules/schedule_rules.dart';
import 'package:test/test.dart';

void main() {
  const days = ScheduleSection(id: 'days', name: 'State dayshift RN');
  const nights = ScheduleSection(id: 'nights', name: 'State nightshift RN');

  ScheduleCell cell(String staffMemberId, String sectionId, int day, String code) {
    return ScheduleCell(
      staffMemberId: staffMemberId,
      sectionId: sectionId,
      date: DateTime(2026, 10, day),
      shiftCode: code,
    );
  }

  test('rows follow the Staff list order within each Section', () {
    final grid = MonthGrid.arrange(
      month: DateTime(2026, 10),
      sections: const [days, nights],
      cells: [
        cell('b', 'days', 1, '7A'),
        cell('a', 'days', 1, 'X'),
        cell('n', 'nights', 1, 'N'),
      ],
      staff: [
        StaffPlacement(
          staffMemberId: 'a',
          displayName: 'First Nurse',
          sectionId: 'days',
          displayOrder: 0,
          effectiveFrom: DateTime(2026, 10),
        ),
        StaffPlacement(
          staffMemberId: 'b',
          displayName: 'Second Nurse',
          sectionId: 'days',
          displayOrder: 1,
          effectiveFrom: DateTime(2026, 10),
        ),
        StaffPlacement(
          staffMemberId: 'n',
          displayName: 'Night Nurse',
          sectionId: 'nights',
          displayOrder: 0,
          effectiveFrom: DateTime(2026, 10),
        ),
      ],
    );

    expect(grid.rowsIn('days').map((row) => row.displayName), [
      'First Nurse',
      'Second Nurse',
    ]);
    expect(grid.rowsIn('nights').single.displayName, 'Night Nurse');
    expect(grid.shiftCodeFor('b', DateTime(2026, 10, 1)), '7A');
  });

  test('a person with cells keeps the Section their cells were in', () {
    final grid = MonthGrid.arrange(
      month: DateTime(2026, 10),
      sections: const [days, nights],
      cells: [cell('moved', 'days', 1, '7A')],
      staff: [
        StaffPlacement(
          staffMemberId: 'moved',
          displayName: 'Moved Nurse',
          sectionId: 'nights',
          displayOrder: 0,
          effectiveFrom: DateTime(2026, 11),
        ),
      ],
    );

    expect(grid.rowsIn('days').single.displayName, 'Moved Nurse');
    expect(grid.rowsIn('nights'), isEmpty);
  });

  test('a current Staff member without cells gets an empty row', () {
    final grid = MonthGrid.arrange(
      month: DateTime(2026, 10),
      sections: const [days],
      cells: const [],
      staff: [
        StaffPlacement(
          staffMemberId: 'new',
          displayName: 'New Nurse',
          sectionId: 'days',
          displayOrder: 0,
          effectiveFrom: DateTime(2026, 10, 20),
        ),
        StaffPlacement(
          staffMemberId: 'later',
          displayName: 'Later Nurse',
          sectionId: 'days',
          displayOrder: 1,
          effectiveFrom: DateTime(2026, 11, 1),
        ),
      ],
    );

    expect(grid.rowsIn('days').single.displayName, 'New Nurse');
    expect(grid.shiftCodeFor('new', DateTime(2026, 10, 20)), isNull);
  });
}
