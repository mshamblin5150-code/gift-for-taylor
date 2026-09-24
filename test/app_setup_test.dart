import 'package:er_schedule/setup/app_setup_page.dart';
import 'package:er_schedule/help/help_page.dart';
import 'package:er_schedule/notifications/notice_gateway.dart';
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
        MaterialApp(
          home: AppSetupPage(
            noticeGateway: _NoticeGateway(PushState.available),
            awaitingConfirmation: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('After the Manager confirms'), findsWidgets);
      expect(find.text('Allow notifications'), findsNothing);
      expect(find.text('Copy app link'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('setup Help keeps Maintainer guidance for a Maintainer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppSetupPage(
          noticeGateway: _NoticeGateway(PushState.unsupported),
          helpRoles: const {HelpRole.maintainer},
        ),
      ),
    );
    await tester.scrollUntilVisible(find.text('Setup Help'), 250);
    await tester.tap(find.text('Setup Help'));
    await tester.pumpAndSettle();
    expect(find.text('Maintainer repairs'), findsOneWidget);
    expect(find.text('Accept your Invite'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('manual phone install steps remain visible without a prompt', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppSetupPage(
          noticeGateway: _NoticeGateway(PushState.unsupported),
          canAllowNotifications: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('iPhone:'), findsWidgets);
    expect(
      find.textContaining('Scroll the list of options down'),
      findsWidgets,
    );
    expect(find.textContaining('Edit Actions'), findsWidgets);
    expect(find.textContaining('leave it on'), findsWidgets);
    expect(find.textContaining('you will get no notifications'), findsWidgets);
    expect(find.textContaining('iPad:'), findsWidgets);
    expect(find.textContaining('View More'), findsWidgets);
    expect(find.textContaining('Android Chrome:'), findsWidgets);
    expect(find.textContaining('Install and create shortcut'), findsWidgets);
    expect(find.textContaining('Do not choose Create shortcut'), findsWidgets);
    expect(
      find.textContaining('sign in with the same personal email'),
      findsWidgets,
    );
    expect(find.text('Install on this device'), findsNothing);
    expect(find.text('Allow notifications'), findsNothing);
  });

  testWidgets('available push can be allowed on the setup page', (
    tester,
  ) async {
    final gateway = _NoticeGateway(PushState.available);
    await tester.pumpWidget(
      MaterialApp(
        home: AppSetupPage(noticeGateway: gateway, canAllowNotifications: true),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Allow notifications'));
    await tester.pumpAndSettle();

    expect(gateway.state, PushState.enabled);
    expect(find.text('Notifications can reach this place.'), findsOneWidget);
  });

  testWidgets('denied push points to settings', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppSetupPage(
          noticeGateway: _NoticeGateway(PushState.denied),
          canAllowNotifications: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('blocked in this place'), findsOneWidget);
    expect(find.text('Allow notifications'), findsNothing);
  });
}

final class _NoticeGateway implements NoticeGateway {
  _NoticeGateway(this.state);

  PushState state;

  @override
  Future<PushState> pushState() async => state;
  @override
  Future<void> allowPush() async => state = PushState.enabled;
  @override
  Future<void> disablePush() async => state = PushState.available;
  @override
  Future<List<StaffNotice>> notices() async => [];
  @override
  Future<void> markRead(String id) async {}
  @override
  Future<RuleBatchDetails> ruleBatchDetails(String id) async =>
      const RuleBatchDetails(plan: [], shifts: []);
}
