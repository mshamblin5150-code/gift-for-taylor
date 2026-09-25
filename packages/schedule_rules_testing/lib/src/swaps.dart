part of '../schedule_rules_testing.dart';

/// Records Swap writes and seeded Schedule cells for client tests.
final class InMemorySwapDatabase {
  InMemorySwapDatabase({
    required Map<(String, DateTime), String> shifts,
    Map<String, String> cellNumbers = const {},
    List<Swap> swaps = const [],
  }) : _shifts = Map.of(shifts),
       _cellNumbers = Map.of(cellNumbers),
       _swaps = List.of(swaps);

  final Map<(String, DateTime), String> _shifts;
  final Map<String, String> _cellNumbers;
  final List<Swap> _swaps;

  SwapStore storeFor(String staffMemberId) =>
      _InMemorySwapStore(this, staffMemberId);

  String? shiftCodeFor(String staffMemberId, DateTime date) =>
      _shifts[(staffMemberId, _day(date))];
}

final class _InMemorySwapStore implements SwapStore {
  _InMemorySwapStore(this.database, this.actor);

  final InMemorySwapDatabase database;
  final String actor;

  @override
  Future<List<Swap>> swaps() async => List.of(database._swaps);

  @override
  Stream<void> updates() => const Stream<void>.empty();

  @override
  Future<String?> colleagueCellNumberForSwap(String swapId) async {
    final swap = database._swaps.where((item) => item.id == swapId).firstOrNull;
    return swap == null ? null : database._cellNumbers[swap.colleagueId];
  }

  @override
  Future<Swap> proposeSwap(
    String colleagueId,
    List<DateTime> requesterDates,
    List<DateTime> colleagueDates,
  ) async {
    requesterDates = requesterDates.map(_day).toList();
    colleagueDates = colleagueDates.map(_day).toList();
    final swap = Swap(
      id: '${database._swaps.length + 1}',
      requesterId: actor,
      colleagueId: colleagueId,
      requesterShifts: [
        for (final date in requesterDates)
          SwapShift(
            date: date,
            shiftCode: database.shiftCodeFor(actor, date) ?? '',
            targetCode: database.shiftCodeFor(colleagueId, date) ?? '',
          ),
      ],
      colleagueShifts: [
        for (final date in colleagueDates)
          SwapShift(
            date: date,
            shiftCode: database.shiftCodeFor(colleagueId, date) ?? '',
            targetCode: database.shiftCodeFor(actor, date) ?? '',
          ),
      ],
      status: SwapStatus.proposed,
    );
    database._swaps.add(swap);
    return swap;
  }

  @override
  Future<void> answerSwap(
    String swapId, {
    required bool accept,
    String? reason,
  }) async {
    final index = database._swaps.indexWhere((swap) => swap.id == swapId);
    final swap = database._swaps[index];
    database._swaps[index] = _copy(
      swap,
      accept ? SwapStatus.accepted : SwapStatus.declined,
      reason,
    );
  }

  @override
  Future<void> approveSwap(String swapId) async {
    final index = database._swaps.indexWhere((swap) => swap.id == swapId);
    final swap = database._swaps[index];
    for (final shift in swap.requesterShifts) {
      database._shifts[(swap.requesterId, shift.date)] = 'X';
    }
    for (final shift in swap.colleagueShifts) {
      database._shifts[(swap.colleagueId, shift.date)] = 'X';
    }
    for (final shift in swap.colleagueShifts) {
      database._shifts[(swap.requesterId, shift.date)] = shift.shiftCode;
    }
    for (final shift in swap.requesterShifts) {
      database._shifts[(swap.colleagueId, shift.date)] = shift.shiftCode;
    }
    database._swaps[index] = _copy(swap, SwapStatus.approved, swap.reason);
  }

  @override
  Future<void> declineSwap(String swapId, {String? reason}) async {
    final index = database._swaps.indexWhere((swap) => swap.id == swapId);
    database._swaps[index] = _copy(
      database._swaps[index],
      SwapStatus.declined,
      reason,
    );
  }
}

Swap _copy(Swap swap, SwapStatus status, String? reason) => Swap(
  id: swap.id,
  requesterId: swap.requesterId,
  colleagueId: swap.colleagueId,
  requesterShifts: swap.requesterShifts,
  colleagueShifts: swap.colleagueShifts,
  status: status,
  reason: reason,
  voidedStaffMemberId: swap.voidedStaffMemberId,
  voidedDate: swap.voidedDate,
);
