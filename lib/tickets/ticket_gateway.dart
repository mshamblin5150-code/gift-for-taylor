import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:schedule_rules/schedule_rules.dart';

enum TicketKind {
  problem("Something's wrong", 'problem'),
  idea('An idea', 'idea'),
  question('A question', 'question');

  const TicketKind(this.label, this.databaseValue);
  final String label;
  final String databaseValue;

  static TicketKind fromDatabase(String value) => values.firstWhere(
    (kind) => kind.databaseValue == value,
    orElse: () => throw FormatException('Unknown Ticket kind: $value'),
  );
}

enum TicketState {
  sent('Sent', 'sent'),
  seen('Seen', 'seen'),
  waitingOnSender('Waiting on you', 'waiting_on_sender'),
  done('Done', 'done'),
  wontDo("Won't do", 'wont_do');

  const TicketState(this.label, this.databaseValue);
  final String label;
  final String databaseValue;

  static TicketState fromDatabase(String value) => values.firstWhere(
    (state) => state.databaseValue == value,
    orElse: () => throw FormatException('Unknown Ticket state: $value'),
  );
}

final class TicketContext {
  const TicketContext({
    required this.screen,
    required this.release,
    required this.device,
    required this.capturedAt,
    required this.recentActions,
    this.month,
    this.refusalCode,
  });

  final String screen;
  final DateTime? month;
  final String release;
  final String device;
  final DateTime capturedAt;
  final List<String> recentActions;
  final String? refusalCode;
}

final class GitHubIssueLink {
  const GitHubIssueLink({required this.number, required this.url});

  final int number;
  final String url;
}

final class Ticket {
  const Ticket({
    required this.id,
    required this.senderId,
    required this.senderDisplayName,
    required this.kind,
    required this.text,
    required this.state,
    required this.context,
    required this.createdAt,
    this.questionCount = 0,
    this.hasNewReply = false,
    this.seenAt,
    this.githubIssue,
    this.closeReason,
    this.closedAt,
    this.reopenedAt,
    this.reopenNote,
    this.canReopen = false,
    this.reopenUntil,
  });

  final String id;
  final String senderId;
  final String senderDisplayName;
  final TicketKind kind;
  final String text;
  final TicketState state;
  final TicketContext context;
  final DateTime createdAt;
  final int questionCount;
  final bool hasNewReply;
  final DateTime? seenAt;
  final GitHubIssueLink? githubIssue;
  final String? closeReason;
  final DateTime? closedAt;
  final DateTime? reopenedAt;
  final String? reopenNote;
  final bool canReopen;
  final DateTime? reopenUntil;

  String get firstLine => text.split(RegExp(r'\r?\n')).first;
}

enum TicketThreadAuthor { maintainer, sender }

final class TicketThreadEntry {
  const TicketThreadEntry({
    required this.id,
    required this.ticketId,
    required this.author,
    required this.text,
    required this.createdAt,
    this.suggestedAnswer,
    this.replyToId,
    this.acceptedSuggestion,
  });

  final String id;
  final String ticketId;
  final TicketThreadAuthor author;
  final String text;
  final String? suggestedAnswer;
  final String? replyToId;
  final bool? acceptedSuggestion;
  final DateTime createdAt;
}

enum TicketSubmissionRefusal {
  staffAccountRequired,
  textInvalid,
  contextIncomplete,
}

final class TicketSubmissionRefused implements Exception {
  const TicketSubmissionRefused(this.reason);
  final TicketSubmissionRefusal reason;
}

final class TicketUnavailable implements Exception {
  const TicketUnavailable();
}

enum TicketThreadRefusal {
  questionInvalid,
  ticketNotReady,
  answerInvalid,
  questionNotWaiting,
}

final class TicketThreadRefused implements Exception {
  const TicketThreadRefused(this.reason);
  final TicketThreadRefusal reason;
}

enum TicketMutationRefusal {
  invalidGitHubIssue,
  closingReasonRequired,
  cannotClose,
  reopeningNoteRequired,
  cannotReopen,
  reopenExpired,
}

final class TicketMutationRejected implements Exception {
  const TicketMutationRejected(this.reason);
  final TicketMutationRefusal reason;
}

abstract interface class TicketGateway {
  Future<void> putIn({
    required TicketKind kind,
    required String text,
    required TicketContext context,
  });

  Future<List<Ticket>> readMine(String senderId);
  Future<List<Ticket>> readForMaintainer();
  Future<Ticket> openForMaintainer(String id);
  Future<Ticket> openForSender(String id);
  Future<List<TicketThreadEntry>> readThread(String ticketId);
  Future<Ticket> askQuestion(
    String ticketId, {
    required String question,
    String? suggestedAnswer,
  });
  Future<Ticket> answerQuestion(
    String ticketId,
    String questionId, {
    String? answer,
    required bool acceptSuggestion,
  });
  Future<Ticket> linkToGitHub(String id, GitHubIssueLink issue);
  Future<Ticket> close(
    String id, {
    required TicketState outcome,
    required String reason,
  });
  Future<Ticket> reopen(String id, {required String note});
}

