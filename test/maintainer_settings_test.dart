import 'package:schedule_rules_testing/schedule_rules_testing.dart';
import 'package:er_schedule/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'support/app_dependencies.dart';
import 'support/repair.dart';

void main() {
  testWidgets('Maintainer sees marked controls without ambient authority', (
    tester,
  ) async {
    final rules = scheduleRulesInMemory(
      InMemoryScheduleDatabase(
        grants: {'manager': Grants(manager: true)},
        sections: const [],
      ),
      actingAs: 'manager',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          maintainerRepairController: noopRepairController(),
          scheduleRules: rules,
          noticeGateway: const NoopNoticeGateway(),
          access: Access(
            grants: Grants(),
            maintainer: true,
            ownStaffMemberId: 'maintainer',
          ),
          onCalendarFeed: () {},
          onManageStaff: () async {},
        ),
      ),
    );
    expect(find.text('Maintainer repairs'), findsOneWidget);
    expect(find.text('Unit'), findsNothing);
    expect(find.text('Manager controls'), findsOneWidget);
    expect(find.text('Sections'), findsOneWidget);
    expect(
      find.text('Requires a Repair — tap to break the glass'),
      findsWidgets,
    );
    expect(find.text('My calendar'), findsOneWidget);
  });
}
