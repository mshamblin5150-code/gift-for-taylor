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
        activeRepair: (scenario['repair'] as bool? ?? false)
            ? MaintainerRepair(
                id: 'repair',
                category: RepairReasonCategory.investigation,
                openedAt: DateTime.utc(2026, 9, 24, 12),
                expiresAt: DateTime.utc(2026, 9, 24, 13),
              )
            : null,
      );
      expect(access.canEditSection('nights'), scenario['editSection']);
      expect(
        access.editableSections.contains('nights'),
        scenario['editSection'],
      );
      expect(
        access.canEditSection('days'),
        (scenario['manager'] as bool) || (scenario['repair'] as bool? ?? false),
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
    expect(access.canUseOwnSettings, isTrue);
    expect(access.canChangeAccess(Grants()), isTrue);
    expect(access.canChangeAccess(Grants(manager: true)), isFalse);
    expect(access.isRepairAccess, isFalse);
    final maintainer = Access(
      grants: Grants(),
      maintainer: true,
      ownStaffMemberId: 'staff',
    );
    expect(maintainer.canTransferManager, isFalse);
    expect(maintainer.canReadUnreleased, isFalse);
    expect(maintainer.ownStaffMemberId, 'staff');
    expect(maintainer.isRepairAccess, isFalse);
    expect(maintainer.canUseOwnSettings, isTrue);
    expect(maintainer.canChangeAccess(Grants()), isFalse);

    final repairing = Access(
      grants: Grants(),
      maintainer: true,
      ownStaffMemberId: 'staff',
      activeRepair: MaintainerRepair(
        id: 'repair',
        category: RepairReasonCategory.managerHandover,
        openedAt: DateTime.utc(2026, 9, 24, 12),
        expiresAt: DateTime.utc(2026, 9, 24, 13),
      ),
    );
    expect(repairing.canTransferManager, isTrue);
    expect(repairing.canReadUnreleased, isTrue);
    expect(repairing.ownStaffMemberId, 'staff');
    expect(repairing.isRepairAccess, isTrue);
    expect(repairing.canUseOwnSettings, isTrue);
    expect(repairing.canChangeAccess(Grants()), isTrue);
  });

  test('committed pgTAP matches the shared scenarios', () {
    expect(
      File('../../supabase/tests/database/access_scenarios.test.sql')
          .readAsStringSync()
          .replaceAll('\r\n', '\n'),
      generator.generateAccessScenarios(fixture),
    );
  });
}
