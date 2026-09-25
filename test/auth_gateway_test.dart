import 'package:er_schedule/auth/auth_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('requestCode identifies an invalid email response', () async {
    final gateway = _gatewayReturning(
      statusCode: 400,
      body: '{"code":"email_address_invalid","msg":"invalid email"}',
    );

    await expectLater(
      gateway.requestCode('mistyped'),
      throwsA(
        isA<InvalidEmailAddress>().having(
          (failure) => failure.cause,
          'cause',
          isA<AuthException>(),
        ),
      ),
    );
  });

  test('requestCode preserves a provider-side failure', () async {
    final gateway = _gatewayReturning(
      statusCode: 500,
      body: '{"code":"unexpected_failure","msg":"mail quota reached"}',
    );

    await expectLater(
      gateway.requestCode('nurse@example.com'),
      throwsA(
        isA<SignInCodeDeliveryFailed>().having(
          (failure) => failure.cause.toString(),
          'cause',
          contains('mail quota reached'),
        ),
      ),
    );
  });
}

SupabaseAuthGateway _gatewayReturning({
  required int statusCode,
  required String body,
}) {
  final client = SupabaseClient(
    'https://example.supabase.co',
    'test-key',
    authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
    httpClient: MockClient(
      (_) async => http.Response(
        body,
        statusCode,
        headers: const {
          'content-type': 'application/json',
          'x-supabase-api-version': '2024-01-01',
        },
      ),
    ),
  );
  addTearDown(client.dispose);
  return SupabaseAuthGateway(client);
}
