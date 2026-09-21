import 'package:er_schedule/schedule/approval_queue_page.dart';
import 'package:er_schedule/schedule/month_grid_page.dart';
import 'package:er_schedule/staff/staff_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

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

class _Invites extends Fake implements StaffGateway {
  final items = <PendingInviteAcceptance>[
    PendingInviteAcceptance(
      inviteId: 'invite',
      staffMemberName: 'Jane Kemp',
      personalEmail: 'bsmith88@gmail.com',
      acceptedAt: DateTime(2026, 9, 18),
    ),
  ];
  String? confirmed;
  String? rejected;

  @override
  Future<List<PendingInviteAcceptance>> pendingInviteAcceptances() async =>
      items;

  @override
  Future<void> confirmInviteAcceptance(String inviteId) async {
    confirmed = inviteId;
    items.clear();
  }

  @override
  Future<void> rejectInviteAcceptance(String inviteId) async {
    rejected = inviteId;
    items.clear();
  }
}

void main() {
  final month = DateTime(2026, 9);
  final requestDay = DateTime(2026, 9, 20);
  final pickupDay = DateTime(2026, 9, 23);
  final swapDay = DateTime(2026, 10, 10);

  testWidgets('Manager confirms a pending Invite in the approval queue', (
    tester,
  ) async {
    final invites = _Invites();
    final db = InMemoryScheduleDatabase(
      sections: const [ScheduleSection(id: 'nurses', name: 'Nurses')],
      editors: const {'manager'},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ApprovalQueuePage(
          rules: ScheduleRules.inMemory(db, actingAs: 'manager'),
          swapRules: SwapRules(_Swaps()),
          openShiftRules: OpenShiftRules(_Pickups()),
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
    expect(invites.confirmed, 'invite');
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
      editors: const {'manager'},
      releasedMonths: {month, DateTime(2026, 10)},
    );
    final manager = ScheduleRules.inMemory(db, actingAs: 'manager');
    await ScheduleRules.inMemory(
      db,
      actingAs: 'alice',
    ).requestOff(RequestOffDraft(dates: [requestDay]));
    final swaps = _Swaps()
      ..items.add(
        Swap(
          id: 'swap',
          requesterId: 'alice',
          colleagueId: 'bob',
          requesterDate: swapDay,
          colleagueDate: swapDay,
          requesterCode: 'D',
          colleagueCode: 'N',
          requesterTargetCode: '',
          colleagueTargetCode: '',
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
          rules: manager,
          month: month,
          swapRules: SwapRules(swaps),
          openShiftRules: OpenShiftRules(pickups),
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
    final decided = (await ScheduleRules.inMemory(
      db,
      actingAs: 'alice',
    ).myRequestsOff()).single;
    expect(decided.decision, RequestOffDecision.approved);
    expect(decided.decisionReason, 'Covered');
    expect(
      await ScheduleRules.inMemory(
        db,
        actingAs: 'alice',
      ).unreadRequestOffNotices(),
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
      editors: const {'manager'},
      releasedMonths: {month},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MonthGridPage(
          rules: ScheduleRules.inMemory(db, actingAs: 'alice'),
          month: month,
          staffMemberId: 'alice',
          swapStaffMemberId: 'alice',
          swapRules: SwapRules(_Swaps()),
          openShiftRules: OpenShiftRules(_Pickups()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Approval queue'), findsNothing);
  });
}
