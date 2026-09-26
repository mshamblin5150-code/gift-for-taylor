import 'package:er_schedule/tickets/ticket_gateway.dart';
import 'package:er_schedule/tickets/ticket_pages.dart';
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
    expect(find.byKey(const Key('ticket-question')), findsOneWidget);
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
}
