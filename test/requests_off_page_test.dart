import 'package:er_schedule/schedule/requests_off_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:schedule_rules_testing/schedule_rules_testing.dart';

void main() {
  testWidgets(
    'Request off accepts a range, another day, and removal from the range',
    (tester) async {
      final rules = await _openRequestDialog(tester);

      expect(
        find.text(
          'Choose dates from Sep 15 through Oct 31, 2026. '
          'The Manager can act on this month and next month.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Add a range'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('26').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('7 days selected'), findsOneWidget);
      expect(find.text('Sep 23, 2026'), findsOneWidget);

      await tester.tap(find.text('Add a range'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('3').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('8 days selected'), findsOneWidget);
      final middleDayChip = find.widgetWithText(InputChip, 'Sep 23, 2026');
      final chipRect = tester.getRect(middleDayChip);
      await tester.tapAt(Offset(chipRect.right - 18, chipRect.center.dy));
      await tester.pumpAndSettle();
      expect(find.text('7 days selected'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
      await tester.pumpAndSettle();

      final request = (await rules.store.requestsOff(pendingOnly: false))
          .single;
      expect(request.dates, [
        DateTime(2026, 9, 20),
        DateTime(2026, 9, 21),
        DateTime(2026, 9, 22),
        DateTime(2026, 9, 24),
        DateTime(2026, 9, 25),
        DateTime(2026, 9, 26),
        DateTime(2026, 10, 3),
      ]);
    },
  );

  testWidgets('Request off caps the selection at 31 days', (tester) async {
    await _openRequestDialog(tester);

    await tester.tap(find.text('Add a range'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('15').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('31 days selected'), findsOneWidget);

    await tester.tap(find.text('Add a range'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('16').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('16').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('31 days selected'), findsOneWidget);
    expect(
      find.text(
        'That would select 32 days. A Request off can include up to 31 days; '
        'Choose a shorter range.',
      ),
      findsOneWidget,
    );
  });
}

Future<ScheduleRules> _openRequestDialog(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final database = InMemoryScheduleDatabase(
    sections: const [ScheduleSection(id: 'nurses', name: 'Nurses')],
    rows: const [
      ScheduleRow(
        staffMemberId: 'alice',
        displayName: 'Alice',
        sectionId: 'nurses',
      ),
    ],
    grants: {'manager': Grants(manager: true)},
    releasedMonths: {DateTime(2026, 9), DateTime(2026, 10)},
  );
  final rules = scheduleRulesInMemory(database, actingAs: 'alice');
  await tester.pumpWidget(
    MaterialApp(
      home: RequestsOffPage(
        rules: rules,
        isManager: false,
        now: () => DateTime(2026, 9, 15),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FloatingActionButton, 'Request off'));
  await tester.pumpAndSettle();
  return rules;
}
