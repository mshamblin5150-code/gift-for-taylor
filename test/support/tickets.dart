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

final class RecordedGitHubLink {
  const RecordedGitHubLink(this.ticketId, this.issue);
  final String ticketId;
  final GitHubIssueLink issue;
}

final class RecordedTicketClose {
  const RecordedTicketClose(this.ticketId, this.outcome, this.reason);
  final String ticketId;
  final TicketState outcome;
  final String reason;
}

final class RecordedTicketReopen {
  const RecordedTicketReopen(this.ticketId, this.note);
  final String ticketId;
  final String note;
}

final class InMemoryTicketGateway implements TicketGateway {
  InMemoryTicketGateway({
    List<Ticket> myTickets = const [],
    List<Ticket> maintainerTickets = const [],
    Map<String, Ticket> openAnswers = const {},
    Map<String, Ticket> senderOpenAnswers = const {},
    this.senderOpenAnswer,
    Map<String, List<List<TicketThreadEntry>>> threadAnswers = const {},
    Map<String, Ticket> askAnswers = const {},
    Map<String, Ticket> answerAnswers = const {},
    Map<String, Ticket> linkAnswers = const {},
    Map<String, Ticket> closeAnswers = const {},
    Map<String, Ticket> reopenAnswers = const {},
    Map<String, Ticket> redactTicketAnswers = const {},
    Map<String, TicketThreadEntry> redactThreadAnswers = const {},
  }) : myTickets = List.unmodifiable(myTickets),
       maintainerTickets = List.unmodifiable(maintainerTickets),
       openAnswers = Map.unmodifiable(openAnswers),
       senderOpenAnswers = Map.unmodifiable(senderOpenAnswers),
       threadAnswers = {
         for (final entry in threadAnswers.entries)
           entry.key: [for (final answer in entry.value) List.of(answer)],
       },
       askAnswers = Map.unmodifiable(askAnswers),
       answerAnswers = Map.unmodifiable(answerAnswers),
       linkAnswers = Map.unmodifiable(linkAnswers),
       closeAnswers = Map.unmodifiable(closeAnswers),
       reopenAnswers = Map.unmodifiable(reopenAnswers),
       redactTicketAnswers = Map.unmodifiable(redactTicketAnswers),
       redactThreadAnswers = Map.unmodifiable(redactThreadAnswers);

  final List<Ticket> myTickets;
  final List<Ticket> maintainerTickets;
  final Map<String, Ticket> openAnswers;
  final Map<String, Ticket> senderOpenAnswers;
  final Ticket Function(String id)? senderOpenAnswer;
  final Map<String, List<List<TicketThreadEntry>>> threadAnswers;
  final Map<String, Ticket> askAnswers;
  final Map<String, Ticket> answerAnswers;
  final List<RecordedTicketSubmission> submissions = [];
  final List<String> openedIds = [];
  final List<RecordedTicketQuestion> questions = [];
  final List<RecordedTicketAnswer> answers = [];
  final Map<String, Ticket> linkAnswers;
  final Map<String, Ticket> closeAnswers;
  final Map<String, Ticket> reopenAnswers;
  final Map<String, Ticket> redactTicketAnswers;
  final Map<String, TicketThreadEntry> redactThreadAnswers;
  final List<RecordedGitHubLink> githubLinks = [];
  final List<RecordedTicketClose> closes = [];
  final List<RecordedTicketReopen> reopens = [];
  final List<String> redactedTicketIds = [];
  final List<String> redactedThreadEntryIds = [];
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
  Future<Ticket> openForSender(String id) async {
    _throwFailure();
    openedIds.add(id);
    if (senderOpenAnswer case final answer?) return answer(id);
    return senderOpenAnswers[id] ??
        (throw StateError('No recorded sender answer for Ticket $id.'));
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

  @override
  Future<Ticket> linkToGitHub(String id, GitHubIssueLink issue) async {
    _throwFailure();
    githubLinks.add(RecordedGitHubLink(id, issue));
    return linkAnswers[id] ??
        (throw StateError('No recorded link answer for Ticket $id.'));
  }

  @override
  Future<Ticket> close(
    String id, {
    required TicketState outcome,
    required String reason,
  }) async {
    _throwFailure();
    closes.add(RecordedTicketClose(id, outcome, reason));
    return closeAnswers[id] ??
        (throw StateError('No recorded close answer for Ticket $id.'));
  }

  @override
  Future<Ticket> reopen(String id, {required String note}) async {
    _throwFailure();
    reopens.add(RecordedTicketReopen(id, note));
    return reopenAnswers[id] ??
        (throw StateError('No recorded reopen answer for Ticket $id.'));
  }

  @override
  Future<Ticket> redactText(String id) async {
    _throwFailure();
    redactedTicketIds.add(id);
    return redactTicketAnswers[id] ??
        (throw StateError('No recorded redact answer for Ticket $id.'));
  }

  @override
  Future<TicketThreadEntry> redactThreadEntry(String id) async {
    _throwFailure();
    redactedThreadEntryIds.add(id);
    return redactThreadAnswers[id] ??
        (throw StateError('No recorded redact answer for thread entry $id.'));
  }

  void _throwFailure() {
    if (failNext case final failure?) {
      failNext = null;
      throw failure;
    }
  }
}

Ticket sampleTicket({
  String id = 'ticket-364',
  String text = 'Save did not work\nThe button stayed busy.',
  TicketState state = TicketState.sent,
  int questionCount = 0,
  bool hasNewReply = false,
  GitHubIssueLink? githubIssue,
  String? closeReason,
  DateTime? closedAt,
  DateTime? reopenedAt,
  String? reopenNote,
  bool canReopen = false,
  DateTime? reopenUntil,
  TicketTextRemoval? textRemoval,
}) => Ticket(
  id: id,
  senderId: 'sender-364',
  senderDisplayName: 'Taylor Nurse',
  kind: TicketKind.problem,
  text: text,
  state: state,
  questionCount: questionCount,
  hasNewReply: hasNewReply,
  githubIssue: githubIssue,
  closeReason: closeReason,
  closedAt: closedAt,
  reopenedAt: reopenedAt,
  reopenNote: reopenNote,
  canReopen: canReopen,
  reopenUntil: reopenUntil,
  textRemoval: textRemoval,
  context: TicketContext(
    screen: 'Schedule',
    month: DateTime(2026, 9),
    release: 'abc1234',
    device: 'Chrome on Windows',
    capturedAt: DateTime(2026, 9, 26, 14, 30),
    recentActions: const ['Screen: Schedule', 'RPC: save_schedule_cell'],
  ),
  createdAt: DateTime(2026, 9, 26, 14, 30),
);

TicketThreadEntry sampleQuestion({
  String id = 'question-366',
  String ticketId = 'ticket-364',
  String text = 'Was it the swap with the 14th in it?',
  String? suggestedAnswer = 'It was the swap with the 14th in it.',
  TicketTextRemoval? textRemoval,
}) => TicketThreadEntry(
  id: id,
  ticketId: ticketId,
  author: TicketThreadAuthor.maintainer,
  text: text,
  suggestedAnswer: suggestedAnswer,
  textRemoval: textRemoval,
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
