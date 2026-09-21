import 'package:schedule_rules_testing/schedule_rules_testing.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:test/test.dart';

void main() {
  test('Request off removes duplicate dates and sorts them', () async {
    final database = InMemoryScheduleDatabase(
      sections: const [ScheduleSection(id: 'rn', name: 'RN')],
      rows: const [
        ScheduleRow(
          staffMemberId: 'staff',
          displayName: 'Test Staff',
          sectionId: 'rn',
        ),
      ],
    );
    final rules = scheduleRulesInMemory(database, actingAs: 'staff');
    final first = DateTime(2026, 10, 12);
    final second = DateTime(2026, 10, 13);
    final email = await rules.requestOff(
      RequestOffDraft(dates: [second, first, second], reason: 'Family'),
    );
    expect(
      email.body,
      'Test Staff requests off on 2026-10-12, 2026-10-13.\nReason: Family',
    );
    final recorded = (await rules.store.requestsOff(pendingOnly: false)).single;
    expect(recorded.dates, [first, second]);
  });

  test('Request off refuses an empty date selection', () async {
    final database = InMemoryScheduleDatabase(
      sections: const [ScheduleSection(id: 'rn', name: 'RN')],
    );
    final rules = scheduleRulesInMemory(database, actingAs: 'staff');
    expect(
      () => rules.requestOff(const RequestOffDraft(dates: [])),
      throwsArgumentError,
    );
  });
}
