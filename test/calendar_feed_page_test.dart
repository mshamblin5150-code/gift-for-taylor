import 'package:er_schedule/calendar/calendar_feed_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Gateway implements CalendarFeedGateway {
  _Gateway({this.currentChannel = 'feed', this.disconnected = const []});

  String currentChannel;
  List<DisconnectedCalendarSubscription> disconnected;

  @override
  Future<String> channel() async => currentChannel;

  @override
  Future<List<CalendarSubscription>> subscriptions() async => [];

  @override
  Future<List<DisconnectedCalendarSubscription>>
  disconnectedSubscriptions() async => disconnected;

  @override
  Future<Uri> createSubscription(String name) async =>
      Uri.parse('webcal://example.test');

  @override
  Future<void> revokeSubscription(String id) async {}

  @override
  Future<void> useInvitations() async {}
}

void main() {
  Future<void> openPage(WidgetTester tester, _Gateway gateway) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: CalendarFeedPage(gateway: gateway)),
    );
    await tester.pumpAndSettle();
  }

  DisconnectedCalendarSubscription subscription({DateTime? fetched}) {
    final revoked = DateTime.now().subtract(const Duration(days: 2));
    return DisconnectedCalendarSubscription(
      id: 'revoked',
      name: 'Kitchen iPad',
      revokedAt: revoked,
      lastFetchedAt: fetched,
    );
  }

  testWidgets('no Disconnected section appears before a revocation', (
    tester,
  ) async {
    await openPage(tester, _Gateway());
    expect(find.text('Disconnected'), findsNothing);
  });

  testWidgets('a post-revocation check-in confirms the calendar picked it up', (
    tester,
  ) async {
    final gateway = _Gateway(
      disconnected: [
        subscription(
          fetched: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      ],
    );
    await openPage(tester, gateway);
    await tester.scrollUntilVisible(find.text('Disconnected'), 200);
    expect(find.text('Kitchen iPad'), findsOneWidget);
    expect(
      find.textContaining('Picked up the disconnection 2 hours ago.'),
      findsOneWidget,
    );
    expect(find.text('Revoke'), findsNothing);
  });

  testWidgets('an old check-in calls for manual removal even on invitations', (
    tester,
  ) async {
    final revoked = DateTime.now().subtract(const Duration(days: 2));
    final gateway = _Gateway(
      currentChannel: 'invitations',
      disconnected: [
        DisconnectedCalendarSubscription(
          id: 'old',
          name: 'Old phone',
          revokedAt: revoked,
          lastFetchedAt: revoked.subtract(const Duration(hours: 1)),
        ),
      ],
    );
    await openPage(tester, gateway);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(
      find.textContaining(
        "Hasn't checked in since. If you still have this device, remove the subscription there.",
      ),
      findsOneWidget,
    );
    expect(find.text('Revoke'), findsNothing);
  });
}
