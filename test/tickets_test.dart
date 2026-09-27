import 'package:er_schedule/tickets/ticket_gateway.dart';
import 'package:er_schedule/tickets/ticket_pages.dart';
import 'package:er_schedule/tickets/ticket_activity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tickets.dart';

void main() {
  testWidgets('Staff sees attached context and puts in a Ticket', (
    tester,
  ) async {
    final gateway = InMemoryTicketGateway();
    final attached = TicketContext(
      screen: 'Schedule',
      month: DateTime(2026, 9),
      release: 'abc1234',
      device: 'Chrome on Windows',
      capturedAt: DateTime(2026, 9, 26, 14, 30),
      recentActions: const ['Screen: Schedule'],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => PutInTicketPage(
                    gateway: gateway,
                    attachedContext: attached,
                  ),
                ),
              ),
              child: const Text('Open Ticket form'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open Ticket form'));
    await tester.pumpAndSettle();

    expect(find.text('Attached context'), findsOneWidget);
    expect(find.textContaining('Schedule · September 2026'), findsOneWidget);
    expect(find.textContaining('abc1234'), findsOneWidget);
    expect(find.textContaining('Chrome on Windows'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('ticket-text')))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Send Ticket'),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byType(DropdownButtonFormField<TicketKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Something's wrong").last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('ticket-text')),
      'Save did not work',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Send Ticket'));
    await tester.pumpAndSettle();

    expect(find.text('Open Ticket form'), findsOneWidget);
  });

  testWidgets('a refusal opens a problem Ticket with code and recent actions', (
    tester,
  ) async {
    final gateway = InMemoryTicketGateway();
    final actions = TicketActivityLog()
      ..screenVisited('Schedule')
      ..rpcCalled('propose_swap');
    final launcher = TicketLauncher(gateway: gateway, actions: actions);

    await tester.pumpWidget(
      TicketLauncherScope(
        launcher: launcher,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => launcher.openRefusal(
                  context,
                  refusal: TicketRefusalContext(
                    screen: 'Swaps',
                    month: DateTime(2026, 9),
                    code: 'P2814',
                  ),
                ),
                child: const Text('Put in a ticket about this'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Put in a ticket about this'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<DropdownButtonFormField<TicketKind>>(
            find.byType(DropdownButtonFormField<TicketKind>),
          )
          .initialValue,
      TicketKind.problem,
    );
    expect(find.textContaining('Refusal P2814'), findsOneWidget);
    expect(find.textContaining('RPC: propose_swap'), findsOneWidget);
  });

  testWidgets('My tickets shows kind, first line, date and state', (
    tester,
  ) async {
    final gateway = InMemoryTicketGateway(myTickets: [sampleTicket()]);
    await tester.pumpWidget(
      MaterialApp(
        home: TicketsPage(
          gateway: gateway,
          maintainer: false,
          ownStaffMemberId: 'sender-364',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Something's wrong"), findsOneWidget);
    expect(find.textContaining('Save did not work'), findsOneWidget);
    expect(find.textContaining('Sep 26, 2026'), findsOneWidget);
    expect(find.textContaining('Sent'), findsOneWidget);
  });

  testWidgets('My tickets shows a closed outcome and its reason', (
    tester,
  ) async {
    final gateway = InMemoryTicketGateway(
      myTickets: [
        sampleTicket(
          state: TicketState.wontDo,
          closeReason: 'This would make the Schedule harder to read.',
          closedAt: DateTime(2026, 9, 26),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TicketsPage(
          gateway: gateway,
          maintainer: false,
          ownStaffMemberId: 'sender-364',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining("Won't do"), findsOneWidget);
    expect(
      find.textContaining('This would make the Schedule harder to read.'),
      findsOneWidget,
    );
  });

  testWidgets('Maintainer sees context and opening marks the Ticket Seen', (
    tester,
  ) async {
    final gateway = InMemoryTicketGateway(
      maintainerTickets: [sampleTicket()],
      openAnswers: {'ticket-364': sampleTicket(state: TicketState.seen)},
    );
    await tester.pumpWidget(
      MaterialApp(home: TicketsPage(gateway: gateway, maintainer: true)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Taylor Nurse'), findsOneWidget);
    expect(find.textContaining('Schedule · September 2026'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ticket-ticket-364')));
    await tester.pumpAndSettle();

    expect(find.text('Ticket text'), findsOneWidget);
    expect(find.textContaining('The button stayed busy.'), findsOneWidget);
    expect(find.text('Attached context'), findsOneWidget);
    expect(find.textContaining('Chrome on Windows'), findsOneWidget);
    expect(find.text('Seen'), findsOneWidget);
  });

  testWidgets('Maintainer sees the private thread and question count', (
    tester,
  ) async {
    final gateway = InMemoryTicketGateway(
      maintainerTickets: [sampleTicket()],
      openAnswers: {'ticket-364': sampleTicket(state: TicketState.seen)},
    );
    await tester.pumpWidget(
      MaterialApp(home: TicketsPage(gateway: gateway, maintainer: true)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ticket-ticket-364')));
    await tester.pumpAndSettle();

    expect(find.text('Private thread'), findsOneWidget);
    expect(find.text('Questions asked: 0 of 2'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('ticket-question')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byKey(const Key('ticket-question')), findsOneWidget);
  });

  testWidgets('Maintainer can redact Ticket text and one thread message', (
    tester,
  ) async {
    final seen = sampleTicket(state: TicketState.seen);
    final redacted = sampleTicket(
      state: TicketState.seen,
      text: ticketTextRemovedByMaintainer,
      textRemoval: TicketTextRemoval.maintainer,
    );
    final question = sampleQuestion();
    final redactedQuestion = sampleQuestion(
      text: ticketTextRemovedByMaintainer,
      suggestedAnswer: null,
      textRemoval: TicketTextRemoval.maintainer,
    );
    final gateway = InMemoryTicketGateway(
      openAnswers: {seen.id: seen},
      threadAnswers: {
        seen.id: [
          [question],
          [redactedQuestion],
        ],
      },
      redactTicketAnswers: {seen.id: redacted},
      redactThreadAnswers: {question.id: redactedQuestion},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TicketDetailPage(
          gateway: gateway,
          ticket: seen,
          maintainer: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ticket-redact-text')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Redact'));
    await tester.pumpAndSettle();

    expect(find.text(ticketTextRemovedByMaintainer), findsOneWidget);
    expect(gateway.redactedTicketIds, [seen.id]);

    final redactMessage = find.byKey(
      const Key('ticket-redact-entry-question-366'),
    );
    await tester.scrollUntilVisible(
      redactMessage,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(redactMessage);
    await tester.pumpAndSettle();
    await tester.tap(redactMessage);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Redact'));
    await tester.pumpAndSettle();

    expect(
      find.text(ticketTextRemovedByMaintainer, skipOffstage: false),
      findsNWidgets(2),
    );
    expect(gateway.redactedThreadEntryIds, [question.id]);
    expect(find.textContaining('Suggested answer:'), findsNothing);
  });

  testWidgets('Maintainer asks a question with a suggested answer', (
    tester,
  ) async {
    final gateway = InMemoryTicketGateway(
      maintainerTickets: [sampleTicket()],
      openAnswers: {'ticket-364': sampleTicket(state: TicketState.seen)},
      threadAnswers: {
        'ticket-364': [
          [],
          [sampleQuestion()],
        ],
      },
      askAnswers: {
        'ticket-364': sampleTicket(
          state: TicketState.waitingOnSender,
          questionCount: 1,
        ),
      },
    );
    await tester.pumpWidget(
      MaterialApp(home: TicketsPage(gateway: gateway, maintainer: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ticket-ticket-364')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('ticket-question')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(
      find.byKey(const Key('ticket-question')),
      'Was it the swap with the 14th in it?',
    );
    await tester.enterText(
      find.byKey(const Key('ticket-suggested-answer')),
      'It was the swap with the 14th in it.',
    );
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Ask sender'));
    await tester.pumpAndSettle();

    expect(
      gateway.questions.single.question,
      'Was it the swap with the 14th in it?',
    );
    expect(
      gateway.questions.single.suggestedAnswer,
      'It was the swap with the 14th in it.',
    );
    expect(find.text('Waiting on you', skipOffstage: false), findsOneWidget);
    expect(
      find.text('Questions asked: 1 of 2', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.textContaining('Suggested answer:'), findsOneWidget);
  });

  testWidgets('Sender can confirm the Maintainer guess with one tap', (
    tester,
  ) async {
    final waiting = sampleTicket(
      state: TicketState.waitingOnSender,
      questionCount: 1,
    );
    final gateway = InMemoryTicketGateway(
      myTickets: [waiting],
      senderOpenAnswers: {waiting.id: waiting},
      threadAnswers: {
        waiting.id: [
          [sampleQuestion()],
          [sampleQuestion(), sampleAnswer()],
        ],
      },
      answerAnswers: {
        waiting.id: sampleTicket(
          state: TicketState.seen,
          questionCount: 1,
          hasNewReply: true,
        ),
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TicketsPage(
          gateway: gateway,
          maintainer: false,
          ownStaffMemberId: waiting.senderId,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ticket-ticket-364')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('ticket-answer-yes')));
    await tester.tap(find.byKey(const Key('ticket-answer-yes')));
    await tester.pumpAndSettle();

    expect(gateway.answers.single.acceptSuggestion, isTrue);
    expect(gateway.answers.single.answer, isNull);
    expect(find.text('Seen'), findsOneWidget);
  });

  testWidgets('Sender can replace the Maintainer guess with text', (
    tester,
  ) async {
    final waiting = sampleTicket(
      state: TicketState.waitingOnSender,
      questionCount: 1,
    );
    final gateway = InMemoryTicketGateway(
      myTickets: [waiting],
      senderOpenAnswers: {waiting.id: waiting},
      threadAnswers: {
        waiting.id: [
          [sampleQuestion()],
          [
            sampleQuestion(),
            sampleAnswer(
              text: 'No, it was the swap on the 18th.',
              acceptedSuggestion: false,
            ),
          ],
        ],
      },
      answerAnswers: {
        waiting.id: sampleTicket(
          state: TicketState.seen,
          questionCount: 1,
          hasNewReply: true,
        ),
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TicketsPage(
          gateway: gateway,
          maintainer: false,
          ownStaffMemberId: waiting.senderId,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ticket-ticket-364')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('ticket-answer')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(
      find.byKey(const Key('ticket-answer')),
      'No, it was the swap on the 18th.',
    );
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Send answer'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Send answer'));
    await tester.pumpAndSettle();

    expect(gateway.answers.single.acceptSuggestion, isFalse);
    expect(gateway.answers.single.answer, 'No, it was the swap on the 18th.');
    expect(find.text('Seen'), findsOneWidget);
  });

  testWidgets('Sender sees a neutral answer label when there is no guess', (
    tester,
  ) async {
    final waiting = sampleTicket(
      state: TicketState.waitingOnSender,
      questionCount: 1,
    );
    final gateway = InMemoryTicketGateway(
      myTickets: [waiting],
      senderOpenAnswers: {waiting.id: waiting},
      threadAnswers: {
        waiting.id: [
          [sampleQuestion(suggestedAnswer: null)],
        ],
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TicketsPage(
          gateway: gateway,
          maintainer: false,
          ownStaffMemberId: waiting.senderId,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ticket-ticket-364')));
    await tester.pumpAndSettle();

    expect(find.text('Your answer'), findsOneWidget);
    expect(find.byKey(const Key('ticket-answer-yes')), findsNothing);
  });

  testWidgets('Maintainer list marks a Ticket with a new reply', (
    tester,
  ) async {
    final gateway = InMemoryTicketGateway(
      maintainerTickets: [
        sampleTicket(state: TicketState.seen, hasNewReply: true),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(home: TicketsPage(gateway: gateway, maintainer: true)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('New reply'), findsOneWidget);
  });

  testWidgets('Maintainer links GitHub and closes Done only after release', (
    tester,
  ) async {
    final seen = sampleTicket(state: TicketState.seen);
    final linked = sampleTicket(
      state: TicketState.seen,
      githubIssue: const GitHubIssueLink(
        number: 365,
        url: 'https://github.com/mshamblin5150-code/gift-for-taylor/issues/365',
      ),
    );
    final done = sampleTicket(
      state: TicketState.done,
      githubIssue: linked.githubIssue,
      closeReason: 'The fix is live in release 1.2.3.',
      closedAt: DateTime.now(),
    );
    final gateway = InMemoryTicketGateway(
      openAnswers: {seen.id: seen},
      linkAnswers: {seen.id: linked},
      closeAnswers: {seen.id: done},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TicketDetailPage(
          gateway: gateway,
          ticket: seen,
          maintainer: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Record GitHub issue'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('ticket-github-url')),
      'https://github.com/mshamblin5150-code/gift-for-taylor/issues/365',
    );
    await tester.tap(find.text('Record issue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('GitHub issue #365'), findsOneWidget);

    await tester.tap(find.text('Close as Done'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('only when the fix is live in a release'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('ticket-close-reason')),
      'The fix is live in release 1.2.3.',
    );
    await tester.tap(find.text('Close Ticket'));
    await tester.pumpAndSettle();

    expect(find.text('Done'), findsOneWidget);
    expect(find.text('The fix is live in release 1.2.3.'), findsOneWidget);
    expect(gateway.closes.single.outcome, TicketState.done);
  });

  testWidgets('sender sees the outcome and can reopen within 14 days', (
    tester,
  ) async {
    final done = sampleTicket(
      state: TicketState.done,
      closeReason: 'The fix is live now.',
      closedAt: DateTime.now().subtract(const Duration(days: 13)),
      canReopen: true,
      reopenUntil: DateTime.now().add(const Duration(days: 1)),
    );
    final reopened = sampleTicket(
      state: TicketState.seen,
      closeReason: done.closeReason,
      closedAt: done.closedAt,
      reopenedAt: DateTime.now(),
      reopenNote: 'The same failure happened again.',
    );
    final gateway = InMemoryTicketGateway(
      senderOpenAnswers: {done.id: done},
      reopenAnswers: {done.id: reopened},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TicketDetailPage(
          gateway: gateway,
          ticket: done,
          maintainer: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('The fix is live now.'), findsOneWidget);
    expect(find.textContaining('GitHub issue'), findsNothing);
    await tester.tap(find.text('Reopen Ticket'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('ticket-reopen-note')),
      'The same failure happened again.',
    );
    await tester.tap(find.text('Reopen'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Reopened · regression'), findsOneWidget);
    expect(gateway.reopens.single.note, 'The same failure happened again.');
  });

  testWidgets('sender is pointed to a new Ticket after 14 days', (
    tester,
  ) async {
    final closed = sampleTicket(
      state: TicketState.wontDo,
      closeReason: 'This would make the Schedule harder to read.',
      closedAt: DateTime.now().subtract(const Duration(days: 15)),
    );
    final gateway = InMemoryTicketGateway(
      senderOpenAnswers: {closed.id: closed},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TicketDetailPage(
          gateway: gateway,
          ticket: closed,
          maintainer: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reopen Ticket'), findsNothing);
    expect(find.textContaining('put in a new Ticket'), findsOneWidget);
  });
}
