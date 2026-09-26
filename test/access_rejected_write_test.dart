import 'package:er_schedule/schedule/access_rejected_write.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  for (final code in ['42501', '401', '403']) {
    test('Postgrest $code becomes AccessRejected with its cause', () async {
      final original = PostgrestException(message: 'Access denied', code: code);

      await expectLater(
        mapAccessRejected<void>(() => Future.error(original)),
        throwsA(
          isA<AccessRejected>().having((e) => e.cause, 'cause', same(original)),
        ),
      );
    });
  }

  test('other Postgrest errors pass through unchanged', () async {
    final original = PostgrestException(message: 'Conflict', code: '23505');

    await expectLater(
      mapAccessRejected<void>(() => Future.error(original)),
      throwsA(same(original)),
    );
  });

  test('month already started SQLSTATE maps to its page exception', () async {
    final error = PostgrestException(message: 'already started', code: 'P2791');
    await expectLater(
      mapStartMonthRefusal<void>(() => Future.error(error)),
      throwsA(isA<MonthAlreadyStarted>()),
    );
  });

  test('missing source month SQLSTATE maps to its page exception', () async {
    final error = PostgrestException(message: 'no source', code: 'P2792');
    await expectLater(
      mapStartMonthRefusal<void>(() => Future.error(error)),
      throwsA(isA<PreviousMonthNotStarted>()),
    );
  });

  test(
    'start month maps Manager rejection and keeps generic failures',
    () async {
      for (final code in ['42501', '23505']) {
        final error = PostgrestException(message: 'failure', code: code);
        await expectLater(
          mapStartMonthRefusal<void>(() => Future.error(error)),
          code == '42501'
              ? throwsA(isA<AccessRejected>())
              : throwsA(same(error)),
        );
      }
    },
  );

  test('Call-in SQLSTATEs map without exposing backend messages', () async {
    const reasons = {
      'P2811': CallInRefusal.recorderNotWorking,
      'P2812': CallInRefusal.targetNotWorking,
      'P2813': CallInRefusal.settled,
    };
    for (final MapEntry(:key, :value) in reasons.entries) {
      final error = PostgrestException(message: 'backend wording', code: key);
      await expectLater(
        mapCallInRefusal<void>(() => Future.error(error)),
        throwsA(
          isA<CallInRefused>().having((error) => error.reason, 'reason', value),
        ),
      );
    }
  });

  test('Call-in mapping keeps generic failures unchanged', () async {
    final error = PostgrestException(message: 'failure', code: '23505');
    await expectLater(
      mapCallInRefusal<void>(() => Future.error(error)),
      throwsA(same(error)),
    );
  });

  test('Swap SQLSTATEs map without exposing backend messages', () async {
    const reasons = {
      'P2814': SwapProposalRefusal.differentStaffRequired,
      'P2815': SwapProposalRefusal.equalCountsRequired,
      'P2816': SwapProposalRefusal.shiftLimitExceeded,
      'P2817': SwapProposalRefusal.duplicateDate,
      'P2818': SwapProposalRefusal.colleagueNotInvited,
      'P2819': SwapProposalRefusal.dayNotFuture,
      'P2820': SwapProposalRefusal.sourceUnavailable,
      'P2821': SwapProposalRefusal.destinationUnavailable,
      'P2822': SwapProposalRefusal.noChange,
    };
    for (final MapEntry(:key, :value) in reasons.entries) {
      final error = PostgrestException(message: 'backend wording', code: key);
      await expectLater(
        mapSwapProposalRefusal<void>(() => Future.error(error)),
        throwsA(
          isA<SwapProposalRefused>().having(
            (error) => error.reason,
            'reason',
            value,
          ),
        ),
      );
    }
  });

  test('Giveaway SQLSTATEs map without exposing backend messages', () async {
    const reasons = {
      'P2823': GiveawayProposalRefusal.differentStaffRequired,
      'P2824': GiveawayProposalRefusal.shiftsRequired,
      'P2825': GiveawayProposalRefusal.shiftLimitExceeded,
      'P2826': GiveawayProposalRefusal.duplicateDate,
      'P2827': GiveawayProposalRefusal.colleagueNotInvited,
      'P2828': GiveawayProposalRefusal.dayNotFuture,
      'P2829': GiveawayProposalRefusal.sourceUnavailable,
      'P2830': GiveawayProposalRefusal.colleagueIneligible,
    };
    for (final MapEntry(:key, :value) in reasons.entries) {
      final error = PostgrestException(message: 'backend wording', code: key);
      await expectLater(
        mapGiveawayProposalRefusal<void>(() => Future.error(error)),
        throwsA(
          isA<GiveawayProposalRefused>().having(
            (error) => error.reason,
            'reason',
            value,
          ),
        ),
      );
    }
  });
}
