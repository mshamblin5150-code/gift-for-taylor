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
}
