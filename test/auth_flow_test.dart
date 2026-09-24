import 'support/app_dependencies.dart';
import 'support/repair.dart';
import 'support/in_memory_staff_gateway.dart';

import 'package:schedule_rules_testing/schedule_rules_testing.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:er_schedule/app.dart';
import 'package:er_schedule/auth/sign_in_page.dart';
import 'package:er_schedule/notifications/notice_gateway.dart';
import 'package:er_schedule/staff/staff_gateway.dart';
import 'package:er_schedule/schedule_theme.dart';
import 'package:er_schedule/settings/appearance.dart';
import 'package:er_schedule/settings/settings_page.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appearanceMode.value = ThemeMode.system;
  });

  testWidgets('saved appearance themes the first signed-out frame', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'appearance_mode': 'dark'});
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await loadAppearance();

    await tester.pumpWidget(
      ScheduleApp(
        dependencies: appDependencies(
          authGateway: FakeAuthGateway(),
          scheduleStore: _scheduleStore(const []),
        ),
      ),
    );
    expect(
      Theme.of(tester.element(find.byType(CircularProgressIndicator)))
          .brightness,
      Brightness.dark,
    );
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('ER Schedule'))).brightness,
      Brightness.dark,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      ScheduleApp(
        dependencies: appDependencies(
          authGateway: FakeAuthGateway(),
          scheduleStore: _scheduleStore(const []),
          staffGateway: InMemoryStaffGateway(),
        ),
        inviteToken: 'fresh-token',
      ),
    );
    expect(
      Theme.of(tester.element(find.byType(CircularProgressIndicator)))
          .brightness,
      Brightness.dark,
    );
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('Cell number'))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('Appearance is a Personal setting', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          maintainerRepairController: noopRepairController(),
          scheduleRules: ScheduleRules(_scheduleStore(const [])),
          noticeGateway: const NoopNoticeGateway(),
          access: Access(grants: Grants()),
        ),
      ),
    );
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(find.text('Light'), findsOneWidget);
  });

  testWidgets('System, Light, and Dark restore from device storage', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final gateway = FakeAuthGateway();
    final store = _scheduleStore(const []);

    for (final (label, expected) in [
      ('Light', Brightness.light),
      ('Dark', Brightness.dark),
      ('System', Brightness.dark),
    ]) {
      await tester.pumpWidget(
        ScheduleApp(
          dependencies: appDependencies(
            authGateway: gateway,
            scheduleStore: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('ER Schedule'))).brightness,
        expected,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      appearanceMode.value = ThemeMode.system;
      await loadAppearance();
      await tester.pumpWidget(
        ScheduleApp(
          dependencies: appDependencies(
            authGateway: gateway,
            scheduleStore: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('ER Schedule'))).brightness,
        expected,
      );
    }
  });

  testWidgets('appearance choice stays in one browser storage', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final gateway = FakeAuthGateway();
    final store = _scheduleStore(const []);
    await tester.pumpWidget(
      ScheduleApp(
        dependencies: appDependencies(
          authGateway: gateway,
          scheduleStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('ER Schedule'))).brightness,
      Brightness.dark,
    );

    // A separate browser has its own empty local preference store.
    await tester.pumpWidget(const SizedBox.shrink());
    SharedPreferences.setMockInitialValues({});
    await loadAppearance();
    await tester.pumpWidget(
      ScheduleApp(
        dependencies: appDependencies(
          authGateway: gateway,
          scheduleStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('ER Schedule'))).brightness,
      Brightness.light,
    );
  });
  testWidgets('system appearance updates sign-in and Invite before auth', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final gateway = FakeAuthGateway();
    await tester.pumpWidget(
      ScheduleApp(
        dependencies: appDependencies(
          authGateway: gateway,
          scheduleStore: _scheduleStore(const []),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Email me a code'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('ER Schedule'))).colorScheme.surface,
      ScheduleTheme.light.colorScheme.surface,
    );

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('ER Schedule'))).colorScheme.surface,
      ScheduleTheme.dark.colorScheme.surface,
    );

    await tester.pumpWidget(
      ScheduleApp(
        dependencies: appDependencies(
          authGateway: gateway,
          scheduleStore: _scheduleStore(const []),
          staffGateway: InMemoryStaffGateway(),
        ),
        inviteToken: 'fresh-token',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cell number'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('Cell number'))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('Manager requests and verifies an emailed one-time code', (
    tester,
  ) async {
    final gateway = FakeAuthGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: SignInPage(
          authGateway: gateway,
          noticeGateway: const NoopNoticeGateway(),
        ),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'manager@example.test',
    );
    await tester.tap(find.text('Email me a code'));
    await tester.pump();

    expect(gateway.requestedEmail, 'manager@example.test');
    expect(find.text('One-time code'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'One-time code'),
      '123456',
    );
    await tester.tap(find.text('Verify code'));
    await tester.pump();

    expect(gateway.verifiedEmail, 'manager@example.test');
    expect(gateway.verifiedCode, '123456');
  });

  testWidgets('signed-in Manager can sign out', (tester) async {
    final gateway = FakeAuthGateway(true);
    await tester.pumpWidget(
      ScheduleApp(
        dependencies: appDependencies(
          authGateway: gateway,
          scheduleStore: _scheduleStore(const [
            ScheduleSection(id: 'days', name: 'State dayshift RN'),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More destinations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pump();

    expect(gateway.signOutCount, 1);
    expect(find.text('Email me a code'), findsOneWidget);
  });

  testWidgets('Access controls the Staff list with every gateway wired', (
    tester,
  ) async {
    final store = _scheduleStore(const [
      ScheduleSection(id: 'days', name: 'State dayshift RN'),
    ]);
    final staffGateway = InMemoryStaffGateway();
    await tester.pumpWidget(
      ScheduleApp(
        dependencies: appDependencies(
          authGateway: FakeAuthGateway(true),
          scheduleStore: store,
          staffGateway: staffGateway,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More destinations'));
    await tester.pumpAndSettle();
    expect(find.text('Manage Staff list'), findsNothing);

    staffGateway.actorRole = 'manager';
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      ScheduleApp(
        dependencies: appDependencies(
          authGateway: FakeAuthGateway(true),
          scheduleStore: store,
          staffGateway: staffGateway,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More destinations'));
    await tester.pumpAndSettle();
    expect(find.text('Manage Staff list'), findsOneWidget);
  });

  testWidgets('signed-in Staff member opens their own month first', (
    tester,
  ) async {
    final now = DateTime.now();
    final database = InMemoryScheduleDatabase(
      sections: const [ScheduleSection(id: 'days', name: 'State dayshift RN')],
      rows: const [
        ScheduleRow(
          staffMemberId: 'staff-1',
          displayName: 'Day RN',
          sectionId: 'days',
        ),
      ],
      releasedMonths: {DateTime(now.year, now.month)},
      grants: {'manager': Grants(manager: true)},
    );
    await tester.pumpWidget(
      ScheduleApp(
        dependencies: appDependencies(
          authGateway: FakeAuthGateway(true),
          scheduleStore: database.storeFor('staff-1'),
          staffGateway: InMemoryStaffGateway(currentId: 'staff-1'),
          noticeGateway: const NoopNoticeGateway(PushState.enabled),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Day RN'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsOneWidget);
  });

  testWidgets(
    'confirmed Staff member is offered notification setup once per place',
    (tester) async {
      final dependencies = appDependencies(
        authGateway: FakeAuthGateway(true),
        scheduleStore: _confirmedStaffSchedule(),
        staffGateway: InMemoryStaffGateway(currentId: 'staff-1'),
        noticeGateway: const NoopNoticeGateway(),
      );

      await tester.pumpWidget(ScheduleApp(dependencies: dependencies));
      await tester.pumpAndSettle();

      expect(find.text('Hear about Schedule changes'), findsOneWidget);
      expect(find.text('Day RN'), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Day RN'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Hear about Schedule changes'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(ScheduleApp(dependencies: dependencies));
      await tester.pumpAndSettle();
      expect(find.text('Hear about Schedule changes'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(ScheduleApp(dependencies: dependencies));
      await tester.pumpAndSettle();
      expect(find.text('Hear about Schedule changes'), findsOneWidget);
    },
  );

  testWidgets('push-enabled confirmed Staff member opens Schedule directly', (
    tester,
  ) async {
    await tester.pumpWidget(
      ScheduleApp(
        dependencies: appDependencies(
          authGateway: FakeAuthGateway(true),
          scheduleStore: _confirmedStaffSchedule(),
          staffGateway: InMemoryStaffGateway(currentId: 'staff-1'),
          noticeGateway: const NoopNoticeGateway(PushState.enabled),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Day RN'), findsOneWidget);
    expect(find.text('Hear about Schedule changes'), findsNothing);
  });

  testWidgets('account without an accepted Invite sees no Schedule data', (
    tester,
  ) async {
    await tester.pumpWidget(
      ScheduleApp(
        dependencies: appDependencies(
          authGateway: FakeAuthGateway(true),
          scheduleStore: _scheduleStore(const []),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining("isn't on the ER staff list"), findsOneWidget);
    expect(find.text('State dayshift RN'), findsNothing);
  });

  testWidgets(
    'invitee gives their Cell number and waits for Manager confirmation',
    (tester) async {
      final staffGateway = InMemoryStaffGateway();
      await tester.pumpWidget(
        ScheduleApp(
          dependencies: appDependencies(
            authGateway: FakeAuthGateway(),
            scheduleStore: _scheduleStore(const []),
            staffGateway: staffGateway,
          ),
          inviteToken: 'fresh-token',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Email me a code'), findsNothing);
      expect(find.text('Add ER Schedule'), findsOneWidget);
      await tester.tap(find.text('Add ER Schedule'));
      await tester.pumpAndSettle();
      expect(find.text('Copy app link'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Cell number'),
        '555-0137',
      );
      await tester.tap(find.text('Continue to email'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'invitee@example.test',
      );
      await tester.tap(find.text('Email me a code'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'One-time code'),
        '123456',
      );
      await tester.tap(find.text('Verify code'));
      await tester.pumpAndSettle();

      expect(staffGateway.acceptedToken, 'fresh-token');
      expect(staffGateway.acceptedCellNumber, '555-0137');
      expect(find.textContaining('waiting for the Manager'), findsOneWidget);
      expect(find.text('Add ER Schedule'), findsOneWidget);
      await tester.tap(find.text('Add ER Schedule'));
      await tester.pumpAndSettle();
      expect(find.text('Copy app link'), findsOneWidget);
    },
  );

  testWidgets('Invite signs out an existing account before asking for email', (
    tester,
  ) async {
    final authGateway = FakeAuthGateway(true);
    final staffGateway = InMemoryStaffGateway();

    await tester.pumpWidget(
      ScheduleApp(
        dependencies: appDependencies(
          authGateway: authGateway,
          scheduleStore: _scheduleStore(const []),
          staffGateway: staffGateway,
        ),
        inviteToken: 'fresh-token',
      ),
    );
    await tester.pumpAndSettle();

    expect(authGateway.signOutCount, 1);
    expect(find.text('Cell number'), findsOneWidget);
    expect(staffGateway.acceptedToken, isNull);
  });

  testWidgets('wrong Cell number shows a specific error and can be retried', (
    tester,
  ) async {
    final staffGateway = InMemoryStaffGateway()
      ..acceptanceResult = InviteAcceptanceResult.cellMismatch;
    await tester.pumpWidget(
      ScheduleApp(
        dependencies: appDependencies(
          authGateway: FakeAuthGateway(),
          scheduleStore: _scheduleStore(const []),
          staffGateway: staffGateway,
        ),
        inviteToken: 'fresh-token',
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Cell number'),
      '555-0000',
    );
    await tester.tap(find.text('Continue to email'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'invitee@example.test',
    );
    await tester.tap(find.text('Email me a code'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'One-time code'),
      '123456',
    );
    await tester.tap(find.text('Verify code'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining("doesn't match the one on file"),
      findsOneWidget,
    );
    staffGateway.acceptanceResult = InviteAcceptanceResult.accepted;
    await tester.enterText(
      find.widgetWithText(TextField, 'Cell number'),
      '555-0137',
    );
    await tester.tap(find.text('Try Cell number again'));
    await tester.pumpAndSettle();
    expect(staffGateway.acceptedCellNumber, '555-0137');
  });

  testWidgets('duplicate sign-in explains why the Invite cannot be accepted', (
    tester,
  ) async {
    final staffGateway = InMemoryStaffGateway()
      ..acceptanceError = const StaffInviteAlreadyLinkedException();
    await tester.pumpWidget(
      ScheduleApp(
        dependencies: appDependencies(
          authGateway: FakeAuthGateway(),
          scheduleStore: _scheduleStore(const []),
          staffGateway: staffGateway,
        ),
        inviteToken: 'fresh-token',
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Cell number'),
      '555-0137',
    );
    await tester.tap(find.text('Continue to email'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'invitee@example.test',
    );
    await tester.tap(find.text('Email me a code'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'One-time code'),
      '123456',
    );
    await tester.tap(find.text('Verify code'));
    await tester.pumpAndSettle();

    expect(
      find.text('This email is already signed in as another Staff member.'),
      findsOneWidget,
    );
    expect(find.textContaining('23505'), findsNothing);
  });

  testWidgets('Invite refusals explain what unblocks acceptance', (
    tester,
  ) async {
    const cases = {
      InviteAcceptanceRefusal.staffAcceptancePending:
          'Wait for the Manager or an Administrator to confirm your Invite '
          'acceptance before signing in.',
      InviteAcceptanceRefusal.staffAlreadyAccepted:
          'This Invite was already accepted, so sign in with the email that '
          'accepted it or ask your Manager to resend it.',
      InviteAcceptanceRefusal.emailAcceptancePending:
          'Ask the Manager or an Administrator to confirm the Invite this '
          'email already accepted.',
      InviteAcceptanceRefusal.accountMissingEmail:
          'Sign out and use an account with an email address before accepting '
          'this Invite.',
    };

    for (final MapEntry(key: reason, value: wording) in cases.entries) {
      final staffGateway = InMemoryStaffGateway()
        ..acceptanceError = InviteAcceptanceRefused(reason);
      await tester.pumpWidget(
        ScheduleApp(
          key: ValueKey(reason),
          dependencies: appDependencies(
            authGateway: FakeAuthGateway(),
            scheduleStore: _scheduleStore(const []),
            staffGateway: staffGateway,
          ),
          inviteToken: 'fresh-token',
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Cell number'),
        '555-0137',
      );
      await tester.tap(find.text('Continue to email'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'invitee@example.test',
      );
      await tester.tap(find.text('Email me a code'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'One-time code'),
        '123456',
      );
      await tester.tap(find.text('Verify code'));
      await tester.pumpAndSettle();

      expect(find.text(wording), findsOneWidget);
      expect(
        find.text('Could not check this Invite. Try again.'),
        findsNothing,
      );
    }
  });

  testWidgets(
    'returning to the foreground rebuilds the Schedule when Access changes',
    (tester) async {
      final staffGateway = InMemoryStaffGateway(currentId: 'staff-1');
      final database = InMemoryScheduleDatabase(
        sections: const [ScheduleSection(id: 'days', name: 'Days')],
        rows: const [
          ScheduleRow(
            staffMemberId: 'staff-1',
            displayName: 'Staff',
            sectionId: 'days',
          ),
        ],
        grants: {'manager': Grants(manager: true)},
      );
      await tester.pumpWidget(
        ScheduleApp(
          dependencies: appDependencies(
            authGateway: FakeAuthGateway(true),
            scheduleStore: database.storeFor('manager'),
            staffGateway: staffGateway,
            noticeGateway: const NoopNoticeGateway(PushState.enabled),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining("hasn't been released"), findsOneWidget);

      staffGateway.actorRole = 'manager';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Start empty month'), findsOneWidget);
    },
  );
}

ScheduleStore _scheduleStore(List<ScheduleSection> sections) {
  return InMemoryScheduleDatabase(
    grants: {'manager': Grants(manager: true)},
    sections: sections,
  ).storeFor('manager');
}

ScheduleStore _confirmedStaffSchedule() {
  final now = DateTime.now();
  return InMemoryScheduleDatabase(
    sections: const [ScheduleSection(id: 'days', name: 'State dayshift RN')],
    rows: const [
      ScheduleRow(
        staffMemberId: 'staff-1',
        displayName: 'Day RN',
        sectionId: 'days',
      ),
    ],
    releasedMonths: {DateTime(now.year, now.month)},
    grants: {'manager': Grants(manager: true)},
  ).storeFor('staff-1');
}
