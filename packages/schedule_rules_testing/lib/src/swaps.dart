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
    DateTime requesterDate,
    DateTime colleagueDate,
  ) async {
    requesterDate = _day(requesterDate);
    colleagueDate = _day(colleagueDate);
    final mine = database.shiftCodeFor(actor, requesterDate);
    final theirs = database.shiftCodeFor(colleagueId, colleagueDate);
    final myTarget = database.shiftCodeFor(actor, colleagueDate) ?? '';
    final theirTarget = database.shiftCodeFor(colleagueId, requesterDate) ?? '';
    final swap = Swap(
      id: '${database._swaps.length + 1}',
      requesterId: actor,
      colleagueId: colleagueId,
      requesterDate: requesterDate,
      colleagueDate: colleagueDate,
      requesterCode: mine ?? '',
      colleagueCode: theirs ?? '',
      requesterTargetCode: myTarget,
      colleagueTargetCode: theirTarget,
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
    if (swap.requesterDate == swap.colleagueDate) {
      database._shifts[(swap.requesterId, swap.requesterDate)] =
          swap.colleagueCode;
      database._shifts[(swap.colleagueId, swap.colleagueDate)] =
          swap.requesterCode;
    } else {
      database._shifts[(swap.requesterId, swap.requesterDate)] = 'X';
      database._shifts[(swap.colleagueId, swap.colleagueDate)] = 'X';
      database._shifts[(swap.requesterId, swap.colleagueDate)] =
          swap.colleagueCode;
      database._shifts[(swap.colleagueId, swap.requesterDate)] =
          swap.requesterCode;
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
  requesterDate: swap.requesterDate,
  colleagueDate: swap.colleagueDate,
  requesterCode: swap.requesterCode,
  colleagueCode: swap.colleagueCode,
  requesterTargetCode: swap.requesterTargetCode,
  colleagueTargetCode: swap.colleagueTargetCode,
  status: status,
  reason: reason,
);
