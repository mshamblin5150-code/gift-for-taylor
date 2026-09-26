import 'support/in_memory_staff_gateway.dart';
import 'support/app_dependencies.dart';

import 'package:schedule_rules_testing/schedule_rules_testing.dart';

import 'dart:async';

import 'package:er_schedule/staff/staff_gateway.dart';
import 'package:er_schedule/staff/staff_details_page.dart';
import 'package:er_schedule/staff/staff_list_page.dart';
import 'package:er_schedule/staff/staff_contacts.dart';
import 'package:er_schedule/settings/settings_page.dart';
import 'package:er_schedule/settings/manager_handover_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'support/repair.dart';

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
      grants: {'manager': Grants(manager: true)},
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
    rules = scheduleRulesInMemory(database, actingAs: 'manager');
  });

  testWidgets('pasted overlong Staff name stays visible and cannot save', (
    tester,
  ) async {
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(sections: [days], members: []),
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
    await tester.tap(find.text('Add Staff member'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'N' * 41);
    await tester.enterText(
      find.widgetWithText(TextField, 'Cell number'),
      '5558675309',
    );
    expect(find.text('N' * 41), findsOneWidget);
    await tester.tap(find.text('Add and text Invite'));
    await tester.pump();
    expect(find.text('Use 30 characters or fewer.'), findsOneWidget);
    expect(gateway.added, isNull);
  });

  testWidgets('pasted overlong Section name stays visible and cannot save', (
    tester,
  ) async {
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(sections: [days], members: []),
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
    await tester.tap(find.byTooltip('Add Section'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Section name'),
      'S' * 33,
    );
    expect(find.text('S' * 33), findsOneWidget);
    await tester.tap(find.text('Save Section'));
    await tester.pump();
    expect(find.text('Use 32 characters or fewer.'), findsOneWidget);
    expect(find.text('Add Section'), findsOneWidget);
  });

  testWidgets('Manager sees an Invite Cell mismatch against the Staff member', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StaffListPage(
          gateway: InMemoryStaffGateway(
            actorRole: 'manager',
            list: StaffList(
              sections: const [days],
              members: [
                StaffListMember(
                  id: 'staff-1',
                  displayName: 'Alex Tech',
                  cellNumber: '+15551112222',
                  sectionId: 'days',
                  displayOrder: 0,
                  inviteCellMismatchAt: DateTime.utc(2026, 9, 20),
                ),
              ],
            ),
          ),
          rules: rules,
          inviteComposer: _FakeInviteComposer(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        "Someone opened Alex Tech's Invite and the number didn't match.",
      ),
      findsOneWidget,
    );
  });

  testWidgets('Help opens from Staff list with Manager topics', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StaffListPage(
          gateway: InMemoryStaffGateway(
            actorRole: 'manager',
            list: const StaffList(sections: [days], members: []),
          ),
          rules: rules,
          inviteComposer: _FakeInviteComposer(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Help'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'release month');
    await tester.pump();
    expect(find.text('Month release'), findsOneWidget);
  });

  testWidgets('combined grants show Night scheduler Help from Staff list', (
    tester,
  ) async {
    final gateway =
        InMemoryStaffGateway(
            actorRole: 'manager',
            list: const StaffList(sections: [days, nights], members: []),
          )
          ..actorRole = 'administrator'
          ..currentId = 'staff-1'
          ..nightSections = {'nights'};
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
    await tester.tap(find.byTooltip('Help'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'edit the schedule');
    await tester.pump();
    expect(find.text('Edit the Schedule'), findsOneWidget);
  });

  testWidgets('Manager adds a Staff member and opens their Invite text', (
    tester,
  ) async {
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(sections: [days], members: []),
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
    expect(gateway.added?.cellNumber, '+15558675309');
    expect(gateway.added?.sectionId, 'days');
    expect(composer.openedToken, 'new-token');
    expect(find.text('Taylor Nurse'), findsOneWidget);
  });

  testWidgets('matching a past Cell number offers the original Staff member', (
    tester,
  ) async {
    final lastDay = DateTime.now().subtract(const Duration(days: 30));
    await rules.store.setLastDay(
      SetLastDay(staffMemberId: 'staff-1', lastDay: lastDay),
    );
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(sections: [days], members: []),
      pastStaff: [
        PastStaffMember(
          id: 'staff-1',
          displayName: 'Jane Kemp',
          cellNumber: '+15558675309',
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

    await tester.tap(find.text('Add Staff member'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Name'),
      'Jane Smith',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Cell number'),
      '(555) 867-5309',
    );
    await tester.tap(find.text('Add and text Invite'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Jane Kemp was on the Staff list'),
      findsOneWidget,
    );
    expect(gateway.added, isNull);
    await tester.tap(find.text('Bring them back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reactivate and text Invite'));
    await tester.pumpAndSettle();

    database.seedStaffChanges([
      StaffChange(
        staffMemberId: 'staff-1',
        kind: StaffChangeKind.reactivated,
        oldValue: null,
        newValue: 'State dayshift RN',
        effectiveFrom: DateTime(2026, 9, 21),
        changedBy: 'manager',
        changedAt: DateTime(2026, 9, 21),
      ),
    ]);
    expect(gateway.added, isNull);
    expect(
      (await rules.store.staffChanges()).last.kind,
      StaffChangeKind.reactivated,
    );
    expect(gateway.resentStaffMemberId, 'staff-1');
    expect(composer.openedToken, 'fresh-token');
  });

  testWidgets('declining a past match permits a recycled Cell number', (
    tester,
  ) async {
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(sections: [days], members: []),
      pastStaff: [
        PastStaffMember(
          id: 'former',
          displayName: 'Jane Kemp',
          cellNumber: '+15558675309',
          lastDay: DateTime(2026, 3, 1),
          sectionId: 'days',
        ),
      ],
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
    await tester.tap(find.text('Add Staff member'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Name'),
      'Different Person',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Cell number'),
      '5558675309',
    );
    await tester.tap(find.text('Add and text Invite'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add different person'));
    await tester.pumpAndSettle();

    expect(gateway.added?.displayName, 'Different Person');
    expect(gateway.allowedRecycledCell, isTrue);
  });

  testWidgets('a recycled Cell number offers every matching past person', (
    tester,
  ) async {
    final lastDay = DateTime.now().subtract(const Duration(days: 30));
    await rules.store.setLastDay(
      SetLastDay(staffMemberId: 'staff-1', lastDay: lastDay),
    );
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(sections: [days], members: []),
      pastStaff: [
        PastStaffMember(
          id: 'former',
          displayName: 'First Person',
          cellNumber: '+15558675309',
          lastDay: DateTime(2026, 3, 1),
          sectionId: 'days',
        ),
        PastStaffMember(
          id: 'staff-1',
          displayName: 'Second Person',
          cellNumber: '+15558675309',
          lastDay: lastDay,
          sectionId: 'days',
        ),
      ],
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
    await tester.tap(find.text('Add Staff member'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Name'),
      'Second Person',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Cell number'),
      '5558675309',
    );
    await tester.tap(find.text('Add and text Invite'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('First Person was on the Staff list'),
      findsOneWidget,
    );
    await tester.tap(find.text('Not this person'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Second Person was on the Staff list'),
      findsOneWidget,
    );
    await tester.tap(find.text('Bring them back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reactivate and text Invite'));
    await tester.pumpAndSettle();

    expect(gateway.added, isNull);
    expect(gateway.resentStaffMemberId, 'staff-1');
  });

  testWidgets('administrator can resend a fresh Invite', (tester) async {
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(
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
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(
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
    expect(find.text('Add a cell number to finish setup'), findsOneWidget);
    expect(
      find.byTooltip('Add a cell number before sending an Invite'),
      findsOneWidget,
    );
    final invite = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.sms_outlined),
        matching: find.byType(IconButton),
      ),
    );
    expect(invite.onPressed, isNull);

    await tester.tap(find.text('Page Nurse'));
    await tester.pumpAndSettle();
    expect(find.text('Add a cell number to finish setup'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(
      find.text('Add a cell number before sending an Invite'),
      findsOneWidget,
    );
    expect(find.text('Edit name and cell number'), findsOneWidget);
  });

  testWidgets(
    'a cleared cell number reads as unfinished after Invite acceptance',
    (tester) async {
      final gateway = InMemoryStaffGateway(
        actorRole: 'manager',
        list: const StaffList(
          sections: [days],
          members: [
            StaffListMember(
              id: 'staff-1',
              displayName: 'Alex Tech',
              cellNumber: null,
              sectionId: 'days',
              displayOrder: 0,
              personalEmail: 'alex@example.test',
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

      expect(find.text('Add a cell number to finish setup'), findsOneWidget);
      expect(find.text('alex@example.test'), findsNothing);
    },
  );

  testWidgets('Manager sets a Last day from the Staff list', (tester) async {
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(sections: [days], members: [alex]),
    );
    database.seedStaffChanges([
      StaffChange(
        staffMemberId: 'staff-1',
        kind: StaffChangeKind.lastDay,
        oldValue: null,
        newValue: '2026-09-21',
        effectiveFrom: DateTime(2026, 9, 21),
        changedBy: 'manager',
        changedAt: DateTime(2026, 9, 21),
      ),
    ]);

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

    final change = (await rules.store.staffChanges()).single;
    expect(change.kind, StaffChangeKind.lastDay);
    expect(change.staffMemberId, 'staff-1');
    expect(database.lastDayWrites.single.staffMemberId, 'staff-1');
    expect(gateway.loads, 2);
  });

  testWidgets('Manager moves someone to another Section and sets a role', (
    tester,
  ) async {
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(sections: [days, nights], members: [alex]),
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
    await tester.tap(find.text('Change Section or Job role'));
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

    database.seedStaffChanges([
      StaffChange(
        staffMemberId: 'staff-1',
        kind: StaffChangeKind.section,
        oldValue: 'State dayshift RN',
        newValue: 'PRN nightshift RN',
        effectiveFrom: DateTime(2026, 9, 21),
        changedBy: 'manager',
        changedAt: DateTime(2026, 9, 21),
      ),
      StaffChange(
        staffMemberId: 'staff-1',
        kind: StaffChangeKind.jobRole,
        oldValue: null,
        newValue: 'LPN',
        effectiveFrom: DateTime(2026, 9, 21),
        changedBy: 'manager',
        changedAt: DateTime(2026, 9, 21),
      ),
    ]);
    final changes = await rules.store.staffChanges();
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
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(sections: [days], members: [alex]),
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
    expect(find.text('Change Section or Job role'), findsOneWidget);
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
    expect(gateway.list.members.single.cellNumber, '+15553334444');
  });

  testWidgets(
    'Manager grants and revokes administrator access in Staff details',
    (tester) async {
      final gateway = InMemoryStaffGateway(
        actorRole: 'manager',
        list: const StaffList(sections: [days], members: [alex]),
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
      await tester.drag(find.byType(ListView).last, const Offset(0, -450));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Change access'));
      await tester.tap(find.text('Change access'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Administrator').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save access'));
      await tester.pumpAndSettle();
      expect(gateway.accessRole, 'administrator');
      await tester.ensureVisible(find.text('Change access'));
      await tester.tap(find.text('Change access'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Administrator').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save access'));
      await tester.pumpAndSettle();
      expect(gateway.accessRole, 'staff_member');
    },
  );

  testWidgets('Administrator confirms an Invite from Staff list', (
    tester,
  ) async {
    final gateway =
        InMemoryStaffGateway(
            actorRole: 'manager',
            list: const StaffList(sections: [days], members: [alex]),
          )
          ..actorRole = 'administrator'
          ..invites = [
            PendingInviteAcceptance(
              inviteId: 'invite-1',
              staffMemberName: 'Alex Tech',
              personalEmail: 'alex@example.test',
              acceptedAt: DateTime(2026, 9, 20),
            ),
          ];
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
    expect(find.text('Invite acceptances'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(gateway.confirmedInviteId, 'invite-1');
    expect(find.text('Invite acceptances'), findsNothing);
  });

  testWidgets(
    'Staff details keeps Night scheduler Sections when Administrator changes',
    (tester) async {
      final gateway = InMemoryStaffGateway(
        actorRole: 'manager',
        list: const StaffList(sections: [days, nights], members: [alex]),
      )..nightSections = {'nights'};
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
      await tester.drag(find.byType(ListView).last, const Offset(0, -450));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Change access'));
      await tester.tap(find.text('Change access'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Administrator').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save access'));
      await tester.pumpAndSettle();
      expect(gateway.accessRole, 'administrator');
      expect(gateway.nightSections, {'nights'});
      await tester.ensureVisible(find.text('Change access'));
      await tester.tap(find.text('Change access'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Administrator').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save access'));
      await tester.pumpAndSettle();
      expect(gateway.accessRole, 'night_scheduler');
      expect(gateway.nightSections, {'nights'});
    },
  );

  testWidgets('Manager transfers role to a signed-in Staff member', (
    tester,
  ) async {
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(
        sections: [days],
        members: [
          StaffListMember(
            id: 'staff-1',
            displayName: 'Alex Tech',
            cellNumber: '5551112222',
            sectionId: 'days',
            displayOrder: 0,
            personalEmail: 'alex@example.test',
          ),
        ],
      ),
      handoverCandidates: const [
        ManagerHandoverCandidate(id: 'staff-1', displayName: 'Alex Tech'),
      ],
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
    await tester.drag(find.byType(ListView).last, const Offset(0, -450));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Change access'));
    await tester.tap(find.text('Change access'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transfer Manager').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Staff member by default'), findsOneWidget);
    await tester.tap(find.text('Transfer Manager').last);
    await tester.pumpAndSettle();
    expect(gateway.accessRole, 'manager');
    expect(gateway.actorRole, 'staff_member');
    expect(find.text('Change access'), findsNothing);
  });

  testWidgets('Staff details shows an actionable handover refusal', (
    tester,
  ) async {
    final gateway =
        InMemoryStaffGateway(
            actorRole: 'manager',
            list: const StaffList(sections: [days], members: [alex]),
            handoverCandidates: const [
              ManagerHandoverCandidate(id: 'staff-1', displayName: 'Alex Tech'),
            ],
          )
          ..transferError = const ManagerHandoverRefused(
            ManagerHandoverRefusal.successorInvitePending,
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
    await tester.drag(find.byType(ListView).last, const Offset(0, -450));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Change access'));
    await tester.tap(find.text('Change access'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transfer Manager').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transfer Manager').last);
    await tester.pumpAndSettle();

    expect(
      find.text(
        "Confirm this Staff member's accepted Invite before transferring "
        'Manager.',
      ),
      findsOneWidget,
    );
    expect(find.text('Could not change the access role.'), findsNothing);
  });

  testWidgets('Maintainer can transfer Manager from Staff details', (
    tester,
  ) async {
    final gateway =
        InMemoryStaffGateway(
            actorRole: 'manager',
            list: const StaffList(sections: [days], members: [alex]),
          )
          ..actorRole = 'maintainer'
          ..handoverCandidates = const [
            ManagerHandoverCandidate(id: 'staff-1', displayName: 'Alex Tech'),
          ]
          ..activeRepair = MaintainerRepair(
            id: 'repair',
            category: RepairReasonCategory.managerHandover,
            openedAt: DateTime.utc(2026, 9, 24, 12),
            expiresAt: DateTime.utc(2026, 9, 24, 13),
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
    await tester.drag(find.byType(ListView).last, const Offset(0, -450));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Change access'));
    await tester.tap(find.text('Change access'));
    await tester.pumpAndSettle();
    expect(find.text('Transfer Manager'), findsOneWidget);
  });

  testWidgets('handover waits for the Staff member to accept the Invite', (
    tester,
  ) async {
    final gateway =
        InMemoryStaffGateway(
            actorRole: 'manager',
            list: const StaffList(
              sections: [days],
              members: [
                StaffListMember(
                  id: 'staff-1',
                  displayName: 'Alex Tech',
                  cellNumber: '5551112222',
                  sectionId: 'days',
                  displayOrder: 0,
                  personalEmail: 'alex@example.test',
                ),
              ],
            ),
          )
          ..handoverCandidates = const [
            ManagerHandoverCandidate(
              id: 'staff-1',
              displayName: 'Alex Tech',
              blocker: ManagerHandoverBlocker.noStaffAccount,
            ),
          ];
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
    await tester.drag(find.byType(ListView).last, const Offset(0, -450));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change access'));
    await tester.pumpAndSettle();
    expect(find.text('Transfer Manager'), findsNothing);
    expect(
      find.text(
        'Alex Tech has not completed an Invite. Resend the Invite and ask '
        'them to accept it before transferring Manager.',
      ),
      findsOneWidget,
    );
    expect(find.text('Resend Invite'), findsOneWidget);
  });

  testWidgets('Manager assigns Night scheduler Sections from Staff details', (
    tester,
  ) async {
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(sections: [days, nights], members: [alex]),
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
    await tester.drag(find.byType(ListView).last, const Offset(0, -450));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Change access'));
    await tester.tap(find.text('Change access'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('PRN nightshift RN').last);
    await tester.tap(find.text('PRN nightshift RN').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save access'));
    await tester.pumpAndSettle();
    expect(gateway.accessRole, 'night_scheduler');
    expect(gateway.nightSections, {'nights'});
    await tester.scrollUntilVisible(
      find.text('Access history'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Access history'), findsOneWidget);
  });

  testWidgets('Manager revokes access from Past staff details', (tester) async {
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(sections: [days], members: []),
      pastStaff: [
        PastStaffMember(
          id: 'staff-1',
          displayName: 'Alex Tech',
          lastDay: DateTime(2026, 9, 1),
          sectionId: 'days',
        ),
      ],
    )..accessRole = 'administrator';
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
    await tester.tap(find.byTooltip('Past staff'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alex Tech'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -450));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Change access'));
    await tester.tap(find.text('Change access'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Administrator').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save access'));
    await tester.pumpAndSettle();
    expect(gateway.accessRole, 'staff_member');
  });

  testWidgets(
    'a phone contact fills add fields and saves a normalized number',
    (tester) async {
      final gateway = InMemoryStaffGateway(
        actorRole: 'manager',
        list: const StaffList(sections: [days], members: []),
      );
      final contacts = _FakePhoneContacts(canPick: true);
      await tester.pumpWidget(
        MaterialApp(
          home: StaffListPage(
            gateway: gateway,
            rules: rules,
            inviteComposer: _FakeInviteComposer(),
            phoneContacts: contacts,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Staff member'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose from contacts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add and text Invite'));
      await tester.pumpAndSettle();
      expect(gateway.added?.displayName, 'Taylor Nurse');
      expect(gateway.added?.cellNumber, '+15558675309');
    },
  );

  testWidgets('without a picker, editing uses manual entry and saves vCard', (
    tester,
  ) async {
    final contacts = _FakePhoneContacts(canPick: false);
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(sections: [days], members: [alex]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: StaffListPage(
          gateway: gateway,
          rules: rules,
          inviteComposer: _FakeInviteComposer(),
          phoneContacts: contacts,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alex Tech'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -450));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to contacts'));
    expect(contacts.saved, ('Alex Tech', '5551112222'));
    await tester.tap(find.text('Edit name and cell number'));
    await tester.pumpAndSettle();
    expect(find.text('Choose from contacts'), findsNothing);
    expect(
      find.text('Enter a name and cell number from your contacts below.'),
      findsOneWidget,
    );
  });

  testWidgets('a phone contact replaces name and number when editing', (
    tester,
  ) async {
    final contacts = _FakePhoneContacts(canPick: true);
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(sections: [days], members: [alex]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: StaffListPage(
          gateway: gateway,
          rules: rules,
          inviteComposer: _FakeInviteComposer(),
          phoneContacts: contacts,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alex Tech'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -450));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit name and cell number'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from contacts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(gateway.list.members.single.displayName, 'Taylor Nurse');
    expect(gateway.list.members.single.cellNumber, '+15558675309');
  });

  testWidgets('Manager chooses a number when the phone contact has several', (
    tester,
  ) async {
    final contacts = _FakePhoneContacts(canPick: true)
      ..numbers = ['5551112222', '(555) 867-5309'];
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(sections: [days], members: []),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: StaffListPage(
          gateway: gateway,
          rules: rules,
          inviteComposer: _FakeInviteComposer(),
          phoneContacts: contacts,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Staff member'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from contacts'));
    await tester.pumpAndSettle();
    expect(find.text('Which cell number?'), findsOneWidget);
    await tester.tap(find.text('(555) 867-5309'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add and text Invite'));
    await tester.pumpAndSettle();
    expect(gateway.added?.cellNumber, '+15558675309');
  });

  testWidgets('Manager reactivates past staff and texts a fresh Invite', (
    tester,
  ) async {
    final lastDay = DateTime.now().subtract(const Duration(days: 30));
    await rules.store.setLastDay(
      SetLastDay(staffMemberId: 'staff-1', lastDay: lastDay),
    );
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(sections: [days, nights], members: []),
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

    database.seedStaffChanges([
      StaffChange(
        staffMemberId: 'staff-1',
        kind: StaffChangeKind.reactivated,
        oldValue: null,
        newValue: 'State dayshift RN',
        effectiveFrom: DateTime(2026, 9, 21),
        changedBy: 'manager',
        changedAt: DateTime(2026, 9, 21),
      ),
    ]);
    final reactivated = (await rules.store.staffChanges()).last;
    expect(reactivated.kind, StaffChangeKind.reactivated);
    expect(reactivated.newValue, 'State dayshift RN');
    expect(gateway.resentStaffMemberId, 'staff-1');
    expect(composer.openedToken, 'fresh-token');
  });

  testWidgets('Manager moves whole Sections, adds and renames one', (
    tester,
  ) async {
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(sections: [days, nights], members: []),
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
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(sections: [days], members: [alex]),
    )..actorRole = 'staff_member';
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
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(sections: [days], members: [alex]),
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
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(sections: [days, nights], members: []),
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

  testWidgets('Manager transfers from Personal settings with Staff default', (
    tester,
  ) async {
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(sections: [days], members: [alex]),
      handoverCandidates: const [
        ManagerHandoverCandidate(id: 'staff-1', displayName: 'Alex Tech'),
      ],
    )..currentId = 'current-manager';
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          maintainerRepairController: noopRepairController(),
          undeliveredInvitationLog: FakeUndeliveredInvitationLog(),
          scheduleRules: rules,
          noticeGateway: const NoopNoticeGateway(),
          access: Access(
            grants: Grants(manager: true),
            ownStaffMemberId: 'current-manager',
          ),
          staffGateway: gateway,
        ),
      ),
    );
    await tester.tap(find.text('Transfer Manager'));
    await tester.pumpAndSettle();
    expect(find.text('Alex Tech'), findsOneWidget);
    expect(find.textContaining('Maintainer hat'), findsOneWidget);
    await tester.tap(find.text('Alex Tech'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Transfer Manager'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Transfer Manager'),
      ),
    );
    await tester.pumpAndSettle();
    expect(gateway.actorRole, 'staff_member');
    expect(gateway.accessRole, 'manager');
  });

  testWidgets('Manager handover shows the typed refusal instead of Try again', (
    tester,
  ) async {
    final gateway =
        InMemoryStaffGateway(
            actorRole: 'manager',
            list: const StaffList(sections: [days], members: [alex]),
            handoverCandidates: const [
              ManagerHandoverCandidate(id: 'staff-1', displayName: 'Alex Tech'),
            ],
          )
          ..transferError = const ManagerHandoverRefused(
            ManagerHandoverRefusal.retainedSectionMissing,
          );
    await tester.pumpWidget(
      MaterialApp(home: ManagerHandoverPage(gateway: gateway)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alex Tech'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Transfer Manager'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Transfer Manager'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Review your Night scheduler Sections because one selected for your '
        'access after handover no longer exists.',
      ),
      findsOneWidget,
    );
    expect(find.text('Could not transfer Manager. Try again.'), findsNothing);
  });

  testWidgets(
    'Personal settings names an accepted Invite awaiting confirmation',
    (tester) async {
      var staffListOpenCount = 0;
      final gateway =
          InMemoryStaffGateway(
              actorRole: 'manager',
              list: const StaffList(sections: [days], members: []),
            )
            ..currentId = 'current-manager'
            ..handoverCandidates = const [
              ManagerHandoverCandidate(
                id: 'taylor',
                displayName: 'Taylor',
                blocker: ManagerHandoverBlocker.inviteAcceptancePending,
              ),
            ];
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsPage(
            maintainerRepairController: noopRepairController(),
            undeliveredInvitationLog: FakeUndeliveredInvitationLog(),
            scheduleRules: rules,
            noticeGateway: const NoopNoticeGateway(),
            access: Access(
              grants: Grants(manager: true),
              ownStaffMemberId: 'current-manager',
            ),
            staffGateway: gateway,
            onManageStaff: () async => staffListOpenCount++,
          ),
        ),
      );

      await tester.tap(find.text('Transfer Manager'));
      await tester.pumpAndSettle();

      expect(find.text('Taylor'), findsOneWidget);
      expect(
        find.text(
          'Taylor accepted the Invite. Confirm it before transferring Manager.',
        ),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Transfer Manager'),
        findsNothing,
      );
      await tester.tap(find.text('Open Staff list'));
      await tester.pumpAndSettle();
      expect(staffListOpenCount, 1);
    },
  );

  testWidgets('handover opens details to assign a missing Section', (
    tester,
  ) async {
    String? openedStaffMemberId;
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(sections: [days], members: []),
      handoverCandidates: const [
        ManagerHandoverCandidate(
          id: 'uri',
          displayName: 'Uri',
          blocker: ManagerHandoverBlocker.noCurrentSection,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          maintainerRepairController: noopRepairController(),
          undeliveredInvitationLog: FakeUndeliveredInvitationLog(),
          scheduleRules: rules,
          noticeGateway: const NoopNoticeGateway(),
          access: Access(grants: Grants(manager: true)),
          staffGateway: gateway,
          onOpenStaffDetails: (id) async => openedStaffMemberId = id,
        ),
      ),
    );

    await tester.tap(find.text('Transfer Manager'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Uri has no current Section. Assign a Section before transferring '
        'Manager.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Assign Section'));
    await tester.pumpAndSettle();
    expect(openedStaffMemberId, 'uri');
  });

  testWidgets(
    'handover can restore the same Section after an assignment ended',
    (tester) async {
      final gateway = InMemoryStaffGateway(
        actorRole: 'manager',
        list: const StaffList(sections: [days], members: [alex]),
        handoverCandidates: const [
          ManagerHandoverCandidate(
            id: 'staff-1',
            displayName: 'Alex Tech',
            blocker: ManagerHandoverBlocker.noCurrentSection,
          ),
        ],
      )..grantsByStaff['staff-1'] = Grants();
      await tester.pumpWidget(
        MaterialApp(
          home: StaffDetailsPage(
            staffMemberId: 'staff-1',
            gateway: gateway,
            rules: rules,
            inviteComposer: _FakeInviteComposer(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -450));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Change access'));
      await tester.tap(find.text('Change access'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Assign Section'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .initialValue,
        isNull,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('State dayshift RN').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save change'));
      await tester.pumpAndSettle();
      expect(find.text('Change Alex Tech'), findsNothing);
    },
  );

  testWidgets('Maintainer can open handover without Staff access choices', (
    tester,
  ) async {
    final gateway =
        InMemoryStaffGateway(
            actorRole: 'manager',
            list: const StaffList(sections: [days], members: [alex]),
          )
          ..actorRole = 'maintainer'
          ..handoverCandidates = const [
            ManagerHandoverCandidate(id: 'staff-1', displayName: 'Alex Tech'),
          ]
          ..activeRepair = MaintainerRepair(
            id: 'repair',
            category: RepairReasonCategory.managerHandover,
            openedAt: DateTime.utc(2026, 9, 24, 12),
            expiresAt: DateTime.utc(2026, 9, 24, 13),
          );
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          maintainerRepairController: noopRepairController(),
          undeliveredInvitationLog: FakeUndeliveredInvitationLog(),
          scheduleRules: rules,
          noticeGateway: const NoopNoticeGateway(),
          access: Access(
            grants: Grants(),
            maintainer: true,
            ownStaffMemberId: 'maintainer',
            activeRepair: gateway.activeRepair,
          ),
          staffGateway: gateway,
        ),
      ),
    );
    await tester.tap(find.text('Transfer Manager'));
    await tester.pumpAndSettle();
    expect(find.text('Alex Tech'), findsOneWidget);
    expect(find.text('Your Staff access after handover'), findsNothing);
    expect(find.text('Administrator'), findsNothing);
  });
}

final class _FakeInviteComposer implements InviteComposer {
  String? openedToken;

  @override
  Future<void> open(StaffInvite invite) async {
    openedToken = invite.token;
  }
}

final class _FakePhoneContacts implements PhoneContacts {
  _FakePhoneContacts({required this.canPick});

  @override
  final bool canPick;
  (String, String)? saved;
  List<String> numbers = ['(555) 867-5309'];

  @override
  Future<PickedContact?> pick() async =>
      PickedContact(name: 'Taylor Nurse', numbers: numbers);

  @override
  void save(String name, String cellNumber) => saved = (name, cellNumber);
}
