import 'support/in_memory_staff_gateway.dart';
import 'support/app_dependencies.dart';

import 'package:schedule_rules_testing/schedule_rules_testing.dart';
import 'package:er_schedule/schedule/approval_queue_page.dart';
import 'package:er_schedule/schedule/month_grid_page.dart';
import 'package:er_schedule/staff/staff_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'support/repair.dart';

class _Swaps extends Fake implements SwapStore {
  final items = <Swap>[];
  @override
  Future<List<Swap>> swaps() async => items;
  @override
  Future<void> approveSwap(String id) async =>
      items.removeWhere((s) => s.id == id);
  @override
  Future<void> declineSwap(String id, {String? reason}) async =>
      items.removeWhere((s) => s.id == id);
  @override
  Stream<void> updates() => const Stream.empty();
}

class _Pickups extends Fake implements OpenShiftStore {
  final items = <OpenShiftPickup>[];
  final shifts = <OpenShift>[];
  @override
  Future<List<OpenShiftPickup>> pickups() async => items;
  @override
  Future<List<OpenShift>> openShifts() async => shifts;
  @override
  Future<void> approvePickup(String id) async =>
      items.removeWhere((p) => p.id == id);
  @override
  Future<void> declinePickup(String id, {String? reason}) async =>
      items.removeWhere((p) => p.id == id);
  @override
  Stream<void> updates() => const Stream.empty();
}

void main() {
  final month = DateTime(2026, 9);
  final requestDay = DateTime(2026, 9, 20);
  final pickupDay = DateTime(2026, 9, 23);
  final swapDay = DateTime(2026, 10, 10);

  testWidgets('Manager confirms a pending Invite in the approval queue', (
    tester,
  ) async {
    final invites = InMemoryStaffGateway()
      ..invites = [
        PendingInviteAcceptance(
          inviteId: 'invite',
          staffMemberName: 'Jane Kemp',
          personalEmail: 'bsmith88@gmail.com',
          acceptedAt: DateTime(2026, 9, 18),
        ),
      ];
    final db = InMemoryScheduleDatabase(
      sections: const [ScheduleSection(id: 'nurses', name: 'Nurses')],
      grants: {'manager': Grants(manager: true)},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ApprovalQueuePage(
          rules: scheduleRulesInMemory(db, actingAs: 'manager'),
          swapStore: _Swaps(),
          openShiftStore: _Pickups(),
          staffGateway: invites,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Jane Kemp accepted as bsmith88@gmail.com'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm').last);
    await tester.pumpAndSettle();
    expect(invites.confirmedInviteId, 'invite');
    expect(find.text('Nothing awaiting approval.'), findsOneWidget);
  });

  testWidgets('Manager queue combines and orders all three pending decisions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = InMemoryScheduleDatabase(
      sections: const [ScheduleSection(id: 'nurses', name: 'Nurses')],
      rows: const [
        ScheduleRow(
          staffMemberId: 'alice',
          displayName: 'Alice',
          sectionId: 'nurses',
        ),
        ScheduleRow(
          staffMemberId: 'bob',
          displayName: 'Bob',
          sectionId: 'nurses',
        ),
      ],
      grants: {'manager': Grants(manager: true)},
      releasedMonths: {month, DateTime(2026, 10)},
    );
    final manager = scheduleRulesInMemory(db, actingAs: 'manager');
    await scheduleRulesInMemory(
      db,
      actingAs: 'alice',
    ).requestOff(RequestOffDraft(dates: [requestDay]));
    db.seedPendingRequestsOff(
      await manager.store.requestsOff(pendingOnly: false),
    );
    db.seedUnreadRequestOffNotices('alice', 1);
    final swaps = _Swaps()
      ..items.add(
        Swap(
          id: 'swap',
          requesterId: 'alice',
          colleagueId: 'bob',
          requesterShifts: [
            SwapShift(date: swapDay, shiftCode: 'D', targetCode: ''),
          ],
          colleagueShifts: [
            SwapShift(date: swapDay, shiftCode: 'N', targetCode: ''),
          ],
          status: SwapStatus.accepted,
        ),
      );
    final pickups = _Pickups()
      ..shifts.add(
        OpenShift(
          id: 'open',
          sectionId: 'nurses',
          date: pickupDay,
          shiftCode: 'D',
          jobRole: JobRole.rn,
        ),
      )
      ..items.add(
        const OpenShiftPickup(
          id: 'pickup',
          openShiftId: 'open',
          staffMemberId: 'bob',
          status: PickupStatus.pending,
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: MonthGridPage(
          noticeGateway: const NoopNoticeGateway(),
          repairController: noopRepairController(),
          access: db.accessFor('manager'),
          rules: manager,
          month: month,
          swapStore: swaps,
          openShiftStore: pickups,
          now: () => DateTime(2026, 9, 19),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Approval queue'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byTooltip('Approval queue'),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Approval queue'));
    await tester.pumpAndSettle();
    expect(find.byType(ApprovalQueuePage), findsOneWidget);
    expect(find.textContaining('Request off — Alice'), findsOneWidget);
    expect(find.textContaining('Open shift pickup — Bob'), findsOneWidget);
    expect(find.textContaining('Swap — Alice ↔ Bob'), findsOneWidget);
    final requestY = tester
        .getTopLeft(find.textContaining('Request off — Alice'))
        .dy;
    final pickupY = tester
        .getTopLeft(find.textContaining('Open shift pickup — Bob'))
        .dy;
    final swapY = tester
        .getTopLeft(find.textContaining('Swap — Alice ↔ Bob'))
        .dy;
    expect(requestY, lessThan(pickupY));
    expect(pickupY, lessThan(swapY));

    await tester.tap(find.widgetWithText(FilledButton, 'Approve').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Covered');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Request off — Alice'), findsNothing);
    final decided = (await scheduleRulesInMemory(
      db,
      actingAs: 'alice',
    ).store.requestsOff(pendingOnly: false)).single;
    expect(decided.decision, RequestOffDecision.approved);
    expect(decided.decisionReason, 'Covered');
    expect(
      await scheduleRulesInMemory(
        db,
        actingAs: 'alice',
      ).store.unreadRequestOffNotices(),
      1,
    );
  });

  testWidgets('Staff member has no Manager queue entry', (tester) async {
    final db = InMemoryScheduleDatabase(
      sections: const [ScheduleSection(id: 'nurses', name: 'Nurses')],
      rows: const [
        ScheduleRow(
          staffMemberId: 'alice',
          displayName: 'Alice',
          sectionId: 'nurses',
        ),
      ],
      grants: {'manager': Grants(manager: true)},
      releasedMonths: {month},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MonthGridPage(
          noticeGateway: const NoopNoticeGateway(),
          repairController: noopRepairController(),
          access: db.accessFor('alice'),
          rules: scheduleRulesInMemory(db, actingAs: 'alice'),
          month: month,
          staffMemberId: 'alice',
          swapStaffMemberId: 'alice',
          swapStore: _Swaps(),
          openShiftStore: _Pickups(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Approval queue'), findsNothing);
  });
}
