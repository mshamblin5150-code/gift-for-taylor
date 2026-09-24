import 'package:er_schedule/help/help_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

void main() {
  test('every manager action visible to Night schedulers is labeled', () {
    final managerOnly = helpTopics.where(
      (topic) =>
          topic.roles.contains(HelpRole.nightScheduler) &&
          !topic.roles.contains(HelpRole.staffMember) &&
          topic.roles.contains(HelpRole.manager) &&
          topic.who.startsWith('Manager only') &&
          topic.title != 'Edit the Schedule' &&
          topic.title != 'Unannounced changes' &&
          topic.who.contains('Manager only'),
    );
    expect(managerOnly, isNotEmpty);
    for (final topic in managerOnly) {
      if (topic.title == 'Staffing minimums' ||
          topic.title == 'Coverage pools') {
        expect(
          topic.who,
          contains('Manager and Administrator'),
          reason: topic.title,
        );
      } else {
        expect(topic.who, contains('Manager only'), reason: topic.title);
        expect(topic.how, contains('Manager only:'), reason: topic.title);
      }
    }
  });

  test('independent Access grants select every Help catalog held', () {
    expect(
      helpRolesFor(
        Access(
          grants: Grants(),
          maintainer: true,
          ownStaffMemberId: 'maintainer',
        ),
      ),
      {HelpRole.maintainer, HelpRole.staffMember},
    );
    expect(
      helpRolesFor(
        Access(
          grants: Grants(
            administrator: true,
            nightSchedulerSectionIds: {'nights'},
          ),
          ownStaffMemberId: 'alex',
        ),
      ),
      {HelpRole.administrator, HelpRole.nightScheduler},
    );
    expect(helpRolesFor(Access(grants: Grants(), ownStaffMemberId: 'alex')), {
      HelpRole.staffMember,
    });
    expect(helpRolesFor(Access(grants: Grants(manager: true))), {
      HelpRole.manager,
    });
  });

  testWidgets('Night scheduler finds how to check a Manager override', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: HelpPage(roles: {HelpRole.nightScheduler})),
    );
    await tester.enterText(find.byType(TextField), 'manager overrode');
    await tester.pump();
    expect(find.text('Change log'), findsOneWidget);
    await tester.tap(find.text('Change log'));
    await tester.pumpAndSettle();
    expect(find.textContaining('old and new codes'), findsOneWidget);
  });

  testWidgets('Maintainer finds Manager guidance and repair instructions', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: HelpPage(roles: {HelpRole.maintainer})),
    );
    await tester.enterText(find.byType(TextField), 'release month');
    await tester.pump();
    expect(find.text('Month release'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'repair reason');
    await tester.pump();
    expect(find.text('Maintainer repairs'), findsOneWidget);
  });

  testWidgets('Administrator finds who changed Unit settings', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HelpPage(roles: {HelpRole.administrator})),
    );
    await tester.enterText(find.byType(TextField), 'who changed settings');
    await tester.pump();
    expect(find.text('Settings history'), findsOneWidget);
    await tester.tap(find.text('Settings history'));
    await tester.pumpAndSettle();
    expect(find.textContaining('before and after values'), findsWidgets);
  });

  Future<void> openHelp(WidgetTester tester, HelpRole role) async {
    await tester.pumpWidget(MaterialApp(home: HelpPage(roles: {role})));
  }

  testWidgets('a Staff member finds capabilities in everyday language', (
    tester,
  ) async {
    await openHelp(tester, HelpRole.staffMember);
    for (final (query, title) in [
      ('day off', 'Request off'),
      ('swap', 'Swap'),
      ('who is working', 'Day view'),
      ('calendar email', 'Calendar invitations'),
      ('subscribe calendar', 'Calendar feed'),
      ('install app', 'Install on a phone'),
      ('home screen', 'Install on a phone'),
      ('computer', 'Install on a computer'),
      ('desktop', 'Install on a computer'),
      ('notifications', 'Allow notifications'),
    ]) {
      await tester.enterText(find.byType(TextField), query);
      await tester.pump();
      expect(find.text(title), findsOneWidget);
    }
  });

  testWidgets('Staff members do not see Manager-only Help', (tester) async {
    await openHelp(tester, HelpRole.staffMember);
    await tester.enterText(find.byType(TextField), 'release month');
    await tester.pump();
    expect(find.text('Month release'), findsNothing);
  });

  testWidgets('Staff members can find printing but not print wording', (
    tester,
  ) async {
    await openHelp(tester, HelpRole.staffMember);
    await tester.enterText(find.byType(TextField), 'print');
    await tester.pump();
    expect(find.text('Print Schedule book page'), findsOneWidget);
    expect(find.text('Change print wording'), findsNothing);
  });

  testWidgets('Manager sees all topics and their instructions', (tester) async {
    await openHelp(tester, HelpRole.manager);
    await tester.enterText(find.byType(TextField), 'release month');
    await tester.pump();
    await tester.tap(find.text('Month release'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Manager'), findsWidgets);
  });

  testWidgets('Manager can find the combined Approval queue', (tester) async {
    await openHelp(tester, HelpRole.manager);
    await tester.enterText(find.byType(TextField), 'approval queue');
    await tester.pump();
    expect(find.text('Approval queue'), findsOneWidget);
    await tester.tap(find.text('Approval queue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('accepted Invites'), findsOneWidget);
  });

  testWidgets('Manager finds the Invite Cell mismatch instructions', (
    tester,
  ) async {
    await openHelp(tester, HelpRole.manager);
    await tester.enterText(find.byType(TextField), 'wrong cell number');
    await tester.pump();
    expect(find.text('Invite Cell mismatch'), findsOneWidget);
    await tester.tap(find.text('Invite Cell mismatch'));
    await tester.pumpAndSettle();
    expect(find.textContaining('retry the same Invite'), findsOneWidget);
  });

  testWidgets('Night scheduler can read clearly labeled Manager guidance', (
    tester,
  ) async {
    await openHelp(tester, HelpRole.nightScheduler);
    await tester.enterText(find.byType(TextField), 'shift code');
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Edit the Schedule'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Edit the Schedule'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'manage shift codes');
    await tester.pump();
    expect(find.text('Manage Shift codes'), findsOneWidget);
    await tester.tap(find.text('Manage Shift codes'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Manager only:'), findsWidgets);
  });

  testWidgets(
    'Administrator finds their Staff guidance and Manager boundaries',
    (tester) async {
      await openHelp(tester, HelpRole.administrator);
      await tester.enterText(find.byType(TextField), 'admin permissions');
      await tester.pump();
      expect(find.text('Administrator access'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'staff list');
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Staff list'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Staff list'), findsOneWidget);
      await tester.tap(find.text('Staff list'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Manager or Administrator:'), findsWidgets);
    },
  );

  testWidgets('combined grants include Night scheduler tasks in Help', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HelpPage(
          roles: {HelpRole.administrator, HelpRole.nightScheduler},
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'edit the schedule');
    await tester.pump();
    expect(find.text('Edit the Schedule'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'administrator access');
    await tester.pump();
    expect(find.text('Administrator access'), findsOneWidget);
  });

  testWidgets('Staff cannot find Manager guidance through search', (
    tester,
  ) async {
    await openHelp(tester, HelpRole.staffMember);
    await tester.enterText(find.byType(TextField), 'minimum RN floor');
    await tester.pump();
    expect(find.text('Staffing minimums'), findsNothing);
    await tester.enterText(find.byType(TextField), 'invite confirmation');
    await tester.pump();
    expect(find.text('Invite'), findsNothing);
  });

  testWidgets('Manager can find pool guidance by everyday search', (
    tester,
  ) async {
    await openHelp(tester, HelpRole.manager);
    await tester.enterText(find.byType(TextField), 'short staffing');
    await tester.pump();
    expect(find.text('Staffing minimums'), findsOneWidget);
    await tester.tap(find.text('Staffing minimums'));
    await tester.pumpAndSettle();
    expect(find.textContaining('never for a Section'), findsOneWidget);
  });
}
