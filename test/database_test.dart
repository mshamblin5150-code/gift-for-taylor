import 'package:er_schedule/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final client = SupabaseClient('https://example.supabase.co', 'test-key');
  final database = Database(client);

  tearDownAll(client.dispose);

  for (final code in ['42501', '401', '403']) {
    test('Database translates Postgrest $code to AccessRejected', () async {
      final error = PostgrestException(message: 'Access denied', code: code);

      await expectLater(
        database.run<void>((_) => Future.error(error)),
        throwsA(
          isA<AccessRejected>().having((value) => value.cause, 'cause', error),
        ),
      );
    });
  }

  test('Database translates a known code to its Refusal', () async {
    final error = PostgrestException(
      message: 'No change',
      code: SwapProposalRefusal.noChange.code,
    );

    await expectLater(
      database.run<void>((_) => Future.error(error)),
      throwsA(
        isA<Refused>().having(
          (value) => value.refusal,
          'refusal',
          SwapProposalRefusal.noChange,
        ),
      ),
    );
  });

  test('Database rethrows an unknown Postgrest error untouched', () async {
    final error = PostgrestException(message: 'Conflict', code: '23505');

    await expectLater(
      database.run<void>((_) => Future.error(error)),
      throwsA(same(error)),
    );
  });
}
