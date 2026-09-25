part of '../schedule_rules.dart';

/// A Swap exchanges two dated Shift codes after both Staff members agree and
/// the Manager approves it.
enum SwapStatus { proposed, accepted, declined, approved }

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
    required this.requesterDate,
    required this.colleagueDate,
    required this.requesterCode,
    required this.colleagueCode,
    required this.requesterTargetCode,
    required this.colleagueTargetCode,
    required this.status,
    this.reason,
  });

  final String id;
  final String requesterId;
  final String colleagueId;
  final DateTime requesterDate;
  final DateTime colleagueDate;
  final String requesterCode;
  final String colleagueCode;
  final String requesterTargetCode;
  final String colleagueTargetCode;
  final SwapStatus status;
  final String? reason;
}

abstract interface class SwapStore {
  Future<List<Swap>> swaps();
  Stream<void> updates();
  Future<String?> colleagueCellNumberForSwap(String swapId);
  Future<Swap> proposeSwap(
    String colleagueId,
    DateTime requesterDate,
    DateTime colleagueDate,
  );
  Future<void> answerSwap(
    String swapId, {
    required bool accept,
    String? reason,
  });
  Future<void> approveSwap(String swapId);
  Future<void> declineSwap(String swapId, {String? reason});
}
