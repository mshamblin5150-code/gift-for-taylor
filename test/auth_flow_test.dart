import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:er_schedule/app.dart';
import 'package:er_schedule/auth/auth_gateway.dart';
import 'package:er_schedule/auth/sign_in_page.dart';
import 'package:er_schedule/schedule/section_gateway.dart';
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

    expect(find.textContaining('not on the ER Staff list'), findsOneWidget);
    expect(find.text('State dayshift RN'), findsNothing);
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
  }

  @override
  Future<void> signOut() async {
    signOutCount += 1;
    _signedIn = false;
    _controller.add(false);
  }
}
