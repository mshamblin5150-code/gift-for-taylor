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

  test('in-memory withdrawal enforces requester and terminal state', () async {
    final date = DateTime(2027, 6, 20);
    Swap swap(String id, SwapStatus status) => Swap(
      id: id,
      requesterId: 'me',
      colleagueId: 'them',
      requesterShifts: [
        SwapShift(date: date, shiftCode: '7A', targetCode: 'X'),
      ],
      colleagueShifts: [
        SwapShift(date: date, shiftCode: '7P', targetCode: 'X'),
      ],
      status: status,
    );
    final database = InMemorySwapDatabase(
      shifts: const {},
      swaps: [
        swap('accepted', SwapStatus.accepted),
        swap('approved', SwapStatus.approved),
      ],
    );

    await expectLater(
      database.storeFor('them').withdrawSwap('accepted'),
      throwsStateError,
    );
    await expectLater(
      database.storeFor('me').withdrawSwap('approved'),
      throwsStateError,
    );
    await database.storeFor('me').withdrawSwap('accepted');

    final swaps = await database.storeFor('me').swaps();
    expect(
      swaps.singleWhere((swap) => swap.id == 'accepted').status,
      SwapStatus.withdrawn,
    );
    expect(
      swaps.singleWhere((swap) => swap.id == 'approved').status,
      SwapStatus.approved,
    );
  });

  test('approval reports pickup eligibility refusal', () async {
    final store = _RefusingApprovalStore();
    final session = SwapsSession(
      rules: scheduleRulesInMemory(
        InMemoryScheduleDatabase(sections: const []),
        actingAs: 'manager',
      ),
      swapStore: store,
      month: DateTime(2027, 6),
    );
    addTearDown(session.dispose);

    final outcome = await session.approve('swap');

    expect(outcome, isA<SwapsWriteRefused>());
    expect(
      (outcome as SwapsWriteRefused).reason,
      SwapProposalRefusal.pickupIneligible,
    );
  });
}

final class _RefusingApprovalStore extends Fake implements SwapStore {
  @override
  Stream<void> updates() => const Stream.empty();

  @override
  Future<List<Swap>> swaps() async => const [];

  @override
  Future<void> approveSwap(String swapId) =>
      throw const SwapProposalRefused(SwapProposalRefusal.pickupIneligible);
}
