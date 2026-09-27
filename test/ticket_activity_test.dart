import 'dart:convert';

import 'package:er_schedule/tickets/ticket_activity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('recent actions can be cleared at an account boundary', () {
    final actions = TicketActivityLog()..screenVisited('Schedule');

    actions.clear();

    expect(actions.snapshot(), isEmpty);
  });

  test('recent actions stay bounded and keep the newest actions', () {
    final actions = TicketActivityLog(limit: 3)
      ..screenVisited('Schedule')
      ..screenVisited('Swaps')
      ..rpcCalled('propose_swap')
      ..refusalRecorded('P2814');

    expect(actions.snapshot(), [
      'Screen: Swaps',
      'RPC: propose_swap',
      'Refusal: P2814',
    ]);
  });

  test('RPC tracking never captures text the person typed', () async {
    const typedText = 'patient detail that must stay private';
    final actions = TicketActivityLog();
    final client = TicketActivityHttpClient(
      MockClient.streaming((request, bodyStream) async {
        final body = await utf8.decoder.bind(bodyStream).join();
        expect(body, contains(typedText));
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(jsonEncode({'code': 'P2814', 'message': typedText})),
          ),
          400,
        );
      }),
      actions,
    );

    await client.post(
      Uri.parse('https://example.test/rest/v1/rpc/propose_swap'),
      body: jsonEncode({'p_reason': typedText}),
    );

    final captured = actions.snapshot().join(' | ');
    expect(captured, contains('RPC: propose_swap'));
    expect(captured, contains('Refusal: P2814'));
    expect(captured, isNot(contains(typedText)));
  });
}
