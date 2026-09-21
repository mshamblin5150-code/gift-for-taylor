import 'dart:convert';
import 'dart:io';

import 'package:schedule_rules/schedule_rules.dart';
import 'package:test/test.dart';

import '../tool/generate_access_scenarios.dart' as generator;

void main() {
  final fixture = File('test/fixtures/access_scenarios.json')
      .readAsStringSync();
  final scenarios = (jsonDecode(fixture) as List<dynamic>)
      .cast<Map<String, dynamic>>();

  for (final scenario in scenarios) {
    test('${scenario['name']} answers shared Access questions', () {
      final access = Access(
        grants: Grants(
          manager: scenario['manager'] as bool,
          administrator: scenario['administrator'] as bool,
          nightSchedulerSectionIds: (scenario['sections'] as List<dynamic>)
              .cast<String>()
              .toSet(),
        ),
        maintainer: scenario['maintainer'] as bool,
        ownStaffMemberId: scenario['staffMemberId'] as String?,
      );
      expect(access.canEditSection('nights'), scenario['editSection']);
      expect(
        access.editableSections.contains('nights'),
        scenario['editSection'],
      );
      expect(
        access.canEditSection('days'),
        (scenario['manager'] as bool) || (scenario['maintainer'] as bool),
      );
      expect(access.canRunSchedule, scenario['runSchedule']);
      expect(access.canManageStaff, scenario['manageStaff']);
      expect(access.canManageUnit, scenario['manageUnit']);
      expect(access.canReadChangeLog, scenario['readChangeLog']);
    });
  }

  test('client-only questions and value equality', () {
    final grants = Grants(
      administrator: true,
      nightSchedulerSectionIds: {'nights', 'days'},
    );
    expect(
      grants,
      Grants(administrator: true, nightSchedulerSectionIds: {'days', 'nights'}),
    );
    expect(
      grants.hashCode,
      Grants(
        administrator: true,
        nightSchedulerSectionIds: {'days', 'nights'},
      ).hashCode,
    );
    expect(grants.copyWith(administrator: false).nightSchedulerSectionIds, {
      'nights',
      'days',
    });
    expect(grants.copyWith(nightSchedulerSectionIds: {}).administrator, isTrue);
    final access = Access(grants: grants, ownStaffMemberId: 'staff');
    expect(
      access,
      Access(
        grants: Grants(
          administrator: true,
          nightSchedulerSectionIds: {'days', 'nights'},
        ),
        ownStaffMemberId: 'staff',
      ),
    );
    expect(access.canReadUnreleased, isTrue);
    expect(access.canTransferManager, isFalse);
    expect(access.ownStaffMemberId, 'staff');
    expect(access.isRepairAccess, isFalse);
    final maintainer = Access(grants: Grants(), maintainer: true);
    expect(maintainer.canTransferManager, isTrue);
    expect(maintainer.canReadUnreleased, isTrue);
    expect(maintainer.ownStaffMemberId, isNull);
    expect(maintainer.isRepairAccess, isTrue);
  });

  test(
    'in-memory grants remain independent and enforce Section edits',
    () async {
      final database = InMemoryScheduleDatabase(
        sections: const [
          ScheduleSection(id: 'nights', name: 'Nights'),
          ScheduleSection(id: 'days', name: 'Days'),
        ],
        rows: const [
          ScheduleRow(
            staffMemberId: 'staff',
            displayName: 'Staff',
            sectionId: 'nights',
          ),
        ],
        editors: const {'manager'},
        grants: {'staff': Grants(administrator: true)},
        maintainerId: 'maintainer',
      );
      final manager = ScheduleRules.inMemory(database, actingAs: 'manager');
      final staff = ScheduleRules.inMemory(database, actingAs: 'staff');
      final maintainer = ScheduleRules.inMemory(
        database,
        actingAs: 'maintainer',
      );
      await manager.assignNightScheduler('staff', {'nights'});
      expect(database.accessFor('staff').grants.administrator, isTrue);
      expect(await staff.canEditSchedule(), isFalse);
      expect((await staff.editableSections()).contains('nights'), isTrue);
      expect((await staff.editableSections()).contains('days'), isFalse);
      await staff.saveCell(
        SaveCell(
          staffMemberId: 'staff',
          sectionId: 'nights',
          date: DateTime(2026, 9, 21),
          shiftCode: 'N',
        ),
      );
      await expectLater(
        staff.saveCell(
          SaveCell(
            staffMemberId: 'staff',
            sectionId: 'days',
            date: DateTime(2026, 9, 22),
            shiftCode: 'N',
          ),
        ),
        throwsA(isA<ScheduleEditRefused>()),
      );
      await manager.removeNightScheduler('staff');
      expect(database.accessFor('staff').grants.administrator, isTrue);
      expect(
        database.accessFor('staff').grants.nightSchedulerSectionIds,
        isEmpty,
      );
      expect(await maintainer.canEditSchedule(), isTrue);
      expect(database.accessFor('maintainer').ownStaffMemberId, isNull);
    },
  );

  test('Manager grant survives assigned Night scheduler Sections', () async {
    final database = InMemoryScheduleDatabase(
      sections: const [],
      editors: const {'manager'},
    );
    final manager = ScheduleRules.inMemory(database, actingAs: 'manager');
    await manager.assignNightScheduler('manager', {'nights'});
    expect(await manager.canEditSchedule(), isTrue);
    expect((await manager.editableSections()).contains('days'), isTrue);
  });

  test('explicit grants do not give an unknown actor Manager access', () async {
    final database = InMemoryScheduleDatabase(
      sections: const [],
      grants: {'administrator': Grants(administrator: true)},
    );
    expect(database.accessFor('stranger').canRunSchedule, isFalse);
    expect(database.accessFor('administrator').canManageStaff, isTrue);
  });

  test('committed pgTAP matches the shared scenarios', () {
    expect(
      File('../../supabase/tests/database/access_scenarios.test.sql')
          .readAsStringSync(),
      generator.generateAccessScenarios(fixture),
    );
  });
}