final class SupabaseTicketGateway implements TicketGateway {
  const SupabaseTicketGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<void> putIn({
    required TicketKind kind,
    required String text,
    required TicketContext context,
  }) async {
    try {
      await _client.rpc<void>(
        'put_in_ticket',
        params: {
          'p_kind': kind.databaseValue,
          'p_text': text,
          'p_screen_context': context.screen,
          'p_schedule_month': context.month == null
              ? null
              : _date(context.month!),
          'p_release_id': context.release,
          'p_device_context': context.device,
          'p_context_captured_at': context.capturedAt.toUtc().toIso8601String(),
          'p_recent_actions': context.recentActions,
          'p_refusal_code': context.refusalCode,
        },
      );
    } on PostgrestException catch (error) {
      final reason = switch (error.code) {
        'P2831' => TicketSubmissionRefusal.staffAccountRequired,
        'P2832' => TicketSubmissionRefusal.textInvalid,
        'P2833' => TicketSubmissionRefusal.contextIncomplete,
        _ => null,
      };
      if (reason != null) throw TicketSubmissionRefused(reason);
      if (_isAccessRejection(error)) throw AccessRejected(error);
      rethrow;
    }
  }

  @override
  Future<List<Ticket>> readMine(String senderId) => _read(senderId);

  @override
  Future<List<Ticket>> readForMaintainer() => _read(null);

  @override
  Future<Ticket> openForMaintainer(String id) async {
    try {
      final row = await _client.rpc<Map<String, dynamic>>(
        'open_ticket_for_maintainer',
        params: {'p_ticket_id': id},
      );
      return _ticket(row);
    } on PostgrestException catch (error) {
      if (error.code == 'P2834') throw const TicketUnavailable();
      if (_isAccessRejection(error)) throw AccessRejected(error);
      rethrow;
    }
  }

  @override
  Future<Ticket> openForSender(String id) async {
    try {
      final row = await _client.rpc<Map<String, dynamic>>(
        'open_ticket_for_sender',
        params: {'p_ticket_id': id},
      );
      return _ticket(row);
    } on PostgrestException catch (error) {
      if (error.code == 'P2834') throw const TicketUnavailable();
      if (_isAccessRejection(error)) throw AccessRejected(error);
      rethrow;
    }
  }

  @override
  Future<List<TicketThreadEntry>> readThread(String ticketId) async {
    try {
      final rows = await _client
          .from('ticket_thread_entries')
          .select(
            'id,ticket_id,author,text,suggested_answer,reply_to_id,'
            'accepted_suggestion,created_at',
          )
          .eq('ticket_id', ticketId)
          .order('created_at');
      return [for (final row in rows) _threadEntry(row)];
    } on PostgrestException catch (error) {
      if (_isAccessRejection(error)) throw AccessRejected(error);
      rethrow;
    }
  }

  @override
  Future<Ticket> askQuestion(
    String ticketId, {
    required String question,
    String? suggestedAnswer,
  }) async {
    try {
      final row = await _client.rpc<Map<String, dynamic>>(
        'ask_ticket_question',
        params: {
          'p_ticket_id': ticketId,
          'p_question': question,
          'p_suggested_answer': suggestedAnswer,
        },
      );
      return _ticket(row);
    } on PostgrestException catch (error) {
      final reason = switch (error.code) {
        'P2841' => TicketThreadRefusal.questionInvalid,
        'P2842' => TicketThreadRefusal.ticketNotReady,
        _ => null,
      };
      if (reason != null) throw TicketThreadRefused(reason);
      if (_isAccessRejection(error)) throw AccessRejected(error);
      rethrow;
    }
  }

  @override
  Future<Ticket> answerQuestion(
    String ticketId,
    String questionId, {
    String? answer,
    required bool acceptSuggestion,
  }) async {
    try {
      final row = await _client.rpc<Map<String, dynamic>>(
        'answer_ticket_question',
        params: {
          'p_ticket_id': ticketId,
          'p_question_id': questionId,
          'p_answer': answer,
          'p_accept_suggestion': acceptSuggestion,
        },
      );
      return _ticket(row);
    } on PostgrestException catch (error) {
      final reason = switch (error.code) {
        'P2843' => TicketThreadRefusal.answerInvalid,
        'P2844' => TicketThreadRefusal.questionNotWaiting,
        _ => null,
      };
      if (reason != null) throw TicketThreadRefused(reason);
      if (_isAccessRejection(error)) throw AccessRejected(error);
      rethrow;
    }
  }

  @override
  Future<Ticket> linkToGitHub(String id, GitHubIssueLink issue) => _mutation(
    () => _client.rpc<Map<String, dynamic>>(
      'link_ticket_to_github',
      params: {
        'p_ticket_id': id,
        'p_issue_number': issue.number,
        'p_issue_url': issue.url,
      },
    ),
  );

