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

/// Maps Call-in refusals to domain values so pages never inspect backend text.
Future<T> mapCallInRefusal<T>(Future<T> Function() command) async {
  try {
    return await mapAccessRejected(command);
  } on PostgrestException catch (error) {
    final reason = switch (error.code) {
      'P2811' => CallInRefusal.recorderNotWorking,
      'P2812' => CallInRefusal.targetNotWorking,
      'P2813' => CallInRefusal.settled,
      _ => null,
    };
    if (reason != null) throw CallInRefused(reason);
    rethrow;
  }
}

/// Maps Swap proposal refusals to domain values so pages never inspect SQL
/// messages or duplicate the rules that produced them.
Future<T> mapSwapProposalRefusal<T>(Future<T> Function() command) async {
  try {
    return await mapAccessRejected(command);
  } on PostgrestException catch (error) {
    final reason = switch (error.code) {
      'P2814' => SwapProposalRefusal.differentStaffRequired,
      'P2815' => SwapProposalRefusal.equalCountsRequired,
      'P2816' => SwapProposalRefusal.shiftLimitExceeded,
      'P2817' => SwapProposalRefusal.duplicateDate,
      'P2818' => SwapProposalRefusal.colleagueNotInvited,
      'P2819' => SwapProposalRefusal.dayNotFuture,
      'P2820' => SwapProposalRefusal.sourceUnavailable,
      'P2821' => SwapProposalRefusal.destinationUnavailable,
      'P2822' => SwapProposalRefusal.noChange,
      _ => null,
    };
    if (reason != null) throw SwapProposalRefused(reason);
    rethrow;
  }
}

/// Maps Giveaway proposal refusals to stable client-facing reasons.
Future<T> mapGiveawayProposalRefusal<T>(Future<T> Function() command) async {
  try {
    return await mapAccessRejected(command);
  } on PostgrestException catch (error) {
    final reason = switch (error.code) {
      'P2823' => GiveawayProposalRefusal.differentStaffRequired,
      'P2824' => GiveawayProposalRefusal.shiftsRequired,
      'P2825' => GiveawayProposalRefusal.shiftLimitExceeded,
      'P2826' => GiveawayProposalRefusal.duplicateDate,
      'P2827' => GiveawayProposalRefusal.colleagueNotInvited,
      'P2828' => GiveawayProposalRefusal.dayNotFuture,
      'P2829' => GiveawayProposalRefusal.sourceUnavailable,
      'P2830' => GiveawayProposalRefusal.colleagueIneligible,
      _ => null,
    };
    if (reason != null) throw GiveawayProposalRefused(reason);
    rethrow;
  }
}
