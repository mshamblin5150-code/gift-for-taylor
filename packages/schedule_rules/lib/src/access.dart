import '../schedule_rules.dart' show EditableSections;

/// Why the Maintainer broke the glass for one bounded Repair.
enum RepairReasonCategory {
  managerHandover('manager_handover', 'Manager handover'),
  scheduleOrMonth('schedule_or_month', 'Schedule or Month'),
  unitSettings('unit_settings', 'Unit settings'),
  staffOrInvite('staff_or_invite', 'Staff record or Invite'),
  investigation('investigation', 'Investigating a fault'),
  somethingElse('something_else', 'Something else');

  const RepairReasonCategory(this.value, this.label);

  final String value;
  final String label;

  static RepairReasonCategory fromValue(String value) =>
      values.firstWhere((category) => category.value == value);
}

/// The open Repair that temporarily gives the Maintainer Manager authority.
final class MaintainerRepair {
  const MaintainerRepair({
    required this.id,
    required this.category,
    required this.openedAt,
    required this.expiresAt,
    this.detail,
    this.remaining,
  });

  final String id;
  final RepairReasonCategory category;
  final String? detail;
  final DateTime openedAt;
  final DateTime expiresAt;
  final Duration? remaining;

  @override
  bool operator ==(Object other) =>
      other is MaintainerRepair &&
      id == other.id &&
      category == other.category &&
      detail == other.detail &&
      openedAt == other.openedAt &&
      expiresAt == other.expiresAt &&
      remaining == other.remaining;

  @override
  int get hashCode =>
      Object.hash(id, category, detail, openedAt, expiresAt, remaining);
}

/// Independent Access grants held by a Staff member.
final class Grants {
  Grants({
    this.manager = false,
    this.administrator = false,
    Set<String> nightSchedulerSectionIds = const {},
  }) : nightSchedulerSectionIds = Set.unmodifiable(nightSchedulerSectionIds);

  final bool manager;
  final bool administrator;
  final Set<String> nightSchedulerSectionIds;

  Grants copyWith({
    bool? manager,
    bool? administrator,
    Set<String>? nightSchedulerSectionIds,
  }) => Grants(
    manager: manager ?? this.manager,
    administrator: administrator ?? this.administrator,
    nightSchedulerSectionIds:
        nightSchedulerSectionIds ?? this.nightSchedulerSectionIds,
  );

  @override
  bool operator ==(Object other) =>
      other is Grants &&
      manager == other.manager &&
      administrator == other.administrator &&
      nightSchedulerSectionIds.length ==
          other.nightSchedulerSectionIds.length &&
      nightSchedulerSectionIds.containsAll(other.nightSchedulerSectionIds);

  @override
  int get hashCode => Object.hash(
    manager,
    administrator,
    Object.hashAllUnordered(nightSchedulerSectionIds),
  );
}

/// The viewer's answers derived from grants, not an exclusive role ranking.
final class Access {
  const Access({
    required this.grants,
    this.maintainer = false,
    this.ownStaffMemberId,
    this.activeRepair,
  });

  final Grants grants;
  final bool maintainer;
  final String? ownStaffMemberId;
  final MaintainerRepair? activeRepair;

  bool get _managerLevel => grants.manager || activeRepair != null;
  bool canEditSection(String id) =>
      _managerLevel || grants.nightSchedulerSectionIds.contains(id);
  EditableSections get editableSections => _managerLevel
      ? const EditableSections.all()
      : EditableSections.only(grants.nightSchedulerSectionIds);
  bool get canRunSchedule => _managerLevel;
  bool get canManageStaff => _managerLevel || grants.administrator;
  bool canChangeAccess(Grants target) => canManageStaff && !target.manager;
  bool get canManageUnit => _managerLevel || grants.administrator;
  bool get canTransferManager => _managerLevel;
  bool get canUseOwnSettings => ownStaffMemberId != null;
  bool get canUseStaffCellActions => ownStaffMemberId != null;
  bool get canReadUnreleased =>
      _managerLevel ||
      grants.administrator ||
      grants.nightSchedulerSectionIds.isNotEmpty;
  bool get canReadChangeLog =>
      _managerLevel ||
      grants.administrator ||
      grants.nightSchedulerSectionIds.isNotEmpty;
  bool get isRepairAccess => activeRepair != null;

  @override
  bool operator ==(Object other) =>
      other is Access &&
      grants == other.grants &&
      maintainer == other.maintainer &&
      ownStaffMemberId == other.ownStaffMemberId &&
      activeRepair == other.activeRepair;

  @override
  int get hashCode =>
      Object.hash(grants, maintainer, ownStaffMemberId, activeRepair);
}
