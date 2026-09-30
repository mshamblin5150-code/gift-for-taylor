import 'package:schedule_rules_testing/schedule_rules_testing.dart';
import 'package:er_schedule/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'support/app_dependencies.dart';
import 'support/repair.dart';

void main() {
  testWidgets('Unit settings opens the Coverage pool editor', (tester) async {
    final database = InMemoryScheduleDatabase(
      sections: const [],
      grants: {'manager': Grants(manager: true)},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          dependencies: appDependencies(
            repairController: noopRepairController(),
            undeliveredInvitationLog: FakeUndeliveredInvitationLog(),
            scheduleStore: (scheduleRulesInMemory(
              database,
              actingAs: 'manager',
            )).store,
            noticeGateway: const NoopNoticeGateway(),
            openShiftStore: database.openShiftStoreFor('manager'),
          ),
          onCalendarFeed: () {},
          onManageStaff: () async {},
          onOpenStaffDetails: (_) async {},
          access: Access(grants: Grants(administrator: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Staffing minimums'));
    await tester.pumpAndSettle();

    expect(find.text('Unit coverage settings'), findsOneWidget);
    expect(find.text('Edit standing Staffing minimums'), findsWidgets);
  });
}
