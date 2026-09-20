part of '../schedule_rules.dart';

enum PickupStatus { pending, approved, declined }

final class OpenShift {
  const OpenShift({
    required this.id,
    required this.sectionId,
    required this.date,
    required this.shiftCode,
    this.originalStaffMemberId,
    required this.jobRole,
    this.requiresApproval = true,
  });
  final String id;
  final String? sectionId;
  final DateTime date;
  final String shiftCode;
  final String? originalStaffMemberId;
  final JobRole jobRole;
  final bool requiresApproval;
}

final class SectionStaffing {
  const SectionStaffing({
    required this.pool,
    required this.coverageWindow,
    required this.date,
    required this.minimum,
    required this.rnFloor,
    required this.workingCount,
    required this.rnCount,
    required this.openCount,
    required this.rnOpenCount,
    this.weekdayMinimum,
    this.dateMinimum,
  });
  final RolePool pool;
  final CoverageWindow coverageWindow;
  final DateTime date;
  final int? minimum;
  final int? rnFloor;
  final int workingCount;
  final int rnCount;
  final int openCount;
  final int rnOpenCount;
  final int? weekdayMinimum;
  final int? dateMinimum;
  int? get shortCount => minimum == null
      ? null
      : [minimum! - workingCount, (rnFloor ?? 0) - rnCount, 0]
          .reduce((a, b) => a > b ? a : b);
  int? get rnShortCount => minimum == null
      ? null
      : ((rnFloor ?? 0) - rnCount).clamp(0, 100);
  int? get unpostedCount => shortCount == null
      ? null
      : (shortCount! - openCount).clamp(0, 100);
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
  Future<void> declinePickup(String pickupId, {String? reason});
  Future<bool> approvalDefault();
  Future<void> setApprovalDefault(bool requiresApproval);
  Future<void> setShiftApproval(String openShiftId, bool requiresApproval);
  Future<List<SectionStaffing>> staffingForMonth(DateTime month);
  Future<void> setWeekdayMinimum(RolePool pool, CoverageWindow window,
      int weekday, int minimum, int rnFloor);
  Future<void> setDateMinimum(RolePool pool, CoverageWindow window,
      DateTime date, int? minimum, int? rnFloor);
  Future<int> postOpenShifts(
    DateTime date,
    String shiftCode,
    RolePool pool,
    int count, {
    bool fillGap = false,
  });
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
  Future<void> declinePickup(String pickupId, {String? reason}) =>
      store.declinePickup(pickupId, reason: reason?.trim());
  Future<bool> approvalDefault() => store.approvalDefault();
  Future<void> setApprovalDefault(bool requiresApproval) =>
      store.setApprovalDefault(requiresApproval);
  Future<void> setShiftApproval(String openShiftId, bool requiresApproval) =>
      store.setShiftApproval(openShiftId, requiresApproval);
  Future<List<SectionStaffing>> staffingForMonth(DateTime month) =>
      store.staffingForMonth(month);
  Future<void> setWeekdayMinimum(RolePool pool, CoverageWindow window,
          int weekday, int minimum, int rnFloor) =>
      store.setWeekdayMinimum(pool, window, weekday, minimum, rnFloor);
  Future<void> setDateMinimum(RolePool pool, CoverageWindow window,
          DateTime date, int? minimum, int? rnFloor) =>
      store.setDateMinimum(pool, window, date, minimum, rnFloor);
  Future<int> postOpenShifts(
    DateTime date,
    String shiftCode,
    RolePool pool,
    int count, {
    bool fillGap = false,
  }) => store.postOpenShifts(
    date,
    shiftCode,
    pool,
    count,
    fillGap: fillGap,
  );
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

