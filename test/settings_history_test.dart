import 'package:er_schedule/settings/settings_history.dart';
import 'package:er_schedule/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:schedule_rules_testing/schedule_rules_testing.dart';

import 'support/in_memory_settings_history.dart';
import 'support/app_dependencies.dart';

void main() {
  final rules = scheduleRulesInMemory(
    InMemoryScheduleDatabase(sections: const []),
    actingAs: 'viewer',
  );
  final history = InMemorySettingsHistory([
    SettingsHistoryEntry(
      kind: 'Print wording',
      actor: 'Taylor',
      changedAt: DateTime.utc(2026, 9, 22, 12),
      before: {'title': 'Old'},
      after: {'title': 'New'},
      repairReason: 'Corrected a typo',
    ),
  ]);

  Future<void> showSettings(WidgetTester tester, Access access) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          scheduleRules: rules,
          noticeGateway: const NoopNoticeGateway(),
          access: access,
          settingsHistory: history,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Unit settings access shows Settings history and its entries', (
    tester,
  ) async {
    await showSettings(tester, Access(grants: Grants(administrator: true)));

    expect(find.text('Settings history'), findsOneWidget);
    await tester.tap(find.text('Settings history'));
    await tester.pumpAndSettle();

    expect(find.text('Print wording'), findsOneWidget);
    expect(find.textContaining('Taylor'), findsOneWidget);
    expect(find.textContaining('Corrected a typo'), findsOneWidget);
    expect(find.textContaining('Old'), findsOneWidget);
    expect(find.textContaining('New'), findsOneWidget);
  });

  testWidgets('Staff cannot see Settings history', (tester) async {
    await showSettings(tester, Access(grants: Grants()));

    expect(find.text('Settings history'), findsNothing);
  });
}
