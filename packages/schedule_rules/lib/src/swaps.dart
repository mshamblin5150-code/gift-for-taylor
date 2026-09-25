part of '../schedule_rules.dart';

/// A Swap exchanges two sets of dated Shift codes after both Staff members
/// agree and the Manager approves it.
enum SwapStatus { proposed, accepted, declined, approved, voided }

enum SwapProposalRefusal {
  differentStaffRequired,
  equalCountsRequired,
  shiftLimitExceeded,
  duplicateDate,
  colleagueNotInvited,
  dayNotFuture,
  sourceUnavailable,
  destinationUnavailable,
  noChange,
}

final class SwapProposalRefused implements Exception {
  const SwapProposalRefused(this.reason);

  final SwapProposalRefusal reason;
}

final class SwapShift {
  const SwapShift({
    required this.date,
    required this.shiftCode,
    required this.targetCode,
  });

  final DateTime date;
  final String shiftCode;
  final String targetCode;
}

/// The first day that can be offered in a Swap proposed at [now].
DateTime firstFutureSwapDay(DateTime now) =>
    DateTime(now.year, now.month, now.day + 1);

/// Whether [date] is far enough in the future to offer in a Swap at [now].
bool isFutureSwapDay(DateTime date, {required DateTime now}) => !DateTime(
  date.year,
  date.month,
  date.day,
).isBefore(firstFutureSwapDay(now));

final class Swap {
  const Swap({
    required this.id,
    required this.requesterId,
    required this.colleagueId,
    required this.requesterShifts,
    required this.colleagueShifts,
    required this.status,
    this.reason,
    this.voidedStaffMemberId,
    this.voidedDate,
  });

  final String id;
  final String requesterId;
  final String colleagueId;
  final List<SwapShift> requesterShifts;
  final List<SwapShift> colleagueShifts;
  final SwapStatus status;
  final String? reason;
  final String? voidedStaffMemberId;
  final DateTime? voidedDate;

  DateTime get firstDate => [
    ...requesterShifts,
    ...colleagueShifts,
  ].map((shift) => shift.date).reduce((a, b) => a.isBefore(b) ? a : b);
}

abstract interface class SwapStore {
  Future<List<Swap>> swaps();
  Stream<void> updates();
  Future<String?> colleagueCellNumberForSwap(String swapId);
  Future<Swap> proposeSwap(
    String colleagueId,
    List<DateTime> requesterDates,
    List<DateTime> colleagueDates,
  );
  Future<void> answerSwap(
    String swapId, {
    required bool accept,
    String? reason,
  });
  Future<void> approveSwap(String swapId);
  Future<void> declineSwap(String swapId, {String? reason});
}
