import 'package:schedule_rules_testing/schedule_rules_testing.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:test/test.dart';

void main() {
  test('someone who may not edit cannot change the Staff list', () async {
    final restricted = InMemoryScheduleDatabase(
      sections: const [ScheduleSection(id: 'days', name: 'State dayshift RN')],
      rows: const [
        ScheduleRow(staffMemberId: 'rn-1', displayName: 'Day RN', sectionId: 'days'),
        ScheduleRow(staffMemberId: 'rn-2', displayName: 'Second day RN', sectionId: 'days'),
      ],
      editors: const {'manager'},
    );
    final staffMember = scheduleRulesInMemory(restricted, actingAs: 'rn-2');

    await expectLater(
      staffMember.store.setLastDay(
        SetLastDay(staffMemberId: 'rn-1', lastDay: DateTime(2026, 9, 30)),
      ),
      throwsA(isA<ScheduleEditRefused>()),
    );
    await expectLater(
      staffMember.store.changeSection(
        ChangeSection(
          staffMemberId: 'rn-1',
          sectionId: 'days',
          from: DateTime(2026, 9, 30),
        ),
      ),
      throwsA(isA<ScheduleEditRefused>()),
    );
  });
}
