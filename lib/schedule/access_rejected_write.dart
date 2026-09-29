import 'package:schedule_rules/schedule_rules.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../refusal_code.dart';

extension CallInRefusalCode on CallInRefusal {
  String get code => switch (this) {
    CallInRefusal.recorderNotWorking => 'P2811',
    CallInRefusal.targetNotWorking => 'P2812',
    CallInRefusal.settled => 'P2813',
    CallInRefusal.notRecorded => 'P2848',
  };
}

extension SwapProposalRefusalCode on SwapProposalRefusal {
  String get code => switch (this) {
    SwapProposalRefusal.differentStaffRequired => 'P2814',
    SwapProposalRefusal.equalCountsRequired => 'P2815',
    SwapProposalRefusal.shiftLimitExceeded => 'P2816',
    SwapProposalRefusal.duplicateDate => 'P2817',
    SwapProposalRefusal.colleagueNotInvited => 'P2818',
    SwapProposalRefusal.dayNotFuture => 'P2819',
    SwapProposalRefusal.sourceUnavailable => 'P2820',
    SwapProposalRefusal.destinationUnavailable => 'P2821',
    SwapProposalRefusal.noChange => 'P2822',
    SwapProposalRefusal.pickupIneligible => 'P2846',
  };
}

extension GiveawayProposalRefusalCode on GiveawayProposalRefusal {
  String get code => switch (this) {
    GiveawayProposalRefusal.differentStaffRequired => 'P2823',
    GiveawayProposalRefusal.shiftsRequired => 'P2824',
    GiveawayProposalRefusal.shiftLimitExceeded => 'P2825',
    GiveawayProposalRefusal.duplicateDate => 'P2826',
    GiveawayProposalRefusal.colleagueNotInvited => 'P2827',
    GiveawayProposalRefusal.dayNotFuture => 'P2828',
    GiveawayProposalRefusal.sourceUnavailable => 'P2829',
    GiveawayProposalRefusal.colleagueIneligible => 'P2830',
  };
}

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
    final reason = valueForRefusalCode(
      CallInRefusal.values,
      error.code,
      (reason) => reason.code,
    );
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
    final reason = valueForRefusalCode(
      SwapProposalRefusal.values,
      error.code,
      (reason) => reason.code,
    );
    if (reason != null) throw SwapProposalRefused(reason);
    rethrow;
  }
}

/// Maps Giveaway proposal refusals to stable client-facing reasons.
Future<T> mapGiveawayProposalRefusal<T>(Future<T> Function() command) async {
  try {
    return await mapAccessRejected(command);
  } on PostgrestException catch (error) {
    final reason = valueForRefusalCode(
      GiveawayProposalRefusal.values,
      error.code,
      (reason) => reason.code,
    );
    if (reason != null) throw GiveawayProposalRefused(reason);
    rethrow;
  }
}
