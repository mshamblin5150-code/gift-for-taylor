import 'package:er_schedule/schedule/shift_codes_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

void main() {
  testWidgets('pasted overlong code and meaning are refused on save', (
    tester,
  ) async {
    final rules = ScheduleRules.inMemory(
      InMemoryScheduleDatabase(sections: const [], editors: const {'manager'}),
      actingAs: 'manager',
    );
    await tester.pumpWidget(MaterialApp(home: ShiftCodesPage(rules: rules)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add code'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Code'), 'C' * 9);
    await tester.enterText(
      find.widgetWithText(TextField, 'Meaning (optional)'),
      'M' * 41,
    );
    expect(find.text('C' * 9), findsOneWidget);
    expect(find.text('M' * 41), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.textContaining('Use at most 8 characters'), findsOneWidget);
    expect(find.text('Add Shift code'), findsOneWidget);
  });

  testWidgets('Manager sees working Shift codes whose times are missing', (
    tester,
  ) async {
    final database = InMemoryScheduleDatabase(
      sections: const [],
      editors: const {'manager'},
    );
    final rules = ScheduleRules.inMemory(database, actingAs: 'manager');
    await rules.saveShiftCode(const LegendCode('CUSTOM', isWorking: true));

    await tester.pumpWidget(MaterialApp(home: ShiftCodesPage(rules: rules)));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('without times appear as all-day'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(find.text('CUSTOM'), 250);
    expect(
      find.text('Time not set · No Coverage window · Worked shift'),
      findsWidgets,
    );
  });
}
