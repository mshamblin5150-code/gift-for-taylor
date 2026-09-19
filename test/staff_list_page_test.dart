import 'package:er_schedule/staff/staff_gateway.dart';
import 'package:er_schedule/staff/staff_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const days = StaffSection(id: 'days', name: 'State dayshift RN');

  testWidgets('Manager adds a Staff member and opens their Invite text', (
    tester,
  ) async {
    final gateway = _FakeStaffGateway(
      const StaffList(sections: [days], members: []),
    );
    final composer = _FakeInviteComposer();

    await tester.pumpWidget(
      MaterialApp(
        home: StaffListPage(gateway: gateway, inviteComposer: composer),
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
        home: StaffListPage(gateway: gateway, inviteComposer: composer),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Resend Invite to Alex Tech'));
    await tester.pumpAndSettle();

    expect(gateway.resentStaffMemberId, 'staff-1');
    expect(composer.openedToken, 'fresh-token');
  });
}

final class _FakeStaffGateway implements StaffGateway {
  _FakeStaffGateway(this._list);

  StaffList _list;
  StaffMemberDraft? added;
  String? resentStaffMemberId;

  @override
  Future<StaffList> loadStaffList() async => _list;

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
