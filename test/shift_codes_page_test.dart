import 'package:er_schedule/schedule/shift_codes_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

void main() {
  testWidgets('Manager sees working Shift codes whose times are missing', (
    tester,
  ) async {
    final database = InMemoryScheduleDatabase(
      sections: const [],
      editors: const {'manager'},
    );
    final rules = ScheduleRules.inMemory(database, actingAs: 'manager');

    await tester.pumpWidget(MaterialApp(home: ShiftCodesPage(rules: rules)));
    await tester.pumpAndSettle();

    expect(find.textContaining('without times appear as all-day'), findsOneWidget);
    expect(find.text('7A–7P · Worked shift'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('4P'), 250);
    expect(find.text('Time not set · Worked shift'), findsWidgets);
  });
}
