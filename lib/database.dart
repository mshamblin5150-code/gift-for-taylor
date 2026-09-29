import 'package:schedule_rules/schedule_rules.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The guarded route from application adapters to Supabase.
class Database {
  const Database(this._client);

  final SupabaseClient _client;

  Future<T> run<T>(Future<T> Function(SupabaseClient client) query) async {
    try {
      return await query(_client);
    } on PostgrestException catch (error, stackTrace) {
      if (error.code == '42501' || error.code == '401' || error.code == '403') {
        Error.throwWithStackTrace(AccessRejected(error), stackTrace);
      }
      final refusal = refusalFor(error.code);
      if (refusal != null) {
        Error.throwWithStackTrace(Refused(refusal), stackTrace);
      }
      rethrow;
    }
  }

  GoTrueClient get auth => _client.auth;

  RealtimeChannel channel(String name) => _client.channel(name);

  Future<void> removeChannel(RealtimeChannel channel) async {
    await _client.removeChannel(channel);
  }
}
