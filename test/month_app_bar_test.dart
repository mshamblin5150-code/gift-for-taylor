import 'dart:convert';
import 'dart:io';

import 'package:er_schedule/schedule/pending_work.dart';
import 'package:er_schedule/schedule/schedule_destinations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'support/app_dependencies.dart';

void main() {
  final scenarios = (jsonDecode(
    File('packages/schedule_rules/test/fixtures/access_scenarios.json')
        .readAsStringSync(),
  ) as List<dynamic>).cast<Map<String, dynamic>>();

  for (final scenario in scenarios) {
    test('${scenario['name']} is offered the expected destinations', () {
      final access = _accessFrom(scenario);
      final entries = scheduleDestinations(
        dependencies: appDependencies(),
        access: access,
        pending: const PendingWorkState(
          pendingApprovals: 2,
          pendingSwaps: 3,
          unreadRequestsOff: 4,
        ),
      );

      expect(
        entries.map((entry) => entry.id.name).toSet(),
        _expectedIds(access),
      );
      expect(
        entries
            .where((entry) => entry.menu != DestinationMenu.none)
            .map((entry) => entry.id.name)
            .toSet(),
        _expectedMenuIds(access).toSet(),
      );
      expect(
        entries
            .where((entry) => entry.settings != null)
            .map((entry) => entry.id.name)
            .toSet(),
        _expectedSettingsIds(access).toSet(),
      );
      expect(
        entries
            .where((entry) => entry.group == DestinationGroup.browseRequests)
            .map((entry) => entry.id.name),
        access.canRunSchedule
            ? [
                'requestsOffManager',
                'swapsManager',
                'giveawaysManager',
                'openShiftsManager',
              ]
            : isEmpty,
      );
      expect(
        entries
            .where((entry) => entry.id == ScheduleDestinationId.approvalQueue)
            .map((entry) => entry.badgeCount),
        access.canRunSchedule ? [2] : isEmpty,
      );
      expect(
        entries
            .where((entry) => entry.id == ScheduleDestinationId.swapsStaff)
            .map((entry) => entry.badgeCount),
        access.canAskAsStaffMember ? [3] : isEmpty,
      );
      expect(
        entries
            .where((entry) => entry.id == ScheduleDestinationId.myRequestsOff)
            .map((entry) => entry.badgeCount),
        access.canAskAsStaffMember ? [4] : isEmpty,
      );
    });
  }

  test('catalog owns the unified labels and reload behavior', () {
    final entries = scheduleDestinations(
      dependencies: appDependencies(),
      access: Access(
        grants: Grants(manager: true),
        maintainer: true,
        ownStaffMemberId: 'staff',
      ),
      pending: const PendingWorkState(),
    );
    String label(ScheduleDestinationId id) =>
        entries.singleWhere((entry) => entry.id == id).label;

    expect(label(ScheduleDestinationId.notices), 'Notices');
    expect(label(ScheduleDestinationId.staffingMinimums), 'Staffing minimums');
    expect(label(ScheduleDestinationId.shiftCodes), 'Shift codes');
    expect(label(ScheduleDestinationId.staffList), 'Staff list');
    expect(
      label(ScheduleDestinationId.maintainerRepairs),
      'Maintainer repairs',
    );
    expect(
      entries
          .where((entry) => entry.reloadMonth)
          .map((entry) => entry.id.name)
          .toSet(),
      {
        'staffingMinimums',
        'shiftCodes',
        'sections',
        'permissionAssignments',
        'staffList',
      },
    );
  });

  test('locked Settings rows are derived from Repair destinations', () {
    final dependencies = appDependencies();
    final maintainer = Access(
      grants: Grants(),
      maintainer: true,
      ownStaffMemberId: 'staff',
    );
    final repairing = _repairingMaintainer();

    expect(
      lockedSettingsDestinations(
        dependencies: dependencies,
        access: maintainer,
        pending: const PendingWorkState(),
      ).map((entry) => entry.id.name).toSet(),
      {
        'signInFailures',
        'undeliveredInvitations',
        'transferManager',
        'staffingMinimums',
        'openShiftPickupApproval',
        'printWording',
        'shiftCodes',
        'sections',
        'permissionAssignments',
        'settingsHistory',
      },
    );
    expect(
      lockedSettingsDestinations(
        dependencies: dependencies,
        access: repairing,
        pending: const PendingWorkState(),
      ),
      isEmpty,
    );
    expect(
      lockedSettingsDestinations(
        dependencies: dependencies,
        access: Access(grants: Grants(), ownStaffMemberId: 'staff'),
        pending: const PendingWorkState(),
      ),
      isEmpty,
    );
  });
}

Set<String> _expectedIds(Access access) => {
  'settings',
  'help',
  'addErSchedule',
  if (access.ownStaffMemberId != null) ...{
    'putInTicket',
    'myTickets',
    'notices',
    'myCalendar',
  },
  if (access.maintainer) 'tickets',
  if (access.maintainer && !access.isRepairAccess) 'maintainerRepairs',
  if (access.maintainer && access.isRepairAccess) ...{
    'signInFailures',
    'undeliveredInvitations',
  },
  if (access.canAskAsStaffMember) ...{
    'openShiftsStaff',
    'swapsStaff',
    'giveawaysStaff',
    'myRequestsOff',
  },
  if (access.canRunSchedule) ...{
    'approvalQueue',
    'requestsOffManager',
    'swapsManager',
    'giveawaysManager',
    'openShiftsManager',
    'transferManager',
  },
  if (access.canManageUnit) ...{
    'staffingMinimums',
    'openShiftPickupApproval',
    'printWording',
    'shiftCodes',
    'sections',
    'permissionAssignments',
    'settingsHistory',
  },
  if (access.canReadChangeLog) 'changeLog',
  if (access.canManageStaff) 'staffList',
};

Iterable<String> _expectedMenuIds(Access access) => _expectedIds(access).where(
  (id) => !{
    'tickets',
    'signInFailures',
    'undeliveredInvitations',
    'addErSchedule',
    'openShiftPickupApproval',
    'printWording',
    'sections',
    'permissionAssignments',
    'transferManager',
    'settingsHistory',
  }.contains(id),
);

Iterable<String> _expectedSettingsIds(Access access) => _expectedIds(access)
    .where(
      (id) => {
        'tickets',
        'maintainerRepairs',
        'signInFailures',
        'undeliveredInvitations',
        'notices',
        'myCalendar',
        'addErSchedule',
        'staffingMinimums',
        'openShiftPickupApproval',
        'printWording',
        'shiftCodes',
        'sections',
        'permissionAssignments',
        'transferManager',
        'settingsHistory',
      }.contains(id),
    );

Access _accessFrom(Map<String, dynamic> scenario) => Access(
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
      ? _repairingMaintainer().activeRepair
      : null,
);

Access _repairingMaintainer() => Access(
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
