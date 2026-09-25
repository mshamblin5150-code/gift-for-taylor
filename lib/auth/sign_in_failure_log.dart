import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_gateway.dart';

final class SignInFailureRecord {
  const SignInFailureRecord({
    required this.happenedAt,
    required this.message,
    this.code,
    this.statusCode,
  });

  final DateTime happenedAt;
  final String? code;
  final String? statusCode;
  final String message;
}

abstract interface class SignInFailureLog {
  Future<void> record(Object error, StackTrace stackTrace);
  Future<List<SignInFailureRecord>> read();
}

final class SupabaseSignInFailureLog implements SignInFailureLog {
  const SupabaseSignInFailureLog(this._client);

  final SupabaseClient _client;

  @override
  Future<void> record(Object error, StackTrace stackTrace) async {
    final cause = error is RequestCodeFailure ? error.cause : error;
    final authError = cause is AuthException ? cause : null;
    try {
      await _client.rpc<void>(
        'record_sign_in_failure',
        params: {
          'p_error_code': authError?.code,
          'p_status_code': authError?.statusCode,
          'p_error_message': authError?.message ?? cause.toString(),
        },
      );
    } catch (recordingError, recordingStackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'ER Schedule authentication',
          context: ErrorDescription(
            'while recording a sign-in failure; the record call also failed: '
            '$recordingError\n$recordingStackTrace',
          ),
        ),
      );
    }
  }

  @override
  Future<List<SignInFailureRecord>> read() async {
    final rows = await _client.rpc<List<dynamic>>('read_sign_in_failures');
    return [
      for (final row in rows.cast<Map<String, dynamic>>())
        SignInFailureRecord(
          happenedAt: DateTime.parse(row['happened_at'] as String),
          code: row['error_code'] as String?,
          statusCode: row['status_code'] as String?,
          message: row['error_message'] as String,
        ),
    ];
  }
}