  @override
  Future<Ticket> close(
    String id, {
    required TicketState outcome,
    required String reason,
  }) => _mutation(
    () => _client.rpc<Map<String, dynamic>>(
      'close_ticket',
      params: {
        'p_ticket_id': id,
        'p_outcome': outcome.databaseValue,
        'p_reason': reason,
      },
    ),
  );

  @override
  Future<Ticket> reopen(String id, {required String note}) => _mutation(
    () => _client.rpc<Map<String, dynamic>>(
      'reopen_ticket',
      params: {'p_ticket_id': id, 'p_note': note},
    ),
  );

  Future<Ticket> _mutation(Future<Map<String, dynamic>> Function() call) async {
    try {
      final row = await call();
      return _ticket(row);
    } on PostgrestException catch (error) {
      final reason = switch (error.code) {
        'P2835' => TicketMutationRefusal.invalidGitHubIssue,
        'P2836' => TicketMutationRefusal.closingReasonRequired,
        'P2837' => TicketMutationRefusal.cannotClose,
        'P2838' => TicketMutationRefusal.reopeningNoteRequired,
        'P2839' => TicketMutationRefusal.cannotReopen,
        'P2840' => TicketMutationRefusal.reopenExpired,
        _ => null,
      };
      if (reason != null) throw TicketMutationRejected(reason);
      if (error.code == 'P2834') throw const TicketUnavailable();
      if (_isAccessRejection(error)) throw AccessRejected(error);
      rethrow;
    }
  }

  Future<List<Ticket>> _read(String? senderId) async {
    try {
      final query = _client
          .from('tickets')
          .select(
            'id,sender_id,sender_display_name,kind,text,state,screen_context,'
            'schedule_month,release_id,device_context,context_captured_at,'
            'recent_actions,refusal_code,created_at,seen_at,question_count,'
            'latest_reply_at,reply_seen_at,close_reason,closed_at,reopened_at,'
            'reopen_note',
          );
      final rows = senderId == null
          ? await query.order('created_at', ascending: false)
          : await query
                .eq('sender_id', senderId)
                .order('created_at', ascending: false);
      return [for (final row in rows) _ticket(row)];
    } on PostgrestException catch (error) {
      if (_isAccessRejection(error)) throw AccessRejected(error);
      rethrow;
    }
  }

  Ticket _ticket(Map<String, dynamic> row) => Ticket(
    id: row['id'] as String,
    senderId: row['sender_id'] as String,
    senderDisplayName: row['sender_display_name'] as String,
    kind: TicketKind.fromDatabase(row['kind'] as String),
    text: row['text'] as String,
    state: TicketState.fromDatabase(row['state'] as String),
    context: TicketContext(
      screen: row['screen_context'] as String,
      month: row['schedule_month'] == null
          ? null
          : DateTime.parse(row['schedule_month'] as String),
      release: row['release_id'] as String,
      device: row['device_context'] as String,
      capturedAt: DateTime.parse(row['context_captured_at'] as String),
      recentActions: List<String>.from(row['recent_actions'] as List),
      refusalCode: row['refusal_code'] as String?,
    ),
    createdAt: DateTime.parse(row['created_at'] as String),
    questionCount: row['question_count'] as int? ?? 0,
    hasNewReply: row['latest_reply_at'] != null && row['reply_seen_at'] == null,
    seenAt: row['seen_at'] == null
        ? null
        : DateTime.parse(row['seen_at'] as String),
    githubIssue: row['github_issue_number'] == null
        ? null
        : GitHubIssueLink(
            number: row['github_issue_number'] as int,
            url: row['github_issue_url'] as String,
          ),
    closeReason: row['close_reason'] as String?,
    closedAt: row['closed_at'] == null
        ? null
        : DateTime.parse(row['closed_at'] as String),
    reopenedAt: row['reopened_at'] == null
        ? null
        : DateTime.parse(row['reopened_at'] as String),
    reopenNote: row['reopen_note'] as String?,
    canReopen: row['can_reopen'] as bool? ?? false,
    reopenUntil: row['reopen_until'] == null
        ? null
        : DateTime.parse(row['reopen_until'] as String),
  );

  TicketThreadEntry _threadEntry(Map<String, dynamic> row) => TicketThreadEntry(
    id: row['id'] as String,
    ticketId: row['ticket_id'] as String,
    author: switch (row['author'] as String) {
      'maintainer' => TicketThreadAuthor.maintainer,
      'sender' => TicketThreadAuthor.sender,
      final value => throw FormatException(
        'Unknown Ticket thread author: $value',
      ),
    },
    text: row['text'] as String,
    suggestedAnswer: row['suggested_answer'] as String?,
    replyToId: row['reply_to_id'] as String?,
    acceptedSuggestion: row['accepted_suggestion'] as bool?,
    createdAt: DateTime.parse(row['created_at'] as String),
  );

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-01';

  bool _isAccessRejection(PostgrestException error) =>
      error.code == '42501' || error.code == '401' || error.code == '403';
}
