import 'package:er_schedule/schedule/swaps_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:schedule_rules_testing/schedule_rules_testing.dart';

void main() {
  test('session owns the Swaps read and proposal command', () async {
    final month = DateTime(2027, 6);
    final mine = DateTime(2027, 6, 20);
    final theirs = DateTime(2027, 6, 21);
    final schedule = InMemoryScheduleDatabase(
      sections: const [ScheduleSection(id: 'unit', name: 'Unit')],
      rows: const [
        ScheduleRow(staffMemberId: 'me', displayName: 'Me', sectionId: 'unit'),
        ScheduleRow(
          staffMemberId: 'them',
          displayName: 'Them',
          sectionId: 'unit',
        ),
      ],
      releasedMonths: {month},
    );
    final swaps = InMemorySwapDatabase(
      shifts: {('me', mine): '7A', ('them', theirs): '7P'},
    );
    final session = SwapsSession(
      rules: scheduleRulesInMemory(schedule, actingAs: 'me'),
      swapStore: swaps.storeFor('me'),
      month: month,
    );
    addTearDown(session.dispose);

    await session.refresh();
    expect(session.state.grid?.month, month);
    expect(session.state.swaps, isEmpty);

    final outcome = await session.propose('them', [mine], [theirs]);

    expect(outcome, isA<SwapsProposed>());
    expect(session.state.busy, isFalse);
    expect(session.state.swaps.single.requesterShifts.single.date, mine);
  });
}
