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
}
