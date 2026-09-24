import 'package:er_schedule/staff/staff_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('Manager handover SQLSTATEs map to typed refusal reasons', () async {
    const cases = {
      'P2797': ManagerHandoverRefusal.managerAccessChanged,
      'P2798': ManagerHandoverRefusal.noActiveManager,
      'P2799': ManagerHandoverRefusal.sameStaffMember,
      'P2800': ManagerHandoverRefusal.retainedSectionMissing,
      'P2801': ManagerHandoverRefusal.successorNoAccount,
      'P2802': ManagerHandoverRefusal.successorInvitePending,
      'P2803': ManagerHandoverRefusal.successorAccountRevoked,
      'P2804': ManagerHandoverRefusal.successorInactive,
      'P2805': ManagerHandoverRefusal.successorAlreadyManager,
      'P2806': ManagerHandoverRefusal.successorNoCurrentSection,
    };

    for (final MapEntry(key: code, value: reason) in cases.entries) {
      final error = PostgrestException(message: 'refused', code: code);
      await expectLater(
        mapManagerHandoverRefusal<void>(() => Future.error(error)),
        throwsA(
          isA<ManagerHandoverRefused>().having(
            (exception) => exception.reason,
            'reason',
            reason,
          ),
        ),
      );
    }
  });

  test('Manager handover keeps generic database failures', () async {
    final error = PostgrestException(message: 'failure', code: '23505');

    await expectLater(
      mapManagerHandoverRefusal<void>(() => Future.error(error)),
      throwsA(same(error)),
    );
  });

  test('Invite acceptance SQLSTATEs map to typed refusal reasons', () async {
    const cases = {
      'P2807': InviteAcceptanceRefusal.staffAcceptancePending,
      'P2808': InviteAcceptanceRefusal.staffAlreadyAccepted,
      'P2809': InviteAcceptanceRefusal.emailAcceptancePending,
      'P2810': InviteAcceptanceRefusal.accountMissingEmail,
    };

    for (final MapEntry(key: code, value: reason) in cases.entries) {
      final error = PostgrestException(message: 'refused', code: code);
      await expectLater(
        mapInviteAcceptanceRefusal<void>(() => Future.error(error)),
        throwsA(
          isA<InviteAcceptanceRefused>().having(
            (exception) => exception.reason,
            'reason',
            reason,
          ),
        ),
      );
    }
  });

  test('Invite acceptance keeps generic database failures', () async {
    final error = PostgrestException(message: 'failure', code: '23505');

    await expectLater(
      mapInviteAcceptanceRefusal<void>(() => Future.error(error)),
      throwsA(same(error)),
    );
  });
}
