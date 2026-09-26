import 'package:er_schedule/tickets/ticket_gateway.dart';

final class RecordedTicketSubmission {
  const RecordedTicketSubmission({
    required this.kind,
    required this.text,
    required this.context,
  });

  final TicketKind kind;
  final String text;
  final TicketContext context;
}

final class InMemoryTicketGateway implements TicketGateway {
  InMemoryTicketGateway({
    List<Ticket> myTickets = const [],
    List<Ticket> maintainerTickets = const [],
    Map<String, Ticket> openAnswers = const {},
  }) : myTickets = List.unmodifiable(myTickets),
       maintainerTickets = List.unmodifiable(maintainerTickets),
       openAnswers = Map.unmodifiable(openAnswers);

  final List<Ticket> myTickets;
  final List<Ticket> maintainerTickets;
  final Map<String, Ticket> openAnswers;
  final List<RecordedTicketSubmission> submissions = [];
  final List<String> openedIds = [];
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
    submissions.add(
      RecordedTicketSubmission(kind: kind, text: text, context: context),
    );
  }

  @override
  Future<List<Ticket>> readMine(String senderId) async => myTickets;

  @override
  Future<List<Ticket>> readForMaintainer() async => maintainerTickets;

  @override
  Future<Ticket> openForMaintainer(String id) async {
    if (failNext case final failure?) {
      failNext = null;
      throw failure;
    }
    openedIds.add(id);
    return openAnswers[id] ??
        (throw StateError('No recorded open answer for Ticket $id.'));
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
