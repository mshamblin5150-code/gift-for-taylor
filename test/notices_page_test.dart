import 'package:er_schedule/notifications/notice_gateway.dart';
import 'package:er_schedule/notifications/notices_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _NoticeGateway implements NoticeGateway {
  PushState state = PushState.available;
  int testsSent = 0;

  @override
  Future<PushState> pushState() async => state;

  @override
  Future<void> allowPush() async => state = PushState.enabled;

  @override
  Future<void> disablePush() async => state = PushState.available;

  @override
  Future<void> sendTestPush() async => testsSent++;

  @override
  Future<List<StaffNotice>> notices() async => [
    StaffNotice(
      id: 'notice-1',
      title: 'Schedule released',
      body: 'March is ready to view.',
      createdAt: DateTime(2028, 3, 1),
      isRead: false,
    ),
  ];

  @override
  Future<void> markRead(String id) async {}
}

void main() {
  testWidgets('Staff allow notifications and send a test push', (tester) async {
    final gateway = _NoticeGateway();
    await tester.pumpWidget(MaterialApp(home: NoticesPage(gateway: gateway)));
    await tester.pumpAndSettle();

    expect(find.text('Schedule released'), findsOneWidget);
    await tester.tap(find.text('Allow notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Send test push'), findsOneWidget);

    await tester.tap(find.text('Send test push'));
    await tester.pumpAndSettle();
    expect(gateway.testsSent, 1);
    expect(find.text('Test push sent.'), findsOneWidget);
  });
}
