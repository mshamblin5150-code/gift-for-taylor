import 'package:schedule_rules/schedule_rules.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Manager can save a Shift code and read it from the month grid',
    () async {
      final rules = ScheduleRules.inMemory(
        sections: const [
          ScheduleSection(id: 'days', name: 'State dayshift RN'),
        ],
      );
      const staffMemberId = 'staff-1';
      final date = DateTime(2026, 9, 18);

      await rules.saveCell(
        SaveCell(
          staffMemberId: staffMemberId,
          sectionId: 'days',
          date: date,
          shiftCode: '7A',
        ),
      );

      final grid = await rules.monthGrid(DateTime(2026, 9));

      expect(grid.shiftCodeFor(staffMemberId, date), '7A');
      expect(grid.sections.single.name, 'State dayshift RN');
    },
  );
}
