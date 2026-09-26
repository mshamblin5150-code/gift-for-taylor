import 'package:supabase_flutter/supabase_flutter.dart';

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
    this.month,
  });

  final String screen;
  final DateTime? month;
  final String release;
  final String device;
  final DateTime capturedAt;
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
    this.seenAt,
  });

  final String id;
  final String senderId;
  final String senderDisplayName;
  final TicketKind kind;
  final String text;
  final TicketState state;
  final TicketContext context;
  final DateTime createdAt;
  final DateTime? seenAt;

  String get firstLine => text.split(RegExp(r'\r?\n')).first;
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

abstract interface class TicketGateway {
  Future<void> putIn({
    required TicketKind kind,
    required String text,
    required TicketContext context,
  });

  Future<List<Ticket>> read();
  Future<Ticket> openForMaintainer(String id);
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
      rethrow;
    }
  }

  @override
  Future<List<Ticket>> read() async {
    final rows = await _client
        .from('tickets')
        .select(
          'id,sender_id,sender_display_name,kind,text,state,screen_context,'
          'schedule_month,release_id,device_context,context_captured_at,'
          'created_at,seen_at',
        )
        .order('created_at', ascending: false);
    return [for (final row in rows) _ticket(row)];
  }

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
    ),
    createdAt: DateTime.parse(row['created_at'] as String),
    seenAt: row['seen_at'] == null
        ? null
        : DateTime.parse(row['seen_at'] as String),
  );

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-01';
}
