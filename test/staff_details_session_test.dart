import 'package:er_schedule/settings/manager_handover_session.dart';
import 'package:er_schedule/staff/staff_details_session.dart';
import 'package:er_schedule/staff/staff_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:schedule_rules_testing/schedule_rules_testing.dart';

import 'support/in_memory_staff_gateway.dart';

void main() {
  late InMemoryScheduleDatabase database;
  late ScheduleRules rules;

  setUp(() {
    database = InMemoryScheduleDatabase(
      grants: {'manager': Grants(manager: true)},
      sections: const [ScheduleSection(id: 'days', name: 'Days')],
      rows: const [],
    );
    rules = scheduleRulesInMemory(database, actingAs: 'manager');
  });

  test('Staff details session records a restored Section assignment', () async {
    final session = StaffDetailsSession(
      'staff-1',
      InMemoryStaffGateway(
        actorRole: 'manager',
        list: const StaffList(
          sections: [StaffSection(id: 'days', name: 'Days')],
          members: [
            StaffListMember(
              id: 'staff-1',
              displayName: 'Alex',
              cellNumber: null,
              sectionId: 'days',
              displayOrder: 0,
            ),
          ],
        ),
      ),
      rules,
    );

    final outcome = await session.changeSectionOrRole(
      from: DateTime(2026, 9, 24),
      sectionId: 'days',
    );

    expect(outcome, isA<StaffCommandSaved>());
    expect(database.sectionWrites.single.sectionId, 'days');
    session.dispose();
  });

  test('Staff details session reports rejected writes', () async {
    var rejected = 0;
    final gateway = InMemoryStaffGateway(actorRole: 'manager')
      ..updateContactError = const AccessRejected();
    final session = StaffDetailsSession(
      'staff-1',
      gateway,
      rules,
      () => rejected++,
    );

    final outcome = await session.updateContact('Alex', null);

    expect(outcome, isA<StaffCommandFailed>());
    expect(rejected, 1);
    session.dispose();
  });

  test('Staff details session reports a rejected Invite resend', () async {
    var rejected = 0;
    final gateway = InMemoryStaffGateway(actorRole: 'manager')
      ..resendInviteError = const AccessRejected();
    final session = StaffDetailsSession(
      'staff-1',
      gateway,
      rules,
      () => rejected++,
    );

    final outcome = await session.resendInvite();

    expect(outcome, isA<StaffInviteFailed>());
    expect(rejected, 1);
    session.dispose();
  });

  test('Manager handover session reports rejected transfers', () async {
    var rejected = 0;
    final gateway = InMemoryStaffGateway(actorRole: 'manager')
      ..transferError = const AccessRejected();
    final session = ManagerHandoverSession(gateway, () => rejected++);

    final outcome = await session.transfer(
      successorId: 'staff-1',
      formerAdministrator: false,
      formerSections: const {},
    );

    expect(outcome, isA<ManagerTransferFailed>());
    expect(rejected, 1);
    session.dispose();
  });
}
