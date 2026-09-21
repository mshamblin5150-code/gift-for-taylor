import 'package:er_schedule/setup/app_setup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ordinary app link removes every Invite URL parameter and fragment', () {
    final link = ordinaryAppUri(
      Uri.parse(
        'https://example.invalid/schedule/?invite=secret&month=2026-09#section',
      ),
    );
    expect(link.toString(), 'https://example.invalid/schedule/');
  });

  testWidgets(
    'pending setup explains later notifications without asking permission',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: AppSetupPage(awaitingConfirmation: true)),
      );
      expect(find.textContaining('After the Manager confirms'), findsOneWidget);
      expect(find.text('Copy app link'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
