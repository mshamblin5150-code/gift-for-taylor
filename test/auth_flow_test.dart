import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:er_schedule/app.dart';
import 'package:er_schedule/auth/auth_gateway.dart';
import 'package:er_schedule/auth/sign_in_page.dart';
import 'package:er_schedule/staff/staff_gateway.dart';
import 'package:schedule_rules/schedule_rules.dart';

void main() {
  testWidgets('Manager requests and verifies an emailed one-time code', (
    tester,
  ) async {
    final gateway = _FakeAuthGateway();
    await tester.pumpWidget(
      MaterialApp(home: SignInPage(authGateway: gateway)),
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
    final gateway = _FakeAuthGateway(true);
    await tester.pumpWidget(
      ScheduleApp(
        authGateway: gateway,
        scheduleStore: _scheduleStore(const [
          ScheduleSection(id: 'days', name: 'State dayshift RN'),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Sign out'), findsOneWidget);
    await tester.tap(find.byTooltip('Sign out'));
    await tester.pump();

    expect(gateway.signOutCount, 1);
    expect(find.text('Email me a code'), findsOneWidget);
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
      editors: const {'manager'},
    );
    await tester.pumpWidget(
      ScheduleApp(
        authGateway: _FakeAuthGateway(true),
        scheduleStore: database.storeFor('staff-1'),
        staffGateway: _FakeStaffGateway('staff-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Day RN'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsOneWidget);
  });

  testWidgets('account without an accepted Invite sees no Schedule data', (
    tester,
  ) async {
    await tester.pumpWidget(
      ScheduleApp(
        authGateway: _FakeAuthGateway(true),
        scheduleStore: _scheduleStore(const []),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining("isn't on the ER staff list"), findsOneWidget);
    expect(find.text('State dayshift RN'), findsNothing);
  });

  testWidgets(
    'invitee gives their Cell number and waits for Manager confirmation',
    (tester) async {
      final staffGateway = _FakeStaffGateway();
      await tester.pumpWidget(
        ScheduleApp(
          authGateway: _FakeAuthGateway(),
          scheduleStore: _scheduleStore(const []),
          staffGateway: staffGateway,
          inviteToken: 'fresh-token',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Email me a code'), findsNothing);
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
    },
  );

  testWidgets('Invite signs out an existing account before asking for email', (
    tester,
  ) async {
    final authGateway = _FakeAuthGateway(true);
    final staffGateway = _FakeStaffGateway();

    await tester.pumpWidget(
      ScheduleApp(
        authGateway: authGateway,
        scheduleStore: _scheduleStore(const []),
        staffGateway: staffGateway,
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
    final staffGateway = _FakeStaffGateway()
      ..acceptanceResult = InviteAcceptanceResult.cellMismatch;
    await tester.pumpWidget(
      ScheduleApp(
        authGateway: _FakeAuthGateway(),
        scheduleStore: _scheduleStore(const []),
        staffGateway: staffGateway,
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
    final staffGateway = _FakeStaffGateway()
      ..acceptanceError = const StaffInviteAlreadyLinkedException();
    await tester.pumpWidget(
      ScheduleApp(
        authGateway: _FakeAuthGateway(),
        scheduleStore: _scheduleStore(const []),
        staffGateway: staffGateway,
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
}

ScheduleStore _scheduleStore(List<ScheduleSection> sections) {
  return InMemoryScheduleDatabase(sections: sections).storeFor('manager');
}

final class _FakeAuthGateway implements AuthGateway {
  _FakeAuthGateway([this._signedIn = false]);

  final _controller = StreamController<bool>.broadcast();
  bool _signedIn;
  String? requestedEmail;
  String? verifiedEmail;
  String? verifiedCode;
  int signOutCount = 0;

  @override
  bool get isSignedIn => _signedIn;

  @override
  Stream<bool> get signedInChanges => _controller.stream;

  @override
  Future<void> requestCode(String email) async {
    requestedEmail = email;
  }

  @override
  Future<void> verifyCode({required String email, required String code}) async {
    verifiedEmail = email;
    verifiedCode = code;
    _signedIn = true;
    _controller.add(true);
  }

  @override
  Future<void> signOut() async {
    signOutCount += 1;
    _signedIn = false;
    _controller.add(false);
  }
}

final class _FakeStaffGateway implements StaffGateway {
  Object? acceptanceError;
  @override
  Future<bool> canTransferManagerTo(String id) async => false;
  @override
  Future<List<StaffAccessChange>> loadStaffAccessChanges(String id) async => [];
  @override
  Future<String?> currentStaffRole() async => 'staff_member';

  @override
  Future<void> assignAdministrator(String id) async {}

  @override
  Future<void> removeAdministrator(String id) async {}

  @override
  Future<void> transferManager(String id) async {}
  _FakeStaffGateway([this.staffMemberId]);

  final String? staffMemberId;
  @override
  Future<StaffMemberDetails> loadStaffMemberDetails(String id) =>
      throw UnimplementedError();

  @override
  Future<void> updateStaffContact(String id, String name, String? cell) =>
      throw UnimplementedError();
  String? acceptedToken;
  String? acceptedCellNumber;
  InviteAcceptanceResult acceptanceResult = InviteAcceptanceResult.accepted;

  @override
  Future<InviteAcceptanceResult> acceptInvite(
    String token,
    String cellNumber,
  ) async {
    if (acceptanceError case final error?) throw error;
    acceptedToken = token;
    acceptedCellNumber = cellNumber;
    return acceptanceResult;
  }

  @override
  Future<bool> isInviteAcceptancePending() async => acceptedToken != null;

  @override
  Future<List<PendingInviteAcceptance>> pendingInviteAcceptances() async => [];

  @override
  Future<void> confirmInviteAcceptance(String inviteId) async {}

  @override
  Future<void> rejectInviteAcceptance(String inviteId) async {}

  @override
  Future<StaffInvite> addStaffMember(
    StaffMemberDraft draft, {
    bool allowRecycledCell = false,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<bool> canManageStaff() async => false;

  @override
  Future<bool> canManageSections() async => false;

  @override
  Future<void> addSection(String name) => throw UnimplementedError();

  @override
  Future<void> renameSection(String sectionId, String name) =>
      throw UnimplementedError();

  @override
  Future<void> deleteEmptySection(String sectionId) =>
      throw UnimplementedError();

  @override
  Future<void> reorderSections(List<String> sectionIds) =>
      throw UnimplementedError();

  @override
  Future<String?> currentStaffMemberId() async => staffMemberId;

  @override
  Future<StaffList> loadStaffList() {
    throw UnimplementedError();
  }

  @override
  Future<List<PastStaffMember>> loadPastStaff() {
    throw UnimplementedError();
  }

  @override
  Future<void> reorderSection(String sectionId, List<String> memberIds) {
    throw UnimplementedError();
  }

  @override
  Future<StaffInvite> resendInvite(String staffMemberId) {
    throw UnimplementedError();
  }
}
