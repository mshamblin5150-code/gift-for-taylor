import 'package:er_schedule/staff/staff_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'in_memory_staff_gateway.dart';

void main() {
  test(
    'rejection removes only the selected pending Invite acceptance',
    () async {
      final gateway = InMemoryStaffGateway()
        ..invites = [
          PendingInviteAcceptance(
            inviteId: 'first',
            staffMemberName: 'Alex',
            personalEmail: 'alex@example.test',
            acceptedAt: DateTime(2026, 9, 18),
          ),
          PendingInviteAcceptance(
            inviteId: 'second',
            staffMemberName: 'Taylor',
            personalEmail: 'taylor@example.test',
            acceptedAt: DateTime(2026, 9, 19),
          ),
        ];

      await gateway.rejectInviteAcceptance('first');

      expect(gateway.rejectedInviteId, 'first');
      expect(
        (await gateway.pendingInviteAcceptances()).map(
          (invite) => invite.inviteId,
        ),
        ['second'],
      );
    },
  );

  test('pending acceptance follows a successful accepted Invite', () async {
    final gateway = InMemoryStaffGateway()
      ..acceptanceError = const StaffInviteAlreadyLinkedException();

    await expectLater(
      gateway.acceptInvite('token', '555-0100'),
      throwsA(isA<StaffInviteAlreadyLinkedException>()),
    );
    expect(await gateway.isInviteAcceptancePending(), isFalse);
    expect(
      await gateway.acceptInvite('token', '555-0100'),
      InviteAcceptanceResult.accepted,
    );
    expect(await gateway.isInviteAcceptancePending(), isTrue);
  });

  test(
    'Access grants are recorded independently for each Staff member',
    () async {
      final gateway = InMemoryStaffGateway();
      final alexGrants = Grants(
        manager: true,
        nightSchedulerSectionIds: {'nights'},
      );
      final taylorGrants = Grants(administrator: true);

      await gateway.setAccessGrants('alex', alexGrants);
      await gateway.setAccessGrants('taylor', taylorGrants);

      expect(await gateway.loadAccessGrants('alex'), alexGrants);
      expect(await gateway.loadAccessGrants('taylor'), taylorGrants);
    },
  );
}
