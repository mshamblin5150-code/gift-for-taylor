import 'package:er_schedule/schedule/open_shifts_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:schedule_rules_testing/schedule_rules_testing.dart';

void main() {
  testWidgets('explains Open shifts hidden by Schedule conflicts', (
    tester,
  ) async {
    final month = DateTime(2026, 9);
    final database = InMemoryScheduleDatabase(
      sections: const [ScheduleSection(id: 'nursing', name: 'Nursing')],
      rows: const [
        ScheduleRow(
          staffMemberId: 'rn-1',
          displayName: 'Day RN',
          sectionId: 'nursing',
        ),
      ],
      releasedMonths: {month},
    );
    database.seedHiddenOpenShiftCount('rn-1', 3);

    await tester.pumpWidget(
      MaterialApp(
        home: OpenShiftsPage(
          rules: database.openShiftStoreFor('rn-1'),
          scheduleRules: scheduleRulesInMemory(database, actingAs: 'rn-1'),
          month: month,
          staffMemberId: 'rn-1',
          isManager: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text("3 more Open shifts aren't available to you."),
      findsOneWidget,
    );
  });
}
