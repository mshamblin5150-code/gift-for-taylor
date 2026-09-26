import 'package:er_schedule/tickets/ticket_gateway.dart';
import 'package:er_schedule/tickets/ticket_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'support/tickets.dart';

void main() {
  final context = TicketContext(
    screen: 'Schedule',
    month: DateTime(2026, 9),
    release: 'abc1234',
    device: 'Chrome on Windows',
    capturedAt: DateTime(2026, 9, 26, 14, 30),
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
}
