import 'package:er_schedule/auth/repair_reason_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('Maintainer Unit write asks for and sends a repair reason', (
    tester,
  ) async {
    final key = GlobalKey<NavigatorState>();
    String? receivedReason;
    final client = RepairReasonClient(
      key,
      inner: MockClient((request) async {
        receivedReason = request.headers['x-repair-reason'];
        return http.Response('', 204);
      }),
    )..isMaintainer = true;
    await tester.pumpWidget(
      MaterialApp(navigatorKey: key, home: const Scaffold()),
    );

    final pending = client.send(
      http.Request(
        'POST',
        Uri.parse('https://unit.example/rest/v1/rpc/set_print_wording'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Maintainer repair reason'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Correct print title');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await pending;
    expect(receivedReason, 'Correct print title');
    client.close();
  });

  testWidgets('Maintainer read and ordinary Manager write need no prompt', (
    tester,
  ) async {
    final key = GlobalKey<NavigatorState>();
    final client = RepairReasonClient(
      key,
      inner: MockClient((request) async => http.Response('', 204)),
    )..isMaintainer = true;
    await tester.pumpWidget(
      MaterialApp(navigatorKey: key, home: const Scaffold()),
    );
    await client.send(
      http.Request(
        'POST',
        Uri.parse('https://unit.example/rest/v1/rpc/schedule_rows'),
      ),
    );
    expect(find.byType(AlertDialog), findsNothing);
    client.isMaintainer = false;
    await client.send(
      http.Request(
        'POST',
        Uri.parse('https://unit.example/rest/v1/rpc/set_print_wording'),
      ),
    );
    expect(find.byType(AlertDialog), findsNothing);
    client.close();
  });
}
