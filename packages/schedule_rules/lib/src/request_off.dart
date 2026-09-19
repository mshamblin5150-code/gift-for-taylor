part of '../schedule_rules.dart';

enum RequestOffDecision { pending, approved, declined }

final class RequestOffDraft {
  const RequestOffDraft({required this.dates, this.reason});
  final List<DateTime> dates;
  final String? reason;
}

final class RequestOffEmail {
  const RequestOffEmail({
    required this.requestId,
    required this.to,
    required this.subject,
    required this.body,
  });
  factory RequestOffEmail.forRequest({
    required String requestId,
    required String to,
    required String staffMemberName,
    required List<DateTime> dates,
    String? reason,
  }) {
    final days = dates.map(_dateText).join(', ');
    final why = reason == null || reason.isEmpty ? '' : '\nReason: $reason';
    return RequestOffEmail(
      requestId: requestId,
      to: to,
      subject: 'Request off - $staffMemberName',
      body: '$staffMemberName requests off on $days.$why',
    );
  }
  final String requestId;
  final String to;
  final String subject;
  final String body;
}

final class RequestOff {
  const RequestOff({
    required this.id,
    required this.staffMemberId,
    required this.staffMemberName,
    required this.dates,
    required this.reason,
    required this.submittedAt,
    required this.emailConfirmedAt,
    required this.decision,
    required this.decisionReason,
    required this.decidedAt,
  });

  final String id;
  final String staffMemberId;
  final String staffMemberName;
  final List<DateTime> dates;
  final String? reason;
  final DateTime submittedAt;
  final DateTime? emailConfirmedAt;
  final RequestOffDecision decision;
  final String? decisionReason;
  final DateTime? decidedAt;

  bool get emailCopyConfirmed => emailConfirmedAt != null;

  RequestOff withEmailConfirmed(DateTime at) => RequestOff(
    id: id,
    staffMemberId: staffMemberId,
    staffMemberName: staffMemberName,
    dates: dates,
    reason: reason,
    submittedAt: submittedAt,
    emailConfirmedAt: at,
    decision: decision,
    decisionReason: decisionReason,
    decidedAt: decidedAt,
  );

  RequestOff withDecision(RequestOffDecision value, String? why, DateTime at) =>
      RequestOff(
        id: id,
        staffMemberId: staffMemberId,
        staffMemberName: staffMemberName,
        dates: dates,
        reason: reason,
        submittedAt: submittedAt,
        emailConfirmedAt: emailConfirmedAt,
        decision: value,
        decisionReason: why,
        decidedAt: at,
      );
}
