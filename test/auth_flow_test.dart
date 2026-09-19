import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:er_schedule/app.dart';
import 'package:er_schedule/auth/auth_gateway.dart';
import 'package:er_schedule/auth/sign_in_page.dart';
import 'package:er_schedule/schedule/section_gateway.dart';
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
        sectionGateway: const _FakeSectionGateway([
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

  testWidgets('account without an accepted Invite sees no Schedule data', (
    tester,
  ) async {
    await tester.pumpWidget(
      ScheduleApp(
        authGateway: _FakeAuthGateway(true),
        sectionGateway: const _FakeSectionGateway([]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining("isn't on the ER staff list"), findsOneWidget);
    expect(find.text('State dayshift RN'), findsNothing);
  });

  testWidgets('invitee signs in before the Invite is accepted', (
    tester,
  ) async {
    final staffGateway = _FakeStaffGateway();
    await tester.pumpWidget(
      ScheduleApp(
        authGateway: _FakeAuthGateway(),
        sectionGateway: const _FakeSectionGateway([
          ScheduleSection(id: 'days', name: 'State dayshift RN'),
        ]),
        staffGateway: staffGateway,
        inviteToken: 'fresh-token',
      ),
    );
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
    expect(find.text('State dayshift RN'), findsOneWidget);
  });

  testWidgets('Invite signs out an existing account before asking for email', (
    tester,
  ) async {
    final authGateway = _FakeAuthGateway(true);
    final staffGateway = _FakeStaffGateway();

    await tester.pumpWidget(
      ScheduleApp(
        authGateway: authGateway,
        sectionGateway: const _FakeSectionGateway([]),
        staffGateway: staffGateway,
        inviteToken: 'fresh-token',
      ),
    );
    await tester.pumpAndSettle();

    expect(authGateway.signOutCount, 1);
    expect(find.text('Email me a code'), findsOneWidget);
    expect(staffGateway.acceptedToken, isNull);
  });
}

final class _FakeSectionGateway implements SectionGateway {
  const _FakeSectionGateway(this.sections);

  final List<ScheduleSection> sections;

  @override
  Future<List<ScheduleSection>> loadSections() async => sections;
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
  String? acceptedToken;

  @override
  Future<void> acceptInvite(String token) async {
    acceptedToken = token;
  }

  @override
  Future<StaffInvite> addStaffMember(StaffMemberDraft draft) {
    throw UnimplementedError();
  }

  @override
  Future<bool> canManageStaff() async => false;

  @override
  Future<StaffList> loadStaffList() {
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
