import 'package:er_schedule/staff/staff_gateway.dart';
import 'package:er_schedule/staff/staff_list_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:schedule_rules_testing/schedule_rules_testing.dart';

import 'support/in_memory_staff_gateway.dart';

void main() {
  test('used Section returns a typed refusal outcome', () async {
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(sections: [], members: []),
    )..deleteSectionError = const Refused(SectionRefusal.staffMembersAssigned);
    final session = StaffListSession(
      gateway,
      scheduleRulesInMemory(
        InMemoryScheduleDatabase(
          sections: const [],
          grants: {'manager': Grants(manager: true)},
        ),
        actingAs: 'manager',
      ),
    );

    final outcome = await session.deleteSection('days');

    expect(outcome, isA<SectionDeleteRefused>());
    expect((outcome as SectionDeleteRefused).code, 'P2795');
    session.dispose();
  });

  test('Section with Schedule history returns its own refusal', () async {
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(sections: [], members: []),
    )..deleteSectionError = const Refused(SectionRefusal.scheduleHistory);
    final session = StaffListSession(
      gateway,
      scheduleRulesInMemory(
        InMemoryScheduleDatabase(
          sections: const [],
          grants: {'manager': Grants(manager: true)},
        ),
        actingAs: 'manager',
      ),
    );

    final outcome = await session.deleteSection('days');

    expect(outcome, isA<SectionDeleteRefused>());
    expect((outcome as SectionDeleteRefused).code, 'P2849');
    session.dispose();
  });

  test('Access rejection is reported by a Staff-list command', () async {
    var rejections = 0;
    final gateway = InMemoryStaffGateway(
      actorRole: 'manager',
      list: const StaffList(sections: [], members: []),
    )..deleteSectionError = const AccessRejected();
    final session = StaffListSession(
      gateway,
      scheduleRulesInMemory(
        InMemoryScheduleDatabase(
          sections: const [],
          grants: {'manager': Grants(manager: true)},
        ),
        actingAs: 'manager',
      ),
      () => rejections++,
    );

    final outcome = await session.deleteSection('days');

    expect(outcome, isA<SectionDeleteFailed>());
    expect(rejections, 1);
    session.dispose();
  });
}
