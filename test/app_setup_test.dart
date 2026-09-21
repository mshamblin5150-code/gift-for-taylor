import 'package:er_schedule/setup/app_setup_page.dart';
import 'package:er_schedule/help/help_page.dart';
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

  testWidgets('setup Help keeps Maintainer guidance for a Maintainer', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: AppSetupPage(helpRole: HelpRole.maintainer)),
    );
    await tester.scrollUntilVisible(find.text('Setup Help'), 250);
    await tester.tap(find.text('Setup Help'));
    await tester.pumpAndSettle();
    expect(find.text('Maintainer repairs'), findsOneWidget);
    expect(find.text('Accept your Invite'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
