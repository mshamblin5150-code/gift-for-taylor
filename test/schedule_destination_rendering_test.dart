import 'package:er_schedule/schedule/month_grid_page.dart';
import 'package:er_schedule/schedule/schedule_destinations.dart';
import 'package:er_schedule/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:schedule_rules_testing/schedule_rules_testing.dart';

import 'support/app_dependencies.dart';

void main() {
  testWidgets('returning from a reload destination refreshes the month', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final month = DateTime(2026, 9);
    final database = InMemoryScheduleDatabase(
      sections: const [ScheduleSection(id: 'days', name: 'State dayshift RN')],
      rows: const [
        ScheduleRow(
          staffMemberId: 'rn-1',
          displayName: 'Day RN',
          sectionId: 'days',
        ),
      ],
      grants: {'manager': Grants(manager: true)},
      releasedMonths: {month},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MonthGridPage(
          dependencies: appDependencies(
            scheduleStore: database.storeFor('manager'),
            openShiftStore: database.openShiftStoreFor('manager'),
          ),
          access: database.accessFor('manager'),
          month: month,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('7A'), findsNothing);

    await tester.tap(find.byTooltip('Schedule actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Staffing minimums'));
    await tester.pumpAndSettle();
    expect(find.text('Unit coverage settings'), findsOneWidget);

    database.loadFromPage(month, [
      ScheduleCell(
        staffMemberId: 'rn-1',
        sectionId: 'days',
        date: DateTime(2026, 9, 18),
        shiftCode: '7A',
      ),
    ]);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('7A'), findsOneWidget);
  });

  testWidgets('returning from a Settings editor requests a month reload', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var reloads = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          dependencies: appDependencies(),
          access: Access(
            grants: Grants(manager: true),
            ownStaffMemberId: 'manager',
          ),
          destinationCallbacks: ScheduleDestinationCallbacks(
            onReloadMonth: () async => reloads += 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Sections'),
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text('Sections'));
    await tester.pumpAndSettle();
    expect(find.text('Staff list'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(reloads, 1);
  });
}
