part of '../schedule_rules.dart';

enum GiveawayStatus {
  proposed,
  accepted,
  declined,
  approved,
  withdrawn,
  voided,
}

enum GiveawayProposalRefusal {
  differentStaffRequired,
  shiftsRequired,
  shiftLimitExceeded,
  duplicateDate,
  colleagueNotInvited,
  dayNotFuture,
  sourceUnavailable,
  colleagueIneligible,
}

final class GiveawayProposalRefused implements Exception {
  const GiveawayProposalRefused(this.reason);
  final GiveawayProposalRefusal reason;
}

final class GiveawayShift {
  const GiveawayShift({
    required this.date,
    required this.shiftCode,
    required this.targetCode,
  });

  final DateTime date;
  final String shiftCode;
  final String targetCode;
}

final class Giveaway {
  const Giveaway({
    required this.id,
    required this.giverId,
    required this.colleagueId,
    required this.shifts,
    required this.status,
    this.reason,
    this.voidedStaffMemberId,
    this.voidedDate,
    this.createsShortfall = false,
  });

  final String id;
  final String giverId;
  final String colleagueId;
  final List<GiveawayShift> shifts;
  final GiveawayStatus status;
  final String? reason;
  final String? voidedStaffMemberId;
  final DateTime? voidedDate;
  final bool createsShortfall;

  DateTime get firstDate =>
      shifts.map((shift) => shift.date).reduce((a, b) => a.isBefore(b) ? a : b);
}

final class GiveawayColleague {
  const GiveawayColleague({
    required this.staffMemberId,
    required this.displayName,
  });
  final String staffMemberId;
  final String displayName;
}

abstract interface class GiveawayStore {
  Future<List<Giveaway>> giveaways();
  Stream<void> updates();
  Future<List<GiveawayColleague>> eligibleColleagues(List<DateTime> dates);
  Future<String?> colleagueCellNumberForGiveaway(String giveawayId);
  Future<Giveaway> proposeGiveaway(String colleagueId, List<DateTime> dates);
  Future<void> answerGiveaway(
    String giveawayId, {
    required bool accept,
    String? reason,
  });
  Future<void> withdrawGiveaway(String giveawayId);
  Future<void> approveGiveaway(String giveawayId);
  Future<void> declineGiveaway(String giveawayId, {String? reason});
}
