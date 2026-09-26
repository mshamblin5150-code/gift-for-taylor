import 'package:supabase_flutter/supabase_flutter.dart';

final class UndeliveredInvitation {
  const UndeliveredInvitation({
    required this.staffDisplayName,
    required this.workDate,
    required this.recipient,
    required this.method,
    required this.shiftCode,
    required this.deliveryAttempts,
    required this.failedAt,
    required this.errorMessage,
    this.errorCode,
    this.statusCode,
  });

  final String staffDisplayName;
  final DateTime workDate;
  final String recipient;
  final String method;
  final String shiftCode;
  final int deliveryAttempts;
  final DateTime failedAt;
  final String? errorCode;
  final String? statusCode;
  final String errorMessage;
}

abstract interface class UndeliveredInvitationLog {
  Future<List<UndeliveredInvitation>> read();
}

final class SupabaseUndeliveredInvitationLog
    implements UndeliveredInvitationLog {
  const SupabaseUndeliveredInvitationLog(this._client);

  final SupabaseClient _client;

  @override
  Future<List<UndeliveredInvitation>> read() async {
    final rows = await _client.rpc<List<dynamic>>(
      'read_undelivered_calendar_invitations',
    );
    return [
      for (final row in rows.cast<Map<String, dynamic>>())
        UndeliveredInvitation(
          staffDisplayName: row['staff_display_name'] as String,
          workDate: DateTime.parse(row['work_date'] as String),
          recipient: row['recipient'] as String,
          method: row['method'] as String,
          shiftCode: row['shift_code'] as String,
          deliveryAttempts: row['delivery_attempts'] as int,
          failedAt: DateTime.parse(row['delivery_failed_at'] as String),
          errorCode: row['delivery_error_code'] as String?,
          statusCode: row['delivery_status_code'] as String?,
          errorMessage: row['delivery_error_message'] as String,
        ),
    ];
  }
}
