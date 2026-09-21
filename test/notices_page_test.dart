import 'package:er_schedule/notifications/notice_gateway.dart';
import 'package:er_schedule/notifications/notices_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _NoticeGateway implements NoticeGateway {
  PushState state = PushState.available;

  @override
  Future<PushState> pushState() async => state;

  @override
  Future<void> allowPush() async => state = PushState.enabled;

  @override
  Future<void> disablePush() async => state = PushState.available;

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

  @override
  Future<RuleBatchDetails> ruleBatchDetails(String id) async =>
      const RuleBatchDetails(plan: [], shifts: []);
}

void main() {
  testWidgets('Staff allow and turn off notifications', (tester) async {
    final gateway = _NoticeGateway();
    await tester.pumpWidget(MaterialApp(home: NoticesPage(gateway: gateway)));
    await tester.pumpAndSettle();

    expect(find.text('Schedule released'), findsOneWidget);
    await tester.tap(find.text('Allow notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Turn off on this device'), findsOneWidget);
    expect(find.text('Send test push'), findsNothing);
    await tester.tap(find.text('Turn off on this device'));
    await tester.pumpAndSettle();
    expect(gateway.state, PushState.available);
  });
}
