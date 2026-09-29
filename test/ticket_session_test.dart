import 'dart:async';

import 'package:er_schedule/tickets/ticket_gateway.dart';
import 'package:er_schedule/tickets/ticket_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'support/tickets.dart';

final class _ReopenTimer implements Timer {
  _ReopenTimer(this.callback);

  final void Function() callback;
  bool cancelled = false;

  void fire() {
    if (!cancelled) callback();
  }

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}

void main() {
  final context = TicketContext(
    screen: 'Schedule',
    month: DateTime(2026, 9),
    release: 'abc1234',
    device: 'Chrome on Windows',
    capturedAt: DateTime(2026, 9, 26, 14, 30),
    recentActions: const ['Screen: Schedule'],
  );

  test('form session records the exact submission', () async {
    final gateway = InMemoryTicketGateway();
    final session = TicketFormSession(gateway);

    final outcome = await session.putIn(
      kind: TicketKind.problem,
      text: 'Save did not work',
      context: context,
    );

    expect(outcome, isA<TicketSent>());
    expect(gateway.submissions, hasLength(1));
    expect(gateway.submissions.single.kind, TicketKind.problem);
    expect(gateway.submissions.single.text, 'Save did not work');
    expect(gateway.submissions.single.context, same(context));
  });

  test(
    'detail session records opening and exposes the returned Ticket',
    () async {
      final sent = sampleTicket();
      final seen = sampleTicket(state: TicketState.seen);
      final gateway = InMemoryTicketGateway(openAnswers: {sent.id: seen});
      final session = TicketDetailSession(gateway, sent, true);

      await session.load();

      expect(gateway.openedIds, [sent.id]);
      expect((session.state as TicketDetailLoaded).ticket, same(seen));
    },
  );

  test('detail session records a GitHub link and exposes the updated Ticket', () async {
    final seen = sampleTicket(state: TicketState.seen);
    final linked = sampleTicket(
      state: TicketState.seen,
      githubIssue: const GitHubIssueLink(
        number: 365,
        url: 'https://github.com/mshamblin5150-code/gift-for-taylor/issues/365',
      ),
    );
    final gateway = InMemoryTicketGateway(
      openAnswers: {seen.id: seen},
      linkAnswers: {seen.id: linked},
    );
    final session = TicketDetailSession(gateway, seen, true);
    await session.load();

    final outcome = await session.linkToGitHub(
      const GitHubIssueLink(
        number: 365,
        url: 'https://github.com/mshamblin5150-code/gift-for-taylor/issues/365',
      ),
    );

    expect(outcome, isA<TicketMutationSucceeded>());
    expect(gateway.githubLinks.single.issue.number, 365);
    expect((session.state as TicketDetailLoaded).ticket, same(linked));
  });

  test(
    'detail session closes and reopens with the exact sender wording',
    () async {
      final seen = sampleTicket(state: TicketState.seen);
      final done = sampleTicket(
        state: TicketState.done,
        closeReason: 'The fix is live in release 1.2.3.',
        closedAt: DateTime.now(),
      );
      final reopened = sampleTicket(
        state: TicketState.seen,
        closeReason: done.closeReason,
        closedAt: done.closedAt,
        reopenedAt: DateTime.now(),
        reopenNote: 'It happened again.',
      );
      final gateway = InMemoryTicketGateway(
        openAnswers: {seen.id: seen},
        closeAnswers: {seen.id: done},
        reopenAnswers: {seen.id: reopened},
      );
      final session = TicketDetailSession(gateway, seen, true);
      await session.load();

      expect(
        await session.close(
          outcome: TicketState.done,
          reason: 'The fix is live in release 1.2.3.',
        ),
        isA<TicketMutationSucceeded>(),
      );
      expect(gateway.closes.single.reason, 'The fix is live in release 1.2.3.');
      expect(
        await session.reopen(note: 'It happened again.'),
        isA<TicketMutationSucceeded>(),
      );
      expect(gateway.reopens.single.note, 'It happened again.');
      expect((session.state as TicketDetailLoaded).ticket, same(reopened));
    },
  );

  test(
    'detail session refreshes SQL reopen eligibility at its deadline',
    () async {
      final now = DateTime.utc(2026, 9, 26, 15);
      final deadline = now.add(const Duration(days: 1));
      final available = sampleTicket(
        state: TicketState.done,
        closeReason: 'The fix is live.',
        closedAt: deadline.subtract(const Duration(days: 14)),
        canReopen: true,
        reopenUntil: deadline,
      );
      final expired = sampleTicket(
        state: TicketState.done,
        closeReason: available.closeReason,
        closedAt: available.closedAt,
      );
      var reads = 0;
      final gateway = InMemoryTicketGateway(
        senderOpenAnswer: (_) => reads++ == 0 ? available : expired,
      );
      late _ReopenTimer timer;
      Duration? scheduledDelay;
      final session = TicketDetailSession(
        gateway,
        available,
        false,
        now: () => now,
        timerFactory: (delay, callback) {
          scheduledDelay = delay;
          return timer = _ReopenTimer(callback);
        },
      );

      await session.load();
      expect((session.state as TicketDetailLoaded).ticket.canReopen, isTrue);
      expect(scheduledDelay, const Duration(days: 1, milliseconds: 10));
      timer.fire();
      await Future<void>.delayed(Duration.zero);

      expect(reads, 2);
      expect((session.state as TicketDetailLoaded).ticket.canReopen, isFalse);
      session.dispose();
    },
  );

  test(
    'form session reports rejected access through the app callback',
    () async {
      final gateway = InMemoryTicketGateway()
        ..failNext = AccessRejected(StateError('expired access'));
      var rejected = false;
      final session = TicketFormSession(
        gateway,
        onAccessRejected: () => rejected = true,
      );

      final outcome = await session.putIn(
        kind: TicketKind.idea,
        text: 'Show open shifts sooner',
        context: context,
      );

      expect(outcome, isA<TicketPutInFailed>());
      expect(rejected, isTrue);
    },
  );

  test('detail session exposes a typed Ticket thread refusal', () async {
    final seen = sampleTicket(state: TicketState.seen);
    final gateway = InMemoryTicketGateway(openAnswers: {seen.id: seen});
    final session = TicketDetailSession(gateway, seen, true);
    await session.load();
    gateway.failNext = const Refused(TicketThreadRefusal.questionInvalid);

    final outcome = await session.askQuestion(question: 'Question');

    expect(outcome, isA<TicketThreadCommandRefused>());
    expect(
      (outcome as TicketThreadCommandRefused).reason,
      TicketThreadRefusal.questionInvalid,
    );
    expect((session.state as TicketDetailLoaded).working, isFalse);
  });
}
