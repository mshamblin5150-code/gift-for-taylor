import 'dart:async';

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

  testWidgets('Manager opens Staff details and edits contact information', (
    tester,
  ) async {
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

    await tester.tap(find.text('Alex Tech'));
    await tester.pumpAndSettle();
    expect(find.text('5551112222'), findsOneWidget);
    expect(find.text('Not signed up yet'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(find.text('Change Section or role'), findsOneWidget);
    expect(find.text('Set Last day'), findsOneWidget);
    expect(find.text('Resend Invite'), findsOneWidget);

    await tester.tap(find.text('Edit name and cell number'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Name'),
      'Alex Nurse',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Cell number'),
      '5553334444',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Alex Nurse'), findsWidgets);
    expect(gateway._list.members.single.cellNumber, '5553334444');
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

  testWidgets('Manager moves whole Sections, adds and renames one', (
    tester,
  ) async {
    final gateway = _FakeStaffGateway(
      const StaffList(sections: [days, nights], members: []),
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

    await tester.tap(find.byTooltip('Move PRN nightshift RN up'));
    await tester.pumpAndSettle();
    expect(gateway.orderedSections, ['nights', 'days']);

    await tester.tap(find.byTooltip('Add Section'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Section name'),
      'CNA',
    );
    await tester.tap(find.text('Save Section'));
    await tester.pumpAndSettle();
    expect(find.text('CNA'), findsOneWidget);

    await tester.tap(find.byTooltip('Rename CNA'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Section name'),
      'Unit clerks',
    );
    await tester.tap(find.text('Save Section'));
    await tester.pumpAndSettle();
    expect(find.text('Unit clerks'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete Unit clerks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Section'));
    await tester.pumpAndSettle();
    expect(gateway.deletedSection, 'new-section');
  });

  testWidgets('Section controls are hidden from a non-Manager', (tester) async {
    final gateway = _FakeStaffGateway(
      const StaffList(sections: [days], members: [alex]),
    )..manager = false;
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
    expect(find.byTooltip('Add Section'), findsNothing);
    expect(find.byTooltip('Rename State dayshift RN'), findsNothing);
    expect(find.byTooltip('Delete State dayshift RN'), findsNothing);
  });

  testWidgets('a Section with Staff members has no delete action', (
    tester,
  ) async {
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
    final button = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.tooltip == 'Delete State dayshift RN',
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('Section arrows wait for the previous reorder to save', (
    tester,
  ) async {
    final gateway = _FakeStaffGateway(
      const StaffList(sections: [days, nights], members: []),
    )..orderGate = Completer<void>();
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

    await tester.tap(find.byTooltip('Move PRN nightshift RN up'));
    await tester.pump();
    final moveDown = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.tooltip == 'Move PRN nightshift RN down',
      ),
    );
    expect(moveDown.onPressed, isNull);
    gateway.orderGate!.complete();
    await tester.pumpAndSettle();
    expect(gateway.orderedSections, ['nights', 'days']);
  });
}

final class _FakeStaffGateway implements StaffGateway {
  @override
  Future<StaffMemberDetails> loadStaffMemberDetails(String id) async {
    final member = _list.members.singleWhere((member) => member.id == id);
    return StaffMemberDetails(
      id: id,
      displayName: member.displayName,
      cellNumber: member.cellNumber,
      sectionId: member.sectionId,
      personalEmail: member.personalEmail,
      jobRole: member.jobRole,
      role: 'staff_member',
    );
  }

  @override
  Future<void> updateStaffContact(String id, String name, String? cell) async {
    _list = StaffList(
      sections: _list.sections,
      members: [
        for (final member in _list.members)
          if (member.id == id)
            StaffListMember(
              id: id,
              displayName: name,
              cellNumber: cell,
              sectionId: member.sectionId,
              displayOrder: member.displayOrder,
              personalEmail: member.personalEmail,
              jobRole: member.jobRole,
            )
          else
            member,
      ],
    );
  }

  @override
  Future<String?> currentStaffMemberId() async => null;
  _FakeStaffGateway(this._list, {this.pastStaff = const []});

  StaffList _list;
  final List<PastStaffMember> pastStaff;
  StaffMemberDraft? added;
  String? resentStaffMemberId;
  int loads = 0;
  bool manager = true;
  List<String>? orderedSections;
  Completer<void>? orderGate;
  String? deletedSection;

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
  Future<bool> canManageSections() async => manager;

  @override
  Future<void> addSection(String name) async {
    _list = _list.withSections([
      ..._list.sections,
      StaffSection(id: 'new-section', name: name),
    ]);
  }

  @override
  Future<void> renameSection(String sectionId, String name) async {
    _list = _list.withSections([
      for (final section in _list.sections)
        section.id == sectionId
            ? StaffSection(id: sectionId, name: name)
            : section,
    ]);
  }

  @override
  Future<void> deleteEmptySection(String sectionId) async {
    deletedSection = sectionId;
    _list = _list.withSections([
      for (final section in _list.sections)
        if (section.id != sectionId) section,
    ]);
  }

  @override
  Future<void> reorderSections(List<String> sectionIds) async {
    await orderGate?.future;
    orderedSections = sectionIds;
    _list = _list.withSections([
      for (final id in sectionIds)
        _list.sections.singleWhere((section) => section.id == id),
    ]);
  }

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
