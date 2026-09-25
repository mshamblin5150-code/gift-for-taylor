import 'dart:convert';

import 'package:er_schedule/auth/auth_gateway.dart';
import 'package:er_schedule/auth/sign_in_failure_log.dart';
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

  test(
    'failure log records the provider reply without the email address',
    () async {
      late http.Request recordedRequest;
      final client = _clientWith(
        MockClient((request) async {
          recordedRequest = request;
        return http.Response('', 204, request: request);
        }),
      );
      addTearDown(client.dispose);

      await SupabaseSignInFailureLog(client).record(
        const SignInCodeDeliveryFailed(
          AuthApiException(
            'mail quota reached',
            statusCode: '500',
            code: 'unexpected_failure',
          ),
        ),
        StackTrace.empty,
      );

      expect(recordedRequest.url.path, endsWith('/rpc/record_sign_in_failure'));
      expect(jsonDecode(recordedRequest.body), {
        'p_error_code': 'unexpected_failure',
        'p_status_code': '500',
        'p_error_message': 'mail quota reached',
      });
      expect(recordedRequest.body, isNot(contains('nurse@example.com')));
    },
  );
}

SupabaseAuthGateway _gatewayReturning({
  required int statusCode,
  required String body,
}) {
  final client = _clientWith(
    MockClient(
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

SupabaseClient _clientWith(http.Client httpClient) => SupabaseClient(
  'https://example.supabase.co',
  'test-key',
  authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
  httpClient: httpClient,
);
