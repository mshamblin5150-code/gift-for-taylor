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

/// Maps the two month lifecycle refusals that the month page words itself.
Future<T> mapStartMonthRefusal<T>(Future<T> Function() write) async {
  try {
    return await mapAccessRejected(write);
  } on PostgrestException catch (error) {
    if (error.code == 'P2791') throw const MonthAlreadyStarted();
    if (error.code == 'P2792') throw PreviousMonthNotStarted();
    rethrow;
  }
}
