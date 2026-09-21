import 'package:schedule_rules/schedule_rules.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Translates rejected Schedule writes without changing other failures.
Future<T> mapAccessRejected<T>(Future<T> Function() write) async {
  try {
    return await write();
  } on PostgrestException catch (error) {
    if (error.code == '42501' || error.code == '401' || error.code == '403') {
      throw AccessRejected(error);
    }
    rethrow;
  }
}
