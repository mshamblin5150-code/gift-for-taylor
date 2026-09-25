import 'package:schedule_rules_testing/schedule_rules_testing.dart';
import 'package:er_schedule/notifications/notice_gateway.dart';
import 'package:er_schedule/schedule/month_grid_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'support/app_dependencies.dart';
import 'support/repair.dart';

void main() {
  const section = ScheduleSection(id: 'nights', name: 'Night RN');
  const row = ScheduleRow(
    staffMemberId: 'nurse',
    displayName: 'Nurse',
    sectionId: 'nights',
  );
  final month = DateTime(2026, 9);

  Future<void> pumpAccess(WidgetTester tester, Access access) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final database = InMemoryScheduleDatabase(
      sections: const [section],
      rows: const [row],
      grants: {'manager': Grants(manager: true)},
      releasedMonths: {month},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MonthGridPage(
          repairController: noopRepairController(),
          rules: scheduleRulesInMemory(database, actingAs: 'manager'),
          access: access,
          month: month,
          staffMemberId: access.canRunSchedule ? null : access.ownStaffMemberId,
          swapStaffMemberId: access.canRunSchedule
              ? null
              : access.ownStaffMemberId,
          onCalendarFeed: () {},
          noticeGateway: _Notices(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Schedule actions'));
    await tester.pumpAndSettle();
  }

  final scenarios =
      <({String name, Access access, bool run, bool changeLog, bool own})>[
        (
          name: 'Manager',
          access: Access(
            grants: Grants(manager: true),
            ownStaffMemberId: 'nurse',
          ),
          run: true,
          changeLog: true,
          own: true,
        ),
        (
          name: 'Maintainer without a Repair',
          access: Access(
            grants: Grants(),
            maintainer: true,
            ownStaffMemberId: 'nurse',
          ),
          run: false,
          changeLog: false,
          own: true,
        ),
        (
          name: 'Maintainer with a Repair',
          access: Access(
            grants: Grants(),
            maintainer: true,
            ownStaffMemberId: 'nurse',
            activeRepair: MaintainerRepair(
              id: 'repair',
              category: RepairReasonCategory.scheduleOrMonth,
              openedAt: DateTime.utc(2026, 9, 24, 12),
              expiresAt: DateTime.utc(2026, 9, 24, 13),
            ),
          ),
          run: true,
          changeLog: true,
          own: true,
        ),
        (
          name: 'Administrator',
          access: Access(
            grants: Grants(administrator: true),
            ownStaffMemberId: 'nurse',
          ),
          run: false,
          changeLog: true,
          own: true,
        ),
        (
          name: 'Administrator without a Staff record',
          access: Access(grants: Grants(administrator: true)),
          run: false,
          changeLog: true,
          own: false,
        ),
        (
          name: 'Night scheduler',
          access: Access(
            grants: Grants(nightSchedulerSectionIds: {'nights'}),
            ownStaffMemberId: 'nurse',
          ),
          run: false,
          changeLog: true,
          own: true,
        ),
        (
          name: 'Administrator and Night scheduler',
          access: Access(
            grants: Grants(
              administrator: true,
              nightSchedulerSectionIds: {'nights'},
            ),
            ownStaffMemberId: 'nurse',
          ),
          run: false,
          changeLog: true,
          own: true,
        ),
        (
          name: 'Staff member',
          access: Access(grants: Grants(), ownStaffMemberId: 'nurse'),
          run: false,
          changeLog: false,
          own: true,
        ),
      ];

  for (final scenario in scenarios) {
    testWidgets('${scenario.name} sees permitted Schedule actions', (
      tester,
    ) async {
      await pumpAccess(tester, scenario.access);
      expect(
        find.text('Manage Shift codes'),
        scenario.run ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Change log'),
        scenario.changeLog ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('My calendar'),
        scenario.own ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Notices'),
        scenario.own ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('My Requests off'),
        scenario.own && !scenario.run ? findsOneWidget : findsNothing,
      );
      if (scenario.name == 'Maintainer without a Repair') {
        expect(find.text('Maintainer repairs (break glass)'), findsOneWidget);
        expect(
          find.text('Schedule and Month controls (requires Repair)'),
          findsOneWidget,
        );
        expect(find.text('Approvals (requires Repair)'), findsOneWidget);
        expect(
          find.text('Staff and Invite changes (requires Repair)'),
          findsOneWidget,
        );
      }
    });
  }

  testWidgets('Administrator reads an unreleased month without editing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final database = InMemoryScheduleDatabase(
      sections: const [section],
      rows: const [row],
      grants: {'manager': Grants(manager: true)},
    );
    final rules = scheduleRulesInMemory(database, actingAs: 'manager');
    await rules.startEmptyMonth(month);
    await tester.pumpWidget(
      MaterialApp(
        home: MonthGridPage(
          noticeGateway: const NoopNoticeGateway(),
          repairController: noopRepairController(),
          rules: rules,
          access: Access(
            grants: Grants(administrator: true),
            ownStaffMemberId: 'nurse',
          ),
          month: month,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining("hasn't been released"), findsNothing);
    expect(find.text('Nurse'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('cell-nurse-2026-09-18')));
    await tester.pumpAndSettle();
    expect(find.text('Other Shift code'), findsNothing);
  });

  testWidgets(
    'Administrator with Night scheduler grant edits only assigned Section',
    (tester) async {
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final database = InMemoryScheduleDatabase(
        sections: const [
          ScheduleSection(id: 'days', name: 'Day RN'),
          section,
        ],
        rows: const [
          ScheduleRow(
            staffMemberId: 'day-nurse',
            displayName: 'Day Nurse',
            sectionId: 'days',
          ),
          row,
        ],
        grants: {'manager': Grants(manager: true)},
        releasedMonths: {month},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MonthGridPage(
            noticeGateway: const NoopNoticeGateway(),
            repairController: noopRepairController(),
            rules: scheduleRulesInMemory(database, actingAs: 'manager'),
            access: Access(
              grants: Grants(
                administrator: true,
                nightSchedulerSectionIds: {'nights'},
              ),
              ownStaffMemberId: 'nurse',
            ),
            month: month,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('cell-day-nurse-2026-09-18')));
      await tester.pumpAndSettle();
      expect(find.text('Other Shift code'), findsNothing);
      expect(
        find.text('There are no actions available for this cell.'),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('cell-nurse-2026-09-18')));
      await tester.pumpAndSettle();
      expect(find.text('Other Shift code'), findsOneWidget);
    },
  );
}

final class _Notices extends Fake implements NoticeGateway {}
