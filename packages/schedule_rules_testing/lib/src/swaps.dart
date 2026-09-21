part of '../schedule_rules_testing.dart';

/// Small in-memory counterpart of the Swap transaction for schedule rules tests.
final class InMemorySwapDatabase {
  InMemorySwapDatabase({
    required this.managerId,
    required Map<(String, DateTime), String> shifts,
    this.shiftCodes = shiftLegend,
  }) : _shifts = Map.of(shifts);

  final String managerId;
  final Map<(String, DateTime), String> _shifts;
  final List<LegendCode> shiftCodes;
  final List<Swap> _swaps = [];

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
  Future<List<Swap>> swaps() async => [
    for (final swap in database._swaps)
      if (actor == database.managerId ||
          swap.requesterId == actor ||
          swap.colleagueId == actor)
        swap,
  ];

  @override
  Stream<void> updates() => const Stream<void>.empty();

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
    if (actor == colleagueId ||
        !isWorkingShift(mine ?? '', codes: database.shiftCodes) ||
        !isWorkingShift(theirs ?? '', codes: database.shiftCodes) ||
        (requesterDate == colleagueDate && mine == theirs) ||
        (requesterDate != colleagueDate &&
            (!_free(myTarget) || !_free(theirTarget)))) {
      throw StateError('Choose two working shifts that change the Schedule');
    }
    final swap = Swap(
      id: '${database._swaps.length + 1}',
      requesterId: actor,
      colleagueId: colleagueId,
      requesterDate: requesterDate,
      colleagueDate: colleagueDate,
      requesterCode: mine!,
      colleagueCode: theirs!,
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
    if (index < 0 ||
        database._swaps[index].colleagueId != actor ||
        database._swaps[index].status != SwapStatus.proposed) {
      throw StateError('This Swap cannot be answered');
    }
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
    if (actor != database.managerId ||
        index < 0 ||
        database._swaps[index].status != SwapStatus.accepted) {
      throw StateError('This Swap is not awaiting Manager approval');
    }
    final swap = database._swaps[index];
    if (database.shiftCodeFor(swap.requesterId, swap.requesterDate) !=
            swap.requesterCode ||
        database.shiftCodeFor(swap.colleagueId, swap.colleagueDate) !=
            swap.colleagueCode ||
        (swap.requesterDate != swap.colleagueDate &&
            ((database.shiftCodeFor(swap.requesterId, swap.colleagueDate) ??
                        '') !=
                    swap.requesterTargetCode ||
                (database.shiftCodeFor(swap.colleagueId, swap.requesterDate) ??
                        '') !=
                    swap.colleagueTargetCode))) {
      throw StateError('A Shift code changed; propose a new Swap');
    }
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
    if (actor != database.managerId ||
        index < 0 ||
        database._swaps[index].status != SwapStatus.accepted) {
      throw StateError('This Swap is not awaiting Manager approval');
    }
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

bool _free(String code) => code.isEmpty || code == 'X';
