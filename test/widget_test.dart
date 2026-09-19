// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:er_schedule/schedule/month_grid_page.dart';
import 'package:schedule_rules/schedule_rules.dart';

void main() {
  testWidgets('current month shows Section bands, weekdays, and weekends', (
    tester,
  ) async {
    await tester.pumpWidget(
      MonthGridPage.testable(
        month: DateTime(2026, 9),
        sections: const [
          ScheduleSection(id: 'days', name: 'State dayshift RN'),
          ScheduleSection(id: 'nights', name: 'PRN nightshift RN'),
        ],
      ),
    );

    expect(find.text('September 2026'), findsOneWidget);
    expect(find.text('State dayshift RN'), findsOneWidget);
    expect(find.text('PRN nightshift RN'), findsOneWidget);
    expect(find.text('T'), findsWidgets);
    expect(find.byKey(const ValueKey('weekday-2026-09-18')), findsNWidgets(2));
    expect(find.byKey(const ValueKey('weekend-2026-09-19')), findsNWidgets(2));
  });
}
