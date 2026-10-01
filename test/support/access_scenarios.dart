import 'dart:convert';
import 'dart:io';

import 'package:schedule_rules/schedule_rules.dart';

List<Map<String, dynamic>> loadAccessScenarios() => (jsonDecode(
  File('packages/schedule_rules/test/fixtures/access_scenarios.json')
      .readAsStringSync(),
) as List<dynamic>).cast<Map<String, dynamic>>();

Access accessFromScenario(Map<String, dynamic> scenario) => Access(
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
      ? repairingMaintainer().activeRepair
      : null,
);

Access repairingMaintainer() => Access(
  grants: Grants(),
  maintainer: true,
  ownStaffMemberId: 'staff',
  activeRepair: MaintainerRepair(
    id: 'repair',
    category: RepairReasonCategory.investigation,
    openedAt: DateTime.utc(2026, 9, 24, 12),
    expiresAt: DateTime.utc(2026, 9, 24, 13),
  ),
);
