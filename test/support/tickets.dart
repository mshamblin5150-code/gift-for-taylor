import 'package:er_schedule/tickets/ticket_gateway.dart';

final class InMemoryTicketGateway implements TicketGateway {
  InMemoryTicketGateway({
    List<Ticket> tickets = const [],
    this.senderId = 'sender-1',
    this.senderDisplayName = 'Taylor Nurse',
  }) : tickets = [...tickets];

  final String senderId;
  final String senderDisplayName;
  final List<Ticket> tickets;
  int openedCount = 0;
  Object? failNext;

  @override
  Future<void> putIn({
    required TicketKind kind,
    required String text,
    required TicketContext context,
  }) async {
    if (failNext case final failure?) {
      failNext = null;
      throw failure;
    }
    tickets.insert(
      0,
      Ticket(
        id: 'ticket-${tickets.length + 1}',
        senderId: senderId,
        senderDisplayName: senderDisplayName,
        kind: kind,
        text: text.trim(),
        state: TicketState.sent,
        context: context,
        createdAt: context.capturedAt,
      ),
    );
  }

  @override
  Future<List<Ticket>> read() async => [...tickets];

  @override
  Future<Ticket> openForMaintainer(String id) async {
    openedCount += 1;
    final index = tickets.indexWhere((ticket) => ticket.id == id);
    final ticket = tickets[index];
    if (ticket.state != TicketState.sent) return ticket;
    final seen = Ticket(
      id: ticket.id,
      senderId: ticket.senderId,
      senderDisplayName: ticket.senderDisplayName,
      kind: ticket.kind,
      text: ticket.text,
      state: TicketState.seen,
      context: ticket.context,
      createdAt: ticket.createdAt,
      seenAt: DateTime(2026, 9, 26, 15),
    );
    tickets[index] = seen;
    return seen;
  }
}

Ticket sampleTicket({
  String id = 'ticket-364',
  TicketState state = TicketState.sent,
}) => Ticket(
  id: id,
  senderId: 'sender-364',
  senderDisplayName: 'Taylor Nurse',
  kind: TicketKind.problem,
  text: 'Save did not work\nThe button stayed busy.',
  state: state,
  context: TicketContext(
    screen: 'Schedule',
    month: DateTime(2026, 9),
    release: 'abc1234',
    device: 'Chrome on Windows',
    capturedAt: DateTime(2026, 9, 26, 14, 30),
  ),
  createdAt: DateTime(2026, 9, 26, 14, 30),
);
