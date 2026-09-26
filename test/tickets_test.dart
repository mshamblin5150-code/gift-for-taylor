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
        home: PutInTicketPage(gateway: gateway, attachedContext: attached),
      ),
    );

    expect(find.text('Attached context'), findsOneWidget);
    expect(find.textContaining('Schedule · September 2026'), findsOneWidget);
    expect(find.textContaining('abc1234'), findsOneWidget);
    expect(find.textContaining('Chrome on Windows'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<TicketKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Something's wrong").last);
    await tester.enterText(
      find.byKey(const Key('ticket-text')),
      'Save did not work',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Send Ticket'));
    await tester.pumpAndSettle();

    expect(gateway.tickets, hasLength(1));
    expect(gateway.tickets.single.kind, TicketKind.problem);
    expect(gateway.tickets.single.text, 'Save did not work');
    expect(gateway.tickets.single.state, TicketState.sent);
    expect(gateway.tickets.single.context.release, 'abc1234');
  });

  testWidgets('My tickets shows kind, first line, date and state', (
    tester,
  ) async {
    final gateway = InMemoryTicketGateway(tickets: [sampleTicket()]);
    await tester.pumpWidget(
      MaterialApp(home: TicketsPage(gateway: gateway, maintainer: false)),
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
    final gateway = InMemoryTicketGateway(tickets: [sampleTicket()]);
    await tester.pumpWidget(
      MaterialApp(home: TicketsPage(gateway: gateway, maintainer: true)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Taylor Nurse'), findsOneWidget);
    expect(find.textContaining('Schedule · September 2026'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ticket-ticket-364')));
    await tester.pumpAndSettle();

    expect(gateway.openedCount, 1);
    expect(gateway.tickets.single.state, TicketState.seen);
    expect(find.text('Ticket text'), findsOneWidget);
    expect(find.textContaining('The button stayed busy.'), findsOneWidget);
    expect(find.text('Attached context'), findsOneWidget);
    expect(find.textContaining('Chrome on Windows'), findsOneWidget);
    expect(find.text('Seen'), findsOneWidget);
  });
}
