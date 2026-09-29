abstract interface class Refusal {
  String get code;
}

enum MonthStartRefusal implements Refusal {
  alreadyStarted('P2791'),
  previousMonthNotStarted('P2792');

  const MonthStartRefusal(this.code);
  @override
  final String code;
}

enum InviteLinkRefusal implements Refusal {
  alreadyLinked('P2793'),
  invalid('P2794');

  const InviteLinkRefusal(this.code);
  @override
  final String code;
}

enum SectionRefusal implements Refusal {
  staffMembersAssigned('P2795'),
  scheduleHistory('P2849');

  const SectionRefusal(this.code);
  @override
  final String code;
}

enum ShiftCodeRefusal implements Refusal {
  inUse('P2796');

  const ShiftCodeRefusal(this.code);
  @override
  final String code;
}

enum ManagerHandoverRefusal implements Refusal {
  managerAccessChanged('P2797'),
  noActiveManager('P2798'),
  sameStaffMember('P2799'),
  retainedSectionMissing('P2800'),
  successorNoAccount('P2801'),
  successorInvitePending('P2802'),
  successorAccountRevoked('P2803'),
  successorInactive('P2804'),
  successorAlreadyManager('P2805'),
  successorNoCurrentSection('P2806');

  const ManagerHandoverRefusal(this.code);
  @override
  final String code;
}

enum InviteAcceptanceRefusal implements Refusal {
  staffAcceptancePending('P2807'),
  staffAlreadyAccepted('P2808'),
  emailAcceptancePending('P2809'),
  accountMissingEmail('P2810');

  const InviteAcceptanceRefusal(this.code);
  @override
  final String code;
}

enum CallInRefusal implements Refusal {
  recorderNotWorking('P2811'),
  targetNotWorking('P2812'),
  settled('P2813'),
  notRecorded('P2848');

  const CallInRefusal(this.code);
  @override
  final String code;
}

enum SwapProposalRefusal implements Refusal {
  differentStaffRequired('P2814'),
  equalCountsRequired('P2815'),
  shiftLimitExceeded('P2816'),
  duplicateDate('P2817'),
  colleagueNotInvited('P2818'),
  dayNotFuture('P2819'),
  sourceUnavailable('P2820'),
  destinationUnavailable('P2821'),
  noChange('P2822'),
  pickupIneligible('P2846');

  const SwapProposalRefusal(this.code);
  @override
  final String code;
}

enum GiveawayProposalRefusal implements Refusal {
  differentStaffRequired('P2823'),
  shiftsRequired('P2824'),
  shiftLimitExceeded('P2825'),
  duplicateDate('P2826'),
  colleagueNotInvited('P2827'),
  dayNotFuture('P2828'),
  sourceUnavailable('P2829'),
  colleagueIneligible('P2830');

  const GiveawayProposalRefusal(this.code);
  @override
  final String code;
}

enum TicketSubmissionRefusal implements Refusal {
  staffAccountRequired('P2831'),
  textInvalid('P2832'),
  contextIncomplete('P2833'),
  tooManyRecently('P2845');

  const TicketSubmissionRefusal(this.code);
  @override
  final String code;
}

enum TicketUnavailable implements Refusal {
  ticketNotFound('P2834'),
  threadEntryNotFound('P2847');

  const TicketUnavailable(this.code);
  @override
  final String code;
}

enum TicketMutationRefusal implements Refusal {
  invalidGitHubIssue('P2835'),
  closingReasonRequired('P2836'),
  cannotClose('P2837'),
  reopeningNoteRequired('P2838'),
  cannotReopen('P2839'),
  reopenExpired('P2840');

  const TicketMutationRefusal(this.code);
  @override
  final String code;
}

enum TicketThreadRefusal implements Refusal {
  questionInvalid('P2841'),
  ticketNotReady('P2842'),
  answerInvalid('P2843'),
  questionNotWaiting('P2844');

  const TicketThreadRefusal(this.code);
  @override
  final String code;
}

final class Refused implements Exception {
  const Refused(this.refusal);

  final Refusal refusal;
}

const knownRefusals = <Refusal>[
  ...MonthStartRefusal.values,
  ...InviteLinkRefusal.values,
  ...SectionRefusal.values,
  ...ShiftCodeRefusal.values,
  ...ManagerHandoverRefusal.values,
  ...InviteAcceptanceRefusal.values,
  ...CallInRefusal.values,
  ...SwapProposalRefusal.values,
  ...GiveawayProposalRefusal.values,
  ...TicketSubmissionRefusal.values,
  ...TicketUnavailable.values,
  ...TicketMutationRefusal.values,
  ...TicketThreadRefusal.values,
];

const retiredRefusalCodes = <String>{};

Refusal? refusalFor(String? code) {
  for (final refusal in knownRefusals) {
    if (refusal.code == code) return refusal;
  }
  return null;
}
