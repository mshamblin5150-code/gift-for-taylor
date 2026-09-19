part of '../schedule_rules.dart';

enum PickupStatus { pending, approved, declined }

final class OpenShift {
  const OpenShift({
    required this.id,
    required this.sectionId,
    required this.date,
    required this.shiftCode,
    required this.originalStaffMemberId,
    required this.jobRole,
  });
  final String id;
  final String sectionId;
  final DateTime date;
  final String shiftCode;
  final String originalStaffMemberId;
  final JobRole jobRole;
}

final class OpenShiftPickup {
  const OpenShiftPickup({
    required this.id,
    required this.openShiftId,
    required this.staffMemberId,
    required this.status,
  });
  final String id;
  final String openShiftId;
  final String staffMemberId;
  final PickupStatus status;
}

abstract interface class OpenShiftStore {
  Future<List<OpenShift>> openShifts();
  Future<List<OpenShiftPickup>> pickups();
  Future<void> requestPickup(String openShiftId);
  Future<void> approvePickup(String pickupId);
  Stream<void> updates();
}

final class OpenShiftRules {
  const OpenShiftRules(this.store);
  final OpenShiftStore store;
  Future<List<OpenShift>> openShifts() => store.openShifts();
  Future<List<OpenShiftPickup>> pickups() => store.pickups();
  Future<void> requestPickup(String openShiftId) =>
      store.requestPickup(openShiftId);
  Future<void> approvePickup(String pickupId) => store.approvePickup(pickupId);
  Stream<void> updates() => store.updates();
}

extension InMemoryOpenShifts on InMemoryScheduleDatabase {
  OpenShiftStore openShiftStoreFor(String actor) =>
      _InMemoryOpenShiftStore(this, actor);
}

bool _samePool(JobRole left, JobRole right) =>
    left == right ||
    ((left == JobRole.rn || left == JobRole.lpn) &&
        (right == JobRole.rn || right == JobRole.lpn));

final class _InMemoryOpenShiftStore implements OpenShiftStore {
  _InMemoryOpenShiftStore(this.database, this.actor);
  final InMemoryScheduleDatabase database;
  final String actor;
  bool get _manager =>
      !database._nightSchedulers.containsKey(actor) &&
      (database.editors?.contains(actor) ?? true);

  Future<JobRole?> _role(String id, DateTime date) =>
      ScheduleRules.inMemory(database, actingAs: actor).jobRoleOn(id, date);

  JobRole? _originalRole(String id, DateTime date) => database._jobRoles[id]
      ?.where((role) => !role.from.isAfter(date))
      .lastOrNull
      ?.jobRole;

  OpenShift _shift(ShortShift short, JobRole role) => OpenShift(
    id: 'short-${identityHashCode(short)}',
    sectionId: short.sectionId,
    date: short.date,
    shiftCode: short.shiftCode,
    originalStaffMemberId: short.staffMemberId,
    jobRole: role,
  );

  @override
  Future<List<OpenShift>> openShifts() async {
    final visible = <OpenShift>[];
    for (final short in database._shortShifts) {
      if (!isWorkingShift(short.shiftCode, codes: database._shiftCodes)) {
        continue;
      }
      final role = _originalRole(short.staffMemberId, short.date);
      if (role == null ||
          await database
                  .storeFor(actor)
                  .monthStatus(DateTime(short.date.year, short.date.month)) !=
              MonthStatus.released) {
        continue;
      }
      final mine = await _role(actor, short.date);
      if (_manager || (mine != null && _samePool(mine, role))) {
        visible.add(_shift(short, role));
      }
    }
    return visible;
  }

  @override
  Future<List<OpenShiftPickup>> pickups() async => [
    for (final pickup in database._openShiftPickups)
      if (_manager || pickup.staffMemberId == actor) pickup,
  ];

  @override
  Future<void> requestPickup(String openShiftId) async {
    if (_manager || !database._isActive(actor)) {
      throw StateError('Only Staff members can request a pickup');
    }
    final shift = (await openShifts())
        .where((shift) => shift.id == openShiftId)
        .firstOrNull;
    if (shift == null) throw StateError('Open shift is unavailable');
    final row = (await database.storeFor(actor).rows(shift.date))
        .where((row) => row.staffMemberId == actor)
        .firstOrNull;
    if (row == null ||
        (row.lastDay != null && shift.date.isAfter(row.lastDay!))) {
      throw StateError('Staff member is not on the Schedule for that day');
    }
    final current = database._cells[_cellKey(actor, shift.date)]?.shiftCode;
    if (current != null && current != '' && current != 'X') {
      throw StateError('You already have a shift that day');
    }
    if (database._openShiftPickups.any(
      (pickup) =>
          pickup.openShiftId == openShiftId && pickup.staffMemberId == actor,
    )) {
      throw StateError('Pickup already requested');
    }
    database._openShiftPickups.add(
      OpenShiftPickup(
        id: 'pickup-${database._openShiftPickups.length + 1}',
        openShiftId: openShiftId,
        staffMemberId: actor,
        status: PickupStatus.pending,
      ),
    );
  }

  @override
  Future<void> approvePickup(String pickupId) async {
    if (!_manager) throw StateError('Only the Manager can approve a pickup');
    final index = database._openShiftPickups.indexWhere(
      (pickup) =>
          pickup.id == pickupId && pickup.status == PickupStatus.pending,
    );
    if (index < 0) throw StateError('Pickup is not awaiting approval');
    final pickup = database._openShiftPickups[index];
    final shift = (await openShifts())
        .where((shift) => shift.id == pickup.openShiftId)
        .firstOrNull;
    if (shift == null) throw StateError('Open shift has been filled');
    final role = await _role(pickup.staffMemberId, shift.date);
    if (role == null ||
        !_samePool(role, shift.jobRole) ||
        !database._isActive(pickup.staffMemberId)) {
      throw StateError('Staff member is no longer eligible');
    }
    final row = (await database.storeFor(actor).rows(shift.date))
        .where((row) => row.staffMemberId == pickup.staffMemberId)
        .firstOrNull;
    if (row == null) throw StateError('Staff member is not on the Schedule');
    final current =
        database._cells[_cellKey(pickup.staffMemberId, shift.date)]?.shiftCode;
    if (current != null && current != '' && current != 'X') {
      throw StateError('Staff member already has a shift that day');
    }
    _InMemoryScheduleStore(database, actor)._write(
      ScheduleCell(
        staffMemberId: pickup.staffMemberId,
        sectionId: row.sectionId,
        date: shift.date,
        shiftCode: shift.shiftCode,
      ),
    );
    database._shortShifts.removeWhere(
      (short) => 'short-${identityHashCode(short)}' == shift.id,
    );
    database._openShiftPickups[index] = OpenShiftPickup(
      id: pickup.id,
      openShiftId: pickup.openShiftId,
      staffMemberId: pickup.staffMemberId,
      status: PickupStatus.approved,
    );
    for (final (otherIndex, other) in database._openShiftPickups.indexed) {
      if (otherIndex != index &&
          other.openShiftId == shift.id &&
          other.status == PickupStatus.pending) {
        database._openShiftPickups[otherIndex] = OpenShiftPickup(
          id: other.id,
          openShiftId: other.openShiftId,
          staffMemberId: other.staffMemberId,
          status: PickupStatus.declined,
        );
      }
    }
  }

  @override
  Stream<void> updates() => const Stream<void>.empty();
}
