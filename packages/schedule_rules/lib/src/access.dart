import '../schedule_rules.dart' show EditableSections;

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
  });

  final Grants grants;
  final bool maintainer;
  final String? ownStaffMemberId;

  bool get _managerLevel => grants.manager || maintainer;
  bool canEditSection(String id) =>
      _managerLevel || grants.nightSchedulerSectionIds.contains(id);
  EditableSections get editableSections => _managerLevel
      ? const EditableSections.all()
      : EditableSections.only(grants.nightSchedulerSectionIds);
  bool get canRunSchedule => _managerLevel;
  bool get canManageStaff => _managerLevel || grants.administrator;
  bool get canManageUnit => _managerLevel || grants.administrator;
  bool get canTransferManager => _managerLevel;
  bool get canReadUnreleased =>
      _managerLevel ||
      grants.administrator ||
      grants.nightSchedulerSectionIds.isNotEmpty;
  bool get canReadChangeLog =>
      _managerLevel ||
      grants.administrator ||
      grants.nightSchedulerSectionIds.isNotEmpty;
  bool get isRepairAccess => maintainer;

  @override
  bool operator ==(Object other) =>
      other is Access &&
      grants == other.grants &&
      maintainer == other.maintainer &&
      ownStaffMemberId == other.ownStaffMemberId;

  @override
  int get hashCode => Object.hash(grants, maintainer, ownStaffMemberId);
}
