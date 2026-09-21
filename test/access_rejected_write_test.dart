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
}
