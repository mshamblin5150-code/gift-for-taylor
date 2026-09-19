import 'package:er_schedule/staff/staff_gateway.dart';
import 'package:er_schedule/staff/staff_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

void main() {
  const days = StaffSection(id: 'days', name: 'State dayshift RN');
  const nights = StaffSection(id: 'nights', name: 'PRN nightshift RN');
  const alex = StaffListMember(
    id: 'staff-1',
    displayName: 'Alex Tech',
    cellNumber: '5551112222',
    sectionId: 'days',
    displayOrder: 0,
  );

  late InMemoryScheduleDatabase database;
  late ScheduleRules rules;

  setUp(() {
    database = InMemoryScheduleDatabase(
      sections: const [
        ScheduleSection(id: 'days', name: 'State dayshift RN'),
        ScheduleSection(id: 'nights', name: 'PRN nightshift RN'),
      ],
      rows: const [
        ScheduleRow(
          staffMemberId: 'staff-1',
          displayName: 'Alex Tech',
          sectionId: 'days',
        ),
      ],
    );
    rules = ScheduleRules.inMemory(database, actingAs: 'manager');
  });

  testWidgets('Manager adds a Staff member and opens their Invite text', (
    tester,
  ) async {
    final gateway = _FakeStaffGateway(
      const StaffList(sections: [days], members: []),
    );
    final composer = _FakeInviteComposer();

    await tester.pumpWidget(
      MaterialApp(
        home: StaffListPage(
          gateway: gateway,
          rules: rules,
          inviteComposer: composer,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Staff member'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Name'),
      'Taylor Nurse',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Cell number'),
      '5558675309',
    );
    await tester.tap(find.text('Add and text Invite'));
    await tester.pumpAndSettle();

    expect(gateway.added?.displayName, 'Taylor Nurse');
    expect(gateway.added?.cellNumber, '5558675309');
    expect(gateway.added?.sectionId, 'days');
    expect(composer.openedToken, 'new-token');
    expect(find.text('Taylor Nurse'), findsOneWidget);
  });

  testWidgets('administrator can resend a fresh Invite', (tester) async {
    final gateway = _FakeStaffGateway(
      const StaffList(
        sections: [days],
        members: [
          StaffListMember(
            id: 'staff-1',
            displayName: 'Alex Tech',
            cellNumber: '5551112222',
            sectionId: 'days',
            displayOrder: 0,
          ),
        ],
      ),
    );
    final composer = _FakeInviteComposer();

    await tester.pumpWidget(
      MaterialApp(
        home: StaffListPage(
          gateway: gateway,
          rules: rules,
          inviteComposer: composer,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Resend Invite to Alex Tech'));
    await tester.pumpAndSettle();

    expect(gateway.resentStaffMemberId, 'staff-1');
    expect(composer.openedToken, 'fresh-token');
  });

  testWidgets('a person loaded from the printed page waits for a cell number', (
    tester,
  ) async {
    final gateway = _FakeStaffGateway(
      const StaffList(
        sections: [days],
        members: [
          StaffListMember(
            id: 'page-1',
            displayName: 'Page Nurse',
            cellNumber: null,
            sectionId: 'days',
            displayOrder: 0,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StaffListPage(
          gateway: gateway,
          rules: rules,
          inviteComposer: _FakeInviteComposer(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Page Nurse'), findsOneWidget);
    expect(find.text('No cell number yet'), findsOneWidget);
    expect(find.byTooltip('Resend Invite to Page Nurse'), findsNothing);
  });

  testWidgets('Manager sets a Last day from the Staff list', (tester) async {
    final gateway = _FakeStaffGateway(
      const StaffList(sections: [days], members: [alex]),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StaffListPage(
          gateway: gateway,
          rules: rules,
          inviteComposer: _FakeInviteComposer(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Change Alex Tech'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set Last day'));
    await tester.pumpAndSettle();
    expect(find.text("Set Alex Tech's Last day"), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Set Last day'));
    await tester.pumpAndSettle();

    final change = (await rules.staffChanges()).single;
    expect(change.kind, StaffChangeKind.lastDay);
    expect(change.staffMemberId, 'staff-1');
    expect(gateway.loads, 2);
  });

  testWidgets('Manager moves someone to another Section and sets a role', (
    tester,
  ) async {
    final gateway = _FakeStaffGateway(
      const StaffList(sections: [days, nights], members: [alex]),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StaffListPage(
          gateway: gateway,
          rules: rules,
          inviteComposer: _FakeInviteComposer(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Change Alex Tech'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change Section or role'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('State dayshift RN').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('PRN nightshift RN').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<JobRole>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LPN').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save change'));
    await tester.pumpAndSettle();

    final changes = await rules.staffChanges();
    expect(changes.map((change) => change.kind), [
      StaffChangeKind.section,
      StaffChangeKind.jobRole,
    ]);
    expect(changes.first.newValue, 'PRN nightshift RN');
    expect(changes.last.newValue, 'LPN');
  });

  testWidgets('Manager reactivates past staff and texts a fresh Invite', (
    tester,
  ) async {
    final lastDay = DateTime.now().subtract(const Duration(days: 30));
    await rules.setLastDay(
      SetLastDay(staffMemberId: 'staff-1', lastDay: lastDay),
    );
    final gateway = _FakeStaffGateway(
      const StaffList(sections: [days, nights], members: []),
      pastStaff: [
        PastStaffMember(
          id: 'staff-1',
          displayName: 'Alex Tech',
          lastDay: lastDay,
          sectionId: 'days',
        ),
      ],
    );
    final composer = _FakeInviteComposer();

    await tester.pumpWidget(
      MaterialApp(
        home: StaffListPage(
          gateway: gateway,
          rules: rules,
          inviteComposer: composer,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Past staff'));
    await tester.pumpAndSettle();
    expect(find.text('Alex Tech'), findsOneWidget);
    await tester.tap(find.text('Reactivate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reactivate and text Invite'));
    await tester.pumpAndSettle();

    final reactivated = (await rules.staffChanges()).last;
    expect(reactivated.kind, StaffChangeKind.reactivated);
    expect(reactivated.newValue, 'State dayshift RN');
    expect(gateway.resentStaffMemberId, 'staff-1');
    expect(composer.openedToken, 'fresh-token');
  });
}

final class _FakeStaffGateway implements StaffGateway {
  _FakeStaffGateway(this._list, {this.pastStaff = const []});

  StaffList _list;
  final List<PastStaffMember> pastStaff;
  StaffMemberDraft? added;
  String? resentStaffMemberId;
  int loads = 0;

  @override
  Future<StaffList> loadStaffList() async {
    loads++;
    return _list;
  }

  @override
  Future<List<PastStaffMember>> loadPastStaff() async => pastStaff;

  @override
  Future<StaffInvite> addStaffMember(StaffMemberDraft draft) async {
    added = draft;
    final member = StaffListMember(
      id: 'new-staff',
      displayName: draft.displayName,
      cellNumber: draft.cellNumber,
      sectionId: draft.sectionId,
      displayOrder: 0,
    );
    _list = StaffList(
      sections: _list.sections,
      members: [..._list.members, member],
    );
    return const StaffInvite(
      staffMemberId: 'new-staff',
      cellNumber: '5558675309',
      token: 'new-token',
    );
  }

  @override
  Future<void> acceptInvite(String token) async {}

  @override
  Future<bool> canManageStaff() async => true;

  @override
  Future<void> reorderSection(String sectionId, List<String> memberIds) async {}

  @override
  Future<StaffInvite> resendInvite(String staffMemberId) async {
    resentStaffMemberId = staffMemberId;
    return const StaffInvite(
      staffMemberId: 'staff-1',
      cellNumber: '5551112222',
      token: 'fresh-token',
    );
  }
}

final class _FakeInviteComposer implements InviteComposer {
  String? openedToken;

  @override
  Future<void> open(StaffInvite invite) async {
    openedToken = invite.token;
  }
}
