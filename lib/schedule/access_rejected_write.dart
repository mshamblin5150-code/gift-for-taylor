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
    switch (refusalFor(error.code)) {
      case MonthStartRefusal.alreadyStarted:
        throw const MonthAlreadyStarted();
      case MonthStartRefusal.previousMonthNotStarted:
        throw PreviousMonthNotStarted();
    }
    rethrow;
  }
}

/// Maps Call-in refusals to domain values so pages never inspect backend text.
Future<T> mapCallInRefusal<T>(Future<T> Function() command) async {
  try {
    return await mapAccessRejected(command);
  } on PostgrestException catch (error) {
    if (refusalFor(error.code) case final CallInRefusal reason) {
      throw CallInRefused(reason);
    }
    rethrow;
  }
}

/// Maps Swap proposal refusals to domain values so pages never inspect SQL
/// messages or duplicate the rules that produced them.
Future<T> mapSwapProposalRefusal<T>(Future<T> Function() command) async {
  try {
    return await mapAccessRejected(command);
  } on PostgrestException catch (error) {
    if (refusalFor(error.code) case final SwapProposalRefusal reason) {
      throw SwapProposalRefused(reason);
    }
    rethrow;
  }
}

/// Maps Giveaway proposal refusals to stable client-facing reasons.
Future<T> mapGiveawayProposalRefusal<T>(Future<T> Function() command) async {
  try {
    return await mapAccessRejected(command);
  } on PostgrestException catch (error) {
    if (refusalFor(error.code) case final GiveawayProposalRefusal reason) {
      throw GiveawayProposalRefused(reason);
    }
    rethrow;
  }
}
