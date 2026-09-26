import 'package:schedule_rules_testing/schedule_rules_testing.dart';
import 'package:er_schedule/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:er_schedule/auth/sign_in_failure_log.dart';
import 'package:er_schedule/calendar/undelivered_invitation_log.dart';

import 'support/app_dependencies.dart';
import 'support/repair.dart';

void main() {
  testWidgets('Maintainer sees marked controls without ambient authority', (
    tester,
  ) async {
    final rules = scheduleRulesInMemory(
      InMemoryScheduleDatabase(
        grants: {'manager': Grants(manager: true)},
        sections: const [],
      ),
      actingAs: 'manager',
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
          ),
          signInFailureLog: FakeSignInFailureLog(),
          onCalendarFeed: () {},
          onManageStaff: () async {},
        ),
      ),
    );
    expect(find.text('Maintainer repairs'), findsOneWidget);
    expect(find.text('Unit'), findsNothing);
    expect(find.text('Manager controls'), findsOneWidget);
    expect(find.text('Sections'), findsOneWidget);
    expect(
      find.text('Requires a Repair — tap to break the glass'),
      findsWidgets,
    );
    expect(find.text('My calendar'), findsOneWidget);
    expect(find.text('Sign-in failures'), findsNothing);
  });

  testWidgets('Maintainer can read a recorded sign-in provider failure', (
    tester,
  ) async {
    final failureLog = FakeSignInFailureLog()
      ..failures = [
        SignInFailureRecord(
          happenedAt: DateTime(2026, 9, 24, 14, 30),
          code: 'unexpected_failure',
          statusCode: '500',
          message: 'mail quota reached',
        ),
      ];
    final rules = scheduleRulesInMemory(
      InMemoryScheduleDatabase(
        grants: {'manager': Grants(manager: true)},
        sections: const [],
      ),
      actingAs: 'manager',
    );
    final openedAt = DateTime(2026, 9, 24, 14);
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
            activeRepair: MaintainerRepair(
              id: 'repair-338',
              category: RepairReasonCategory.investigation,
              detail: 'Review sign-in delivery failures',
              openedAt: openedAt,
              expiresAt: openedAt.add(const Duration(hours: 1)),
            ),
          ),
          signInFailureLog: failureLog,
        ),
      ),
    );

    expect(find.text('Sign-in failures'), findsOneWidget);

    await tester.tap(find.text('Sign-in failures'));
    await tester.pumpAndSettle();
    expect(find.text('unexpected_failure'), findsOneWidget);
    expect(find.textContaining('mail quota reached'), findsOneWidget);
  });

  testWidgets('only a repairing Maintainer sees Undelivered invitations', (
    tester,
  ) async {
    final log = FakeUndeliveredInvitationLog()
      ..invitations = [
        UndeliveredInvitation(
          staffDisplayName: 'Taylor Nurse',
          workDate: DateTime(2027, 1, 4),
          recipient: 'taylor@example.test',
          method: 'REQUEST',
          shiftCode: '7A',
          deliveryAttempts: 3,
          failedAt: DateTime(2026, 9, 24, 14, 30),
          errorCode: 'EENVELOPE',
          statusCode: '550',
          errorMessage: 'Daily email quota exhausted',
        ),
      ];
    final rules = scheduleRulesInMemory(
      InMemoryScheduleDatabase(
        grants: {'manager': Grants(manager: true)},
        sections: const [],
      ),
      actingAs: 'manager',
    );
    final openedAt = DateTime(2026, 9, 24, 14);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          maintainerRepairController: noopRepairController(),
          scheduleRules: rules,
          noticeGateway: const NoopNoticeGateway(),
          access: Access(
            grants: Grants(),
            maintainer: true,
            activeRepair: MaintainerRepair(
              id: 'repair-337',
              category: RepairReasonCategory.investigation,
              detail: 'Review Undelivered invitations',
              openedAt: openedAt,
              expiresAt: openedAt.add(const Duration(hours: 1)),
            ),
          ),
          undeliveredInvitationLog: log,
        ),
      ),
    );

    expect(find.text('Undelivered invitations'), findsOneWidget);
    await tester.tap(find.text('Undelivered invitations'));
    await tester.pumpAndSettle();
    expect(find.text('Taylor Nurse · Jan 4, 2027 · 7A'), findsOneWidget);
    expect(find.textContaining('3 attempts'), findsOneWidget);
    expect(find.textContaining('Daily email quota exhausted'), findsOneWidget);
  });
}
