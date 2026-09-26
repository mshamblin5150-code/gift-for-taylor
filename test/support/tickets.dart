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

final class RecordedTicketQuestion {
  const RecordedTicketQuestion({
    required this.ticketId,
    required this.question,
    required this.suggestedAnswer,
  });

  final String ticketId;
  final String question;
  final String? suggestedAnswer;
}

final class RecordedTicketAnswer {
  const RecordedTicketAnswer({
    required this.ticketId,
    required this.questionId,
    required this.answer,
    required this.acceptSuggestion,
  });

  final String ticketId;
  final String questionId;
  final String? answer;
  final bool acceptSuggestion;
}

final class InMemoryTicketGateway implements TicketGateway {
  InMemoryTicketGateway({
    List<Ticket> myTickets = const [],
    List<Ticket> maintainerTickets = const [],
    Map<String, Ticket> openAnswers = const {},
    Map<String, List<List<TicketThreadEntry>>> threadAnswers = const {},
    Map<String, Ticket> askAnswers = const {},
    Map<String, Ticket> answerAnswers = const {},
  }) : myTickets = List.unmodifiable(myTickets),
       maintainerTickets = List.unmodifiable(maintainerTickets),
       openAnswers = Map.unmodifiable(openAnswers),
       threadAnswers = {
         for (final entry in threadAnswers.entries)
           entry.key: [for (final answer in entry.value) List.of(answer)],
       },
       askAnswers = Map.unmodifiable(askAnswers),
       answerAnswers = Map.unmodifiable(answerAnswers);

  final List<Ticket> myTickets;
  final List<Ticket> maintainerTickets;
  final Map<String, Ticket> openAnswers;
  final Map<String, List<List<TicketThreadEntry>>> threadAnswers;
  final Map<String, Ticket> askAnswers;
  final Map<String, Ticket> answerAnswers;
  final List<RecordedTicketSubmission> submissions = [];
  final List<String> openedIds = [];
  final List<RecordedTicketQuestion> questions = [];
  final List<RecordedTicketAnswer> answers = [];
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

  @override
  Future<List<TicketThreadEntry>> readThread(String ticketId) async {
    final answers = threadAnswers[ticketId];
    if (answers == null || answers.isEmpty) return const [];
    final answer = answers.length == 1 ? answers.single : answers.removeAt(0);
    return List.unmodifiable(answer);
  }

  @override
  Future<Ticket> askQuestion(
    String ticketId, {
    required String question,
    String? suggestedAnswer,
  }) async {
    if (failNext case final failure?) {
      failNext = null;
      throw failure;
    }
    questions.add(
      RecordedTicketQuestion(
        ticketId: ticketId,
        question: question,
        suggestedAnswer: suggestedAnswer,
      ),
    );
    return askAnswers[ticketId] ??
        (throw StateError('No recorded question answer for Ticket $ticketId.'));
  }

  @override
  Future<Ticket> answerQuestion(
    String ticketId,
    String questionId, {
    String? answer,
    required bool acceptSuggestion,
  }) async {
    if (failNext case final failure?) {
      failNext = null;
      throw failure;
    }
    answers.add(
      RecordedTicketAnswer(
        ticketId: ticketId,
        questionId: questionId,
        answer: answer,
        acceptSuggestion: acceptSuggestion,
      ),
    );
    return answerAnswers[ticketId] ??
        (throw StateError('No recorded answer result for Ticket $ticketId.'));
  }
}

Ticket sampleTicket({
  String id = 'ticket-364',
  TicketState state = TicketState.sent,
  int questionCount = 0,
  bool hasNewReply = false,
}) => Ticket(
  id: id,
  senderId: 'sender-364',
  senderDisplayName: 'Taylor Nurse',
  kind: TicketKind.problem,
  text: 'Save did not work\nThe button stayed busy.',
  state: state,
  questionCount: questionCount,
  hasNewReply: hasNewReply,
  context: TicketContext(
    screen: 'Schedule',
    month: DateTime(2026, 9),
    release: 'abc1234',
    device: 'Chrome on Windows',
    capturedAt: DateTime(2026, 9, 26, 14, 30),
  ),
  createdAt: DateTime(2026, 9, 26, 14, 30),
);

TicketThreadEntry sampleQuestion({
  String id = 'question-366',
  String ticketId = 'ticket-364',
  String? suggestedAnswer = 'It was the swap with the 14th in it.',
}) => TicketThreadEntry(
  id: id,
  ticketId: ticketId,
  author: TicketThreadAuthor.maintainer,
  text: 'Was it the swap with the 14th in it?',
  suggestedAnswer: suggestedAnswer,
  createdAt: DateTime(2026, 9, 26, 15),
);

TicketThreadEntry sampleAnswer({
  String ticketId = 'ticket-364',
  String questionId = 'question-366',
  String text = 'It was the swap with the 14th in it.',
  bool acceptedSuggestion = true,
}) => TicketThreadEntry(
  id: 'answer-366',
  ticketId: ticketId,
  author: TicketThreadAuthor.sender,
  text: text,
  replyToId: questionId,
  acceptedSuggestion: acceptedSuggestion,
  createdAt: DateTime(2026, 9, 26, 15, 5),
);
