import 'package:schedule_rules_testing/schedule_rules_testing.dart';
import 'package:er_schedule/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

void main() {
  testWidgets('Unit settings opens the Coverage pool editor', (tester) async {
    final database = InMemoryScheduleDatabase(
      sections: const [],
      editors: const {'manager'},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          scheduleRules: scheduleRulesInMemory(database, actingAs: 'manager'),
          openShiftStore: database.openShiftStoreFor('manager'),
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
