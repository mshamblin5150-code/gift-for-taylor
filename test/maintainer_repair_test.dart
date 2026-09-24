import 'package:er_schedule/app.dart';
import 'package:er_schedule/maintainer/maintainer_repair.dart';
import 'package:er_schedule/maintainer/repair_controller.dart';
import 'package:er_schedule/maintainer/repair_gateway.dart';
import 'package:er_schedule/notifications/notice_gateway.dart';
import 'package:er_schedule/schedule/month_grid_page.dart';
import 'package:er_schedule/staff/access_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:schedule_rules_testing/schedule_rules_testing.dart';

import 'support/app_dependencies.dart';
import 'support/in_memory_staff_gateway.dart';

void main() {
  final now = DateTime.now();
  final repair = MaintainerRepair(
    id: 'repair-304',
    category: RepairReasonCategory.unitSettings,
    detail: 'Restore the Coverage window',
    openedAt: now,
    expiresAt: now.add(const Duration(hours: 1)),
    remaining: const Duration(hours: 1),
  );

  test('current_access row carries the active Repair', () {
    final access = accessFromRow({
      'manager': true,
      'administrator': false,
      'maintainer': true,
      'staff_member_id': 'staff-304',
      'night_scheduler_section_ids': <dynamic>[],
      'repair_id': repair.id,
      'repair_reason_category': repair.category.value,
      'repair_detail': repair.detail,
      'repair_opened_at': repair.openedAt.toIso8601String(),
      'repair_expires_at': repair.expiresAt.toIso8601String(),
      'repair_seconds_remaining': 3600,
    });

    expect(access.ownStaffMemberId, 'staff-304');
    expect(access.activeRepair, repair);
    expect(access.isRepairAccess, isTrue);
  });

  testWidgets('Repair surface names the glass and opens a category', (
    tester,
  ) async {
    final gateway = _RepairGateway(repair);
    final controller = RepairController(gateway);
    await tester.pumpWidget(
      MaterialApp(home: MaintainerRepairPage(controller: controller)),
    );

    expect(find.text('Break the glass'), findsOneWidget);
    expect(find.text('Manager handover'), findsOneWidget);
    expect(find.text('Schedule or Month'), findsOneWidget);
    expect(find.text('Unit settings'), findsOneWidget);
    expect(find.text('Staff record or Invite'), findsOneWidget);
    expect(find.text('Investigating a fault'), findsOneWidget);
    expect(find.text('Something else'), findsOneWidget);

    await tester.tap(find.text('Unit settings'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Detail (optional)'),
      300,
      scrollable: find.byType(Scrollable),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Detail (optional)'),
      'Restore the Coverage window',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Break the glass'));
    await tester.pumpAndSettle();

    expect(gateway.openedCategory, RepairReasonCategory.unitSettings);
    expect(gateway.openedDetail, 'Restore the Coverage window');
    expect(controller.repair, repair);
    controller.dispose();
  });

  testWidgets('the wrench names the Repair and closes it on confirmation', (
    tester,
  ) async {
    final gateway = _RepairGateway(repair);
    final controller = RepairController(gateway)..synchronize(repair);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: _RepairChrome(controller: controller)),
    );

    expect(find.byIcon(Icons.build), findsOneWidget);
    // The Repair is named in the dialog, not in a banner taking a row of the
    // Schedule.
    expect(find.text('Repairing: Unit settings'), findsNothing);

    await tester.tap(find.byIcon(Icons.build));
    await tester.pumpAndSettle();
    expect(find.text('Repairing: Unit settings'), findsOneWidget);
    expect(find.text('Restore the Coverage window'), findsOneWidget);

    await tester.tap(find.text('Close this repair'));
    await tester.pumpAndSettle();

    expect(gateway.closeCount, 1);
    expect(controller.repair, isNull);
    expect(find.byIcon(Icons.build), findsNothing);
  });

  testWidgets('keeping the Repair leaves it open', (tester) async {
    final gateway = _RepairGateway(repair);
    final controller = RepairController(gateway)..synchronize(repair);
    await tester.pumpWidget(
      MaterialApp(home: _RepairChrome(controller: controller)),
    );

    await tester.tap(find.byIcon(Icons.build));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep repairing'));
    await tester.pumpAndSettle();

    expect(gateway.closeCount, 0);
    expect(controller.repair, repair);
    expect(find.byIcon(Icons.build), findsOneWidget);
    // The Repair is still open, so its hour timer is still running.
    controller.dispose();
  });

  testWidgets(
    'hour cap clears client authority without an early server close',
    (tester) async {
      final expiringRepair = MaintainerRepair(
        id: 'expiring-repair',
        category: RepairReasonCategory.investigation,
        openedAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(seconds: 1)),
        remaining: const Duration(seconds: 1),
      );
      final gateway = _RepairGateway(expiringRepair);
      final controller = RepairController(gateway)..synchronize(expiringRepair);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: _RepairChrome(controller: controller)),
      );

      expect(find.byIcon(Icons.build), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(controller.repair, isNull);
      expect(gateway.closeCount, 0);
      expect(find.byIcon(Icons.build), findsNothing);
    },
  );

  testWidgets('closing from the Schedule returns to Staff chrome', (
    tester,
  ) async {
    final month = DateTime(2026, 9);
    final staffGateway = InMemoryStaffGateway(
      currentId: 'nurse',
      actorRole: 'maintainer',
    )..activeRepair = repair;
    final repairGateway = _RepairGateway(
      repair,
      onClose: () => staffGateway.activeRepair = null,
    );
    final controller = RepairController(repairGateway)..synchronize(repair);
    addTearDown(controller.dispose);
    final navigatorKey = GlobalKey<NavigatorState>();
    final database = InMemoryScheduleDatabase(
      sections: const [ScheduleSection(id: 'days', name: 'Days')],
      rows: const [
        ScheduleRow(
          staffMemberId: 'nurse',
          displayName: 'Maintainer Nurse',
          sectionId: 'days',
        ),
      ],
      releasedMonths: {month},
      grants: {'manager': Grants(manager: true)},
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: MonthGridPage(
          repairController: controller,
          rules: scheduleRulesInMemory(database, actingAs: 'manager'),
          access: Access(
            grants: Grants(manager: true),
            ownStaffMemberId: 'nurse',
            maintainer: true,
            activeRepair: repair,
          ),
          month: month,
          onCalendarFeed: () {},
          noticeGateway: const NoopNoticeGateway(PushState.enabled),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.build), findsOneWidget);

    // A page opened under Manager authority must not outlive the Repair.
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: const Text('Repair route'),
            actions: [RepairAction(controller: controller)],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Repair route'), findsOneWidget);

    // The Schedule beneath keeps its own wrench; take the one on top.
    await tester.tap(find.byIcon(Icons.build).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close this repair'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byIcon(Icons.build), findsNothing);
    expect(find.text('Repair route'), findsNothing);
    expect(controller.repair, isNull);
  });
}

/// The wrench lives in an app bar, so the tests give it one.
class _RepairChrome extends StatelessWidget {
  const _RepairChrome({required this.controller});

  final RepairController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Schedule'),
      actions: [RepairAction(controller: controller)],
    ),
  );
}

final class _RepairGateway implements RepairGateway {
  _RepairGateway(this.result, {this.onClose});

  final MaintainerRepair result;
  final VoidCallback? onClose;
  RepairReasonCategory? openedCategory;
  String? openedDetail;
  int closeCount = 0;

  @override
  Future<MaintainerRepair> open(
    RepairReasonCategory category,
    String? detail,
  ) async {
    openedCategory = category;
    openedDetail = detail;
    return result;
  }

  @override
  Future<void> close(String repairId) async {
    closeCount += 1;
    onClose?.call();
  }
}