  JobRole? _originalRole(String? id, DateTime date) => database._jobRoles[id]
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
    requiresApproval: database._openShiftApprovalOverrides[
            'short-${identityHashCode(short)}'] ??
        true,
  );

  @override
  Future<List<OpenShift>> openShifts() async {
    final visible = <OpenShift>[];
    for (final short in database._shortShifts) {
      if (!isWorkingShift(short.shiftCode, codes: database._shiftCodes)) {
        continue;
      }
      final role =
          short.jobRole ?? _originalRole(short.staffMemberId, short.date);
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
    final pickup = OpenShiftPickup(
        id: 'pickup-${database._openShiftPickups.length + 1}',
        openShiftId: openShiftId,
        staffMemberId: actor,
        status: PickupStatus.pending,
    );
    database._openShiftPickups.add(pickup);
    if (!shift.requiresApproval) await _completePickup(pickup.id);
  }

  @override
  Future<void> approvePickup(String pickupId) async {
    if (!_manager) throw StateError('Only the Manager can approve a pickup');
    await _completePickup(pickupId);
  }

  Future<void> _completePickup(String pickupId) async {
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
  Future<void> declinePickup(String pickupId, {String? reason}) async {
    if (!_manager) throw StateError('Only the Manager can decline a pickup');
    final index = database._openShiftPickups.indexWhere(
      (pickup) =>
          pickup.id == pickupId && pickup.status == PickupStatus.pending,
    );
    if (index < 0) throw StateError('Pickup is not awaiting approval');
    final pickup = database._openShiftPickups[index];
    database._openShiftPickups[index] = OpenShiftPickup(
      id: pickup.id,
      openShiftId: pickup.openShiftId,
      staffMemberId: pickup.staffMemberId,
      status: PickupStatus.declined,
    );
  }

  CoverageWindow? _windowForCode(String code) =>
      _coverageWindowOf(code, database._shiftCodes);

  @override
  Future<bool> approvalDefault() async => database._openShiftApprovalDefault;

  @override
  Future<void> setApprovalDefault(bool requiresApproval) async {
    if (!_manager) throw StateError('Only the Manager can set Open shift approval');
    database._openShiftApprovalDefault = requiresApproval;
  }

  @override
  Future<void> setShiftApproval(String openShiftId, bool requiresApproval) async {
    if (!_manager) throw StateError('Only the Manager can set Open shift approval');
    if (!(await openShifts()).any((shift) => shift.id == openShiftId)) {
      throw StateError('Open shift is unavailable');
    }
    database._openShiftApprovalOverrides[openShiftId] = requiresApproval;
  }

  @override
  Future<List<SectionStaffing>> staffingForMonth(DateTime month) async {
    database._throwNextFailure(InMemoryStoreCall.staffingForMonth);
    final grid = await ScheduleRules.inMemory(
      database,
      actingAs: actor,
    ).monthGrid(month);
    final result = <SectionStaffing>[];
    for (final date in grid.days) {
      final working = <(RolePool, CoverageWindow, JobRole)>[];
      for (final entry in grid.rowsOn(date)) {
        if (!isWorkingShift(entry.shiftCode, codes: database._shiftCodes)) continue;
        final window = _windowForCode(entry.shiftCode);
        final role = await _role(entry.row.staffMemberId, date);
        if (window != null && role != null) {
          working.add((RolePool.forJobRole(role), window, role));
        }
      }
      final opened = <(RolePool, CoverageWindow, JobRole)>[];
      for (final short in grid.shortShifts.where((item) => _sameDay(item.date, date))) {
        if (!isWorkingShift(short.shiftCode, codes: database._shiftCodes)) continue;
        final window = short.coverageWindow ?? _windowForCode(short.shiftCode);
        final role = short.jobRole ?? _originalRole(short.staffMemberId, date);
        if (window != null && role != null) {
          opened.add((RolePool.forJobRole(role), window, role));
        }
      }
      for (final pool in RolePool.values) {
        for (final window in CoverageWindow.values) {
          final weekdayKey = '${pool.value}:${window.value}:${date.weekday % 7}';
          final dateKey = '${pool.value}:${window.value}:${_day(date)}';
          final onFloor = working.where((item) => item.$1 == pool && item.$2 == window);
          final open = opened.where((item) => item.$1 == pool && item.$2 == window);
          result.add(SectionStaffing(
            pool: pool,
            coverageWindow: window,
            date: date,
            minimum: database._dateMinimums[dateKey] ?? database._weekdayMinimums[weekdayKey],
            rnFloor: database._dateRnFloors[dateKey] ?? database._weekdayRnFloors[weekdayKey],
            workingCount: onFloor.length,
            rnCount: onFloor.where((item) => item.$3 == JobRole.rn).length,
            openCount: open.length,
            rnOpenCount: open.where((item) => item.$3 == JobRole.rn).length,
            weekdayMinimum: database._weekdayMinimums[weekdayKey],
            dateMinimum: database._dateMinimums[dateKey],
          ));
        }
      }
    }
    return result;
  }

  @override
  Future<void> setWeekdayMinimum(RolePool pool, CoverageWindow window,
      int weekday, int minimum, int rnFloor) async {
    if (!_manager) throw StateError('Only the Manager can set staffing minimums');
    if (weekday < 0 || weekday > 6 || minimum < 0 || minimum > 100 ||
        rnFloor < 0 || rnFloor > minimum ||
        (pool != RolePool.nurses && rnFloor != 0)) {
      throw ArgumentError('Invalid staffing minimum');
    }
    final key = '${pool.value}:${window.value}:$weekday';
    database._weekdayMinimums[key] = minimum;
    database._weekdayRnFloors[key] = rnFloor;
  }

  @override
  Future<void> setDateMinimum(RolePool pool, CoverageWindow window,
      DateTime date, int? minimum, int? rnFloor) async {
    if (!_manager) throw StateError('Only the Manager can set staffing minimums');
    if (minimum != null && (minimum < 0 || minimum > 100 || rnFloor == null ||
        rnFloor < 0 || rnFloor > minimum ||
        (pool != RolePool.nurses && rnFloor != 0))) {
      throw ArgumentError('Invalid staffing minimum');
    }
    final key = '${pool.value}:${window.value}:${_day(date)}';
    if (minimum == null) {
      database._dateMinimums.remove(key);
      database._dateRnFloors.remove(key);
    } else {
      database._dateMinimums[key] = minimum;
      database._dateRnFloors[key] = rnFloor!;
    }
  }

  @override
  Future<int> postOpenShifts(DateTime date, String shiftCode, RolePool pool,
      int count, {bool fillGap = false}) async {
    if (!_manager) throw StateError('Only the Manager can post Open shifts');
    final code = shiftCode.trim().toUpperCase();
    final window = _windowForCode(code);
    if (!isWorkingShift(code, codes: database._shiftCodes) ||
        window == null || count < 1 || count > 100) {
      throw ArgumentError('Invalid Open shift');
    }
    var rnCritical = 0;
    if (fillGap) {
      final staffing = (await staffingForMonth(date)).firstWhere((item) =>
          item.pool == pool && item.coverageWindow == window &&
          _sameDay(item.date, date));
      count = count < (staffing.unpostedCount ?? 0)
          ? count : (staffing.unpostedCount ?? 0);
      rnCritical = ((staffing.rnShortCount ?? 0) - staffing.rnOpenCount)
          .clamp(0, count);
    }
    for (var i = 0; i < count; i++) {
      database._shortShifts.add(ShortShift(
        date: date,
        shiftCode: code,
        staffMemberId: null,
        jobRole: pool == RolePool.nurses && i < rnCritical
            ? JobRole.rn
            : switch (pool) {
                RolePool.nurses => JobRole.lpn,
                RolePool.cna => JobRole.cna,
                RolePool.unitClerk => JobRole.unitClerk,
              },
        coverageWindow: window,
      ));
      database._openShiftApprovalOverrides[
          'short-${identityHashCode(database._shortShifts.last)}'] =
          i < rnCritical ? true : database._openShiftApprovalDefault;
    }
    return count;
  }

  @override
  Stream<void> updates() => const Stream<void>.empty();
}
