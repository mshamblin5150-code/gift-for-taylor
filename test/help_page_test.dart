import 'package:er_schedule/help/help_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every manager action visible to Night schedulers is labeled', () {
    final managerOnly = helpTopics.where(
      (topic) =>
          topic.roles.contains(HelpRole.nightScheduler) &&
          !topic.roles.contains(HelpRole.staffMember) &&
          topic.roles.contains(HelpRole.manager) &&
          topic.title != 'Edit the Schedule' &&
          topic.title != 'Unannounced changes',
    );
    expect(managerOnly, isNotEmpty);
    for (final topic in managerOnly) {
      expect(topic.who, contains('Manager only'), reason: topic.title);
      expect(topic.how, contains('Manager only:'), reason: topic.title);
    }
  });

  Future<void> openHelp(WidgetTester tester, HelpRole role) async {
    await tester.pumpWidget(MaterialApp(home: HelpPage(role: role)));
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
    expect(find.text('Edit the Schedule'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'manage shift codes');
    await tester.pump();
    expect(find.text('Manage Shift codes'), findsOneWidget);
    await tester.tap(find.text('Manage Shift codes'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Manager only:'), findsWidgets);
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
