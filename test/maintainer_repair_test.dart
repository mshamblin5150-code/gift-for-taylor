import 'package:er_schedule/app.dart';
import 'package:er_schedule/maintainer/maintainer_repair.dart';
import 'package:er_schedule/maintainer/repair_controller.dart';
import 'package:er_schedule/maintainer/repair_gateway.dart';
import 'package:er_schedule/notifications/notice_gateway.dart';
import 'package:er_schedule/staff/access_row.dart';
import 'package:er_schedule/tickets/ticket_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:schedule_rules_testing/schedule_rules_testing.dart';

import 'support/app_dependencies.dart';
import 'support/in_memory_staff_gateway.dart';
import 'support/tickets.dart';

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

  final ticketRepair = MaintainerRepair(
    id: 'repair-370',
    category: RepairReasonCategory.investigation,
    openedAt: now,
    expiresAt: now.add(const Duration(hours: 1)),
    remaining: const Duration(hours: 1),
    ticketId: 'ticket-364',
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

  test('current_access row carries the Ticket that caused the Repair', () {
    final access = accessFromRow({
      'manager': true,
      'administrator': false,
      'maintainer': true,
      'staff_member_id': 'staff-370',
      'night_scheduler_section_ids': <dynamic>[],
      'repair_id': ticketRepair.id,
      'repair_reason_category': ticketRepair.category.value,
      'repair_detail': ticketRepair.detail,
      'repair_opened_at': ticketRepair.openedAt.toIso8601String(),
      'repair_expires_at': ticketRepair.expiresAt.toIso8601String(),
      'repair_seconds_remaining': 3600,
      'repair_ticket_id': ticketRepair.ticketId,
    });

    expect(access.activeRepair, ticketRepair);
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

  testWidgets('Repair surface can name an open Ticket as its cause', (
    tester,
  ) async {
    final gateway = _RepairGateway(ticketRepair);
    final controller = RepairController(gateway);
    final ticket = sampleTicket(state: TicketState.seen);
    await tester.pumpWidget(
      MaterialApp(
        home: MaintainerRepairPage(
          controller: controller,
          ticketGateway: InMemoryTicketGateway(maintainerTickets: [ticket]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ticket cause (optional)'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(ListView).last,
        matching: find.textContaining('Save did not work'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -420));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Investigating a fault'));
    await tester.pump();
    await tester.drag(find.byType(ListView).first, const Offset(0, -420));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Break the glass'));
    await tester.pumpAndSettle();

    expect(gateway.openedTicketId, ticket.id);
    expect(controller.repair, ticketRepair);
    controller.dispose();
  });

  testWidgets('persistent Repair indicator closes the Repair', (tester) async {
    final gateway = _RepairGateway(repair);
    final controller = RepairController(gateway)..synchronize(repair);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RepairBanner(controller: controller)),
      ),
    );

    expect(find.text('Repairing: Unit settings'), findsOneWidget);
    expect(find.text('Close this repair'), findsOneWidget);
    await tester.tap(find.text('Close this repair'));
    await tester.pumpAndSettle();

    expect(gateway.closeCount, 1);
    expect(controller.repair, isNull);
  });

  testWidgets('closing a linked Repair offers to close its Ticket as Done', (
    tester,
  ) async {
    final repairGateway = _RepairGateway(ticketRepair);
    final controller = RepairController(repairGateway)
      ..synchronize(ticketRepair);
    addTearDown(controller.dispose);
    final ticket = sampleTicket(state: TicketState.seen);
    final closedTicket = sampleTicket(
      state: TicketState.done,
      closeReason: 'The repair is live in this release.',
      closedAt: now,
    );
    final ticketGateway = InMemoryTicketGateway(
      maintainerTickets: [ticket],
      closeAnswers: {ticket.id: closedTicket},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepairBanner(
            controller: controller,
            ticketGateway: ticketGateway,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Close this repair'));
    await tester.pumpAndSettle();
    expect(find.text('Close linked Ticket?'), findsOneWidget);
    await tester.tap(find.text('Close Ticket as Done'));
    await tester.pumpAndSettle();
    expect(find.text('Close as Done'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('ticket-close-reason')),
      'The repair is live in this release.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Close Ticket'));
    await tester.pumpAndSettle();

    expect(ticketGateway.closes.single.ticketId, ticket.id);
    expect(ticketGateway.closes.single.outcome, TicketState.done);
    expect(
      ticketGateway.closes.single.reason,
      'The repair is live in this release.',
    );
    expect(repairGateway.closeCount, 1);
    expect(controller.repair, isNull);
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
        MaterialApp(
          home: Scaffold(body: RepairBanner(controller: controller)),
        ),
      );

      expect(find.text('Repairing: Investigating a fault'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(controller.repair, isNull);
      expect(gateway.closeCount, 0);
      expect(find.text('Repairing: Investigating a fault'), findsNothing);
    },
  );

  testWidgets('Repair indicator stays above routes and exits to Staff chrome', (
    tester,
  ) async {
    final now = DateTime.now();
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
      releasedMonths: {DateTime(now.year, now.month)},
      grants: {'manager': Grants(manager: true)},
    );

    await tester.pumpWidget(
      ScheduleApp(
        navigatorKey: navigatorKey,
        dependencies: appDependencies(
          authGateway: FakeAuthGateway(true),
          noticeGateway: const NoopNoticeGateway(PushState.enabled),
          scheduleStore: database.storeFor('nurse'),
          staffGateway: staffGateway,
          repairController: controller,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Repairing: Unit settings'), findsOneWidget);

    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(appBar: AppBar(title: Text('Repair route'))),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Repair route'), findsOneWidget);
    expect(find.text('Repairing: Unit settings'), findsOneWidget);

    await tester.tap(find.text('Close this repair'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Repairing: Unit settings'), findsNothing);
    expect(find.text('Repair route'), findsNothing);
    expect(controller.repair, isNull);
  });
}

final class _RepairGateway implements RepairGateway {
  _RepairGateway(this.result, {this.onClose});

  final MaintainerRepair result;
  final VoidCallback? onClose;
  RepairReasonCategory? openedCategory;
  String? openedDetail;
  String? openedTicketId;
  int closeCount = 0;

  @override
  Future<MaintainerRepair> open(
    RepairReasonCategory category,
    String? detail, {
    String? ticketId,
  }) async {
    openedCategory = category;
    openedDetail = detail;
    openedTicketId = ticketId;
    return result;
  }

  @override
  Future<void> close(String repairId) async {
    closeCount += 1;
    onClose?.call();
  }
}
