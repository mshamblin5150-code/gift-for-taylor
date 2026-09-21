import 'package:schedule_rules_testing/schedule_rules_testing.dart';
import 'package:er_schedule/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

void main() {
  testWidgets('Maintainer sees Unit controls without Staff calendar settings', (
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
          scheduleRules: rules,
          access: Access(grants: Grants(), maintainer: true),
          onCalendarFeed: () {},
          onManageStaff: () async {},
        ),
      ),
    );
    expect(find.text('Unit'), findsOneWidget);
    expect(find.text('Sections'), findsOneWidget);
    expect(find.text('My calendar'), findsNothing);
  });
}
