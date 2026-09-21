import 'package:schedule_rules_testing/schedule_rules_testing.dart';
import 'package:er_schedule/schedule/month_grid_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

void main() {
  late InMemoryScheduleDatabase database;

  setUp(() {
    database = InMemoryScheduleDatabase(
      sections: const [ScheduleSection(id: 'days', name: 'State dayshift RN')],
      rows: const [
        ScheduleRow(
          staffMemberId: 'rn-1',
          displayName: 'Day RN',
          sectionId: 'days',
        ),
      ],
      editors: const {'manager'},
      releasedMonths: {
        DateTime(2026, 8),
        DateTime(2026, 9),
        DateTime(2026, 10),
      },
    );
  });

  testWidgets('Manager can use month arrows and actions at 320 px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var signOuts = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: MonthGridPage(
          access: database.accessFor('manager'),
          rules: scheduleRulesInMemory(database, actingAs: 'manager'),
          month: DateTime(2026, 9),
          onCalendarFeed: () {},
          onManageStaff: () async {},
          onSignOut: () => signOuts++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('September 2026'), findsOneWidget);

    await tester.tap(find.byTooltip('Schedule actions'));
    await tester.pumpAndSettle();
    expect(find.text('My calendar'), findsNothing);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(signOuts, 1);
  });

  for (final width in [375.0, 390.0, 428.0]) {
    testWidgets('Manager month controls stay reachable at $width px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: MonthGridPage(
            access: database.accessFor('manager'),
            rules: scheduleRulesInMemory(database, actingAs: 'manager'),
            month: DateTime(2026, 9),
            onCalendarFeed: () {},
            onManageStaff: () async {},
            onSignOut: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final previous = tester.getRect(find.byTooltip('Previous month'));
      final next = tester.getRect(find.byTooltip('Next month'));
      final actions = tester.getRect(find.byTooltip('Schedule actions'));
      for (final rect in [previous, next, actions]) {
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(width));
        expect(rect.width, greaterThanOrEqualTo(24));
        expect(rect.height, greaterThanOrEqualTo(24));
      }
      expect(previous.overlaps(actions), isFalse);
      expect(next.overlaps(actions), isFalse);

      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('September 2026'), findsOneWidget);

      await tester.tap(find.byTooltip('Schedule actions'));
      await tester.pumpAndSettle();
      expect(find.text('Browse requests'), findsOneWidget);
      await tester.tap(find.text('Requests off'));
      await tester.pumpAndSettle();
      expect(find.text('Request off approval queue'), findsOneWidget);
    });
  }

  for (final width in [320.0, 375.0, 390.0, 428.0]) {
    testWidgets('Staff member actions stay reachable at $width px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var calendarOpens = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: MonthGridPage(
            access: database.accessFor('rn-1'),
            rules: scheduleRulesInMemory(database, actingAs: 'rn-1'),
            month: DateTime(2026, 9),
            staffMemberId: 'rn-1',
            onCalendarFeed: () => calendarOpens++,
            onSignOut: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('September 2026'), findsOneWidget);

      await tester.tap(find.byTooltip('Schedule actions'));
      await tester.pumpAndSettle();
      expect(find.text('Manage Shift codes'), findsNothing);
      await tester.tap(find.text('My calendar'));
      await tester.pumpAndSettle();
      expect(calendarOpens, 1);

      await tester.tap(find.byTooltip('Schedule actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My Requests off'));
      await tester.pumpAndSettle();
      expect(find.text('My Requests off'), findsWidgets);
    });
  }

  testWidgets('wide Schedule keeps direct actions and Browse requests', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MonthGridPage(
          access: database.accessFor('manager'),
          rules: scheduleRulesInMemory(database, actingAs: 'manager'),
          month: DateTime(2026, 9),
          onCalendarFeed: () {},
          onManageStaff: () async {},
          onSignOut: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Schedule actions'), findsNothing);

    await tester.tap(find.byTooltip('More destinations'));
    await tester.pumpAndSettle();
    expect(find.text('My calendar'), findsNothing);
    await tester.tapAt(const Offset(20, 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Browse requests'));
    await tester.pumpAndSettle();
    expect(find.text('Requests off'), findsOneWidget);
  });
}
