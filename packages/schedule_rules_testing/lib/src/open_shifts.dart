part of '../schedule_rules_testing.dart';

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
  @override
  Future<List<CoveragePoolConfig>> coveragePoolsOn(DateTime date) async {
    final seeds = [
      CoveragePoolConfig(
        id: 'nurses',
        name: 'Nurses',
        sortOrder: 0,
        retired: false,
        jobRoles: {JobRole.rn, JobRole.lpn},
        floorRole: JobRole.rn,
      ),
      CoveragePoolConfig(
        id: 'cna',
        name: 'CNAs',
        sortOrder: 1,
        retired: false,
        jobRoles: {JobRole.cna},
      ),
      CoveragePoolConfig(
        id: 'unit_clerk',
        name: 'Unit clerks',
        sortOrder: 2,
        retired: false,
        jobRoles: {JobRole.unitClerk},
      ),
    ];
    final configs = <CoveragePoolConfig>[];
    for (final seed in seeds) {
      final history = database._coveragePoolVersions[seed.id]
          ?.where((entry) => !entry.from.isAfter(date))
          .toList();
      configs.add(
        history == null || history.isEmpty
            ? seed
            : (history..sort((a, b) => a.from.compareTo(b.from))).last.config,
      );
    }
    for (final entry in database._coveragePoolVersions.entries) {
      if (seeds.any((seed) => seed.id == entry.key)) continue;
      final history =
          entry.value.where((item) => !item.from.isAfter(date)).toList()
            ..sort((a, b) => a.from.compareTo(b.from));
      if (history.isNotEmpty) configs.add(history.last.config);
    }
    return configs..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  @override
  Future<List<Map<String, dynamic>>> coverageRuleHistory() async =>
      database._coverageRuleHistory.reversed.toList();

  List<Map<String, dynamic>> _poolSnapshot(List<CoveragePoolConfig> pools) => [
    for (final pool in pools)
      {
        'id': pool.id,
        'name': pool.name,
        'sort_order': pool.sortOrder,
        'retired': pool.retired,
        'floor_role': pool.floorRole?.value,
        'job_roles': [for (final role in pool.jobRoles) role.value],
      },
  ];

  void _recordRuleChange(
    String action,
    DateTime effectiveFrom,
    Object? before,
    Object? after,
  ) {
    database._coverageRuleHistory.add({
      'action': action,
      'actor_name': actor,
      'effective_from': _day(effectiveFrom),
      'changed_at': database._clock().toIso8601String(),
      'before_value': before,
      'after_value': after,
    });
  }

  Future<void> _saveCoveragePools(
    DateTime effectiveFrom,
    List<CoveragePoolConfig> pools,
  ) async {
    if (!_manager) throw StateError('Only the Manager can edit Coverage pools');
    if (effectiveFrom.isBefore(
      DateTime(
        database._clock().year,
        database._clock().month,
        database._clock().day,
      ),
    )) {
      throw ArgumentError('Coverage pool changes cannot start before today');
    }
    final before = _poolSnapshot(await coveragePoolsOn(effectiveFrom));
    final roles = [for (final pool in pools) ...pool.jobRoles];
    if (roles.length != JobRole.values.length ||
        roles.toSet().length != roles.length ||
        pools.any(
          (pool) =>
              pool.retired && pool.jobRoles.isNotEmpty ||
              !pool.retired && pool.jobRoles.isEmpty ||
              pool.floorRole != null && !pool.jobRoles.contains(pool.floorRole),
        )) {
      throw ArgumentError('Invalid Coverage pool membership or floor');
    }
    for (final pool in pools) {
      final history = database._coveragePoolVersions.putIfAbsent(
        pool.id,
        () => [],
      );
      history.removeWhere((entry) => _sameDay(entry.from, effectiveFrom));
      history.add((from: effectiveFrom, config: pool));
    }
    _recordRuleChange(
      'coverage_pools',
      effectiveFrom,
      before,
      _poolSnapshot(pools),
    );
  }

  Future<void> _setStandingMinimum(
    CoveragePool pool,
    CoverageWindow window,
    int weekday,
    DateTime effectiveFrom,
    int minimum,
    JobRole? floorRole,
    int floor,
  ) async {
    if (!_manager) {
      throw StateError('Only the Manager can set Staffing minimums');
    }
    if (effectiveFrom.isBefore(
          DateTime(
            database._clock().year,
            database._clock().month,
            database._clock().day,
          ),
        ) ||
        weekday < 0 ||
        weekday > 6 ||
        minimum < 0 ||
        minimum > 100 ||
        floor < 0 ||
        floor > minimum) {
      throw ArgumentError('Invalid Staffing minimum');
    }
    final config = (await coveragePoolsOn(effectiveFrom))
        .where((item) => item.id == pool.value && !item.retired)
        .firstOrNull;
    if (config == null ||
        floor > 0 &&
            (config.floorRole != floorRole ||
                !config.jobRoles.contains(floorRole))) {
      throw ArgumentError('Floor Job role must belong to the Coverage pool');
    }
    final key = '${pool.value}:${window.value}:$weekday';
    final history = database._standingRuleVersions.putIfAbsent(key, () => []);
    final before = history
        .where((entry) => !entry.from.isAfter(effectiveFrom))
        .lastOrNull;
    history.removeWhere((entry) => _sameDay(entry.from, effectiveFrom));
    history.add((
      from: effectiveFrom,
      minimum: minimum,
      floorRole: floorRole,
      floor: floor,
    ));
    _recordRuleChange(
      'weekday_minimum',
      effectiveFrom,
      {
        'pool': pool.value,
        'window': window.value,
        'weekday': weekday,
        'minimum': before?.minimum,
        'floor_role': before?.floorRole?.value,
        'floor': before?.floor,
      },
      {
        'pool': pool.value,
        'window': window.value,
        'weekday': weekday,
        'minimum': minimum,
        'floor_role': floorRole?.value,
        'floor': floor,
      },
    );
  }

  @override
  Future<List<Map<String, dynamic>>> previewCoveragePools(
    DateTime effectiveFrom,
    List<CoveragePoolConfig> pools,
  ) async => [];

  @override
  Future<void> commitCoveragePools(
    DateTime effectiveFrom,
    List<CoveragePoolConfig> pools,
    List<Map<String, dynamic>> plan,
    List<Map<String, dynamic>> choices,
  ) => _saveCoveragePools(effectiveFrom, pools);

  @override
  Future<List<Map<String, dynamic>>> previewStandingMinimum(
    CoveragePool pool,
    CoverageWindow window,
    int weekday,
    DateTime effectiveFrom,
    int minimum,
    JobRole? floorRole,
    int floor,
  ) async => [];

  @override
  Future<void> commitStandingMinimum(
    CoveragePool pool,
    CoverageWindow window,
    int weekday,
    DateTime effectiveFrom,
    int minimum,
    JobRole? floorRole,
    int floor,
    List<Map<String, dynamic>> plan,
    List<Map<String, dynamic>> choices,
  ) => _setStandingMinimum(
    pool,
    window,
    weekday,
    effectiveFrom,
    minimum,
    floorRole,
    floor,
  );

  @override
  Future<List<Map<String, dynamic>>> previewDateMinimum(
    CoveragePool pool,
    CoverageWindow window,
    DateTime date,
    int? minimum,
    JobRole? floorRole,
    int floor,
  ) async => [];

  @override
  Future<void> commitDateMinimum(
    CoveragePool pool,
    CoverageWindow window,
    DateTime date,
    int? minimum,
    JobRole? floorRole,
    int floor,
    List<Map<String, dynamic>> plan,
    List<Map<String, dynamic>> choices,
  ) => setDateMinimum(pool, window, date, minimum, floor);
  bool get _manager => database.accessFor(actor).canRunSchedule;

  Future<JobRole?> _role(String id, DateTime date) =>
      scheduleRulesInMemory(database, actingAs: actor).jobRoleOn(id, date);

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
    requiresApproval:
        database
            ._openShiftApprovalOverrides['short-${identityHashCode(short)}'] ??
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
    if (!_manager) {
      throw StateError('Only the Manager can set Open shift approval');
    }
    database._openShiftApprovalDefault = requiresApproval;
  }

  @override
  Future<void> setShiftApproval(
    String openShiftId,
    bool requiresApproval,
  ) async {
    if (!_manager) {
      throw StateError('Only the Manager can set Open shift approval');
    }
    if (!(await openShifts()).any((shift) => shift.id == openShiftId)) {
      throw StateError('Open shift is unavailable');
    }
    database._openShiftApprovalOverrides[openShiftId] = requiresApproval;
  }

  @override
  Future<List<SectionStaffing>> staffingForMonth(DateTime month) async {
    database._throwNextFailure(InMemoryStoreCall.staffingForMonth);
    final grid = await scheduleRulesInMemory(
      database,
      actingAs: actor,
    ).monthGrid(month);
    final result = <SectionStaffing>[];
    for (final date in grid.days) {
      final configs = (await coveragePoolsOn(date))
          .where((pool) => !pool.retired)
          .toList();
      CoveragePool poolFor(JobRole role) {
        final config = configs.firstWhere(
          (pool) => pool.jobRoles.contains(role),
        );
        return CoveragePool(
          config.id,
          config.name,
          sortOrder: config.sortOrder,
        );
      }

      final working = <(CoveragePool, CoverageWindow, JobRole)>[];
      for (final entry in grid.rowsOn(date)) {
        if (!isWorkingShift(entry.shiftCode, codes: database._shiftCodes)) {
          continue;
        }
        final window = _windowForCode(entry.shiftCode);
        final role = await _role(entry.row.staffMemberId, date);
        if (window != null && role != null) {
          working.add((poolFor(role), window, role));
        }
      }
      final opened = <(CoveragePool, CoverageWindow, JobRole)>[];
      for (final short in grid.shortShifts.where(
        (item) => _sameDay(item.date, date),
      )) {
        if (!isWorkingShift(short.shiftCode, codes: database._shiftCodes)) {
          continue;
        }
        final window = short.coverageWindow ?? _windowForCode(short.shiftCode);
        final role = short.jobRole ?? _originalRole(short.staffMemberId, date);
        if (window != null && role != null) {
          opened.add((poolFor(role), window, role));
        }
      }
      for (final config in configs) {
        final pool = CoveragePool(
          config.id,
          config.name,
          sortOrder: config.sortOrder,
        );
        for (final window in CoverageWindow.values) {
          final weekdayKey =
              '${pool.value}:${window.value}:${date.weekday % 7}';
          final dateKey = '${pool.value}:${window.value}:${_day(date)}';
          final onFloor = working.where(
            (item) => item.$1 == pool && item.$2 == window,
          );
          final open = opened.where(
            (item) => item.$1 == pool && item.$2 == window,
          );
          final history =
              database._standingRuleVersions[weekdayKey]
                  ?.where((entry) => !entry.from.isAfter(date))
                  .toList()
                ?..sort((a, b) => a.from.compareTo(b.from));
          final standing = history?.lastOrNull;
          final floorRole = config.floorRole;
          final weekdayMinimum =
              standing?.minimum ?? database._weekdayMinimums[weekdayKey];
          final weekdayFloor =
              standing?.floor ?? database._weekdayRnFloors[weekdayKey];
          final minimum = database._dateMinimums[dateKey] ?? weekdayMinimum;
          final floor = database._dateRnFloors[dateKey] ?? weekdayFloor;
          final floorShortfall = minimum == null
              ? null
              : ((floor ?? 0) -
                        onFloor.where((item) => item.$3 == floorRole).length)
                    .clamp(0, 100);
          final shortfall = minimum == null
              ? null
              : [
                  minimum - onFloor.length,
                  floorShortfall!,
                  0,
                ].reduce((a, b) => a > b ? a : b);
          result.add(
            SectionStaffing(
              pool: pool,
              coverageWindow: window,
              date: date,
              minimum: minimum,
              rnFloor: floor,
              workingCount: onFloor.length,
              rnCount: onFloor.where((item) => item.$3 == floorRole).length,
              openCount: open.length,
              rnOpenCount: open.where((item) => item.$3 == floorRole).length,
              shortCount: shortfall,
              rnShortCount: floorShortfall,
              unpostedCount: shortfall == null
                  ? null
                  : (shortfall - open.length).clamp(0, 100),
              weekdayMinimum: weekdayMinimum,
              dateMinimum: database._dateMinimums[dateKey],
              floorRole: floorRole,
            ),
          );
        }
      }
    }
    return result;
  }

  @override
  Future<void> setWeekdayMinimum(
    CoveragePool pool,
    CoverageWindow window,
    int weekday,
    int minimum,
    int rnFloor,
  ) async {
    if (!_manager) {
      throw StateError('Only the Manager can set staffing minimums');
    }
    final config = (await coveragePoolsOn(database._clock()))
        .where((item) => item.id == pool.value && !item.retired)
        .firstOrNull;
    if (weekday < 0 ||
        weekday > 6 ||
        minimum < 0 ||
        minimum > 100 ||
        rnFloor < 0 ||
        rnFloor > minimum ||
        (rnFloor > 0 && config?.floorRole == null)) {
      throw ArgumentError('Invalid staffing minimum');
    }
    final key = '${pool.value}:${window.value}:$weekday';
    database._weekdayMinimums[key] = minimum;
    database._weekdayRnFloors[key] = rnFloor;
  }

  @override
  Future<void> setDateMinimum(
    CoveragePool pool,
    CoverageWindow window,
    DateTime date,
    int? minimum,
    int? rnFloor,
  ) async {
    if (!_manager) {
      throw StateError('Only the Manager can set staffing minimums');
    }
    final config = (await coveragePoolsOn(date))
        .where((item) => item.id == pool.value && !item.retired)
        .firstOrNull;
    if (minimum != null &&
        (minimum < 0 ||
            minimum > 100 ||
            rnFloor == null ||
            rnFloor < 0 ||
            rnFloor > minimum ||
            (rnFloor > 0 && config?.floorRole == null))) {
      throw ArgumentError('Invalid staffing minimum');
    }
    final key = '${pool.value}:${window.value}:${_day(date)}';
    final before = {
      'pool': pool.value,
      'window': window.value,
      'date': _day(date),
      'minimum': database._dateMinimums[key],
      'floor': database._dateRnFloors[key],
    };
    if (minimum == null) {
      database._dateMinimums.remove(key);
      database._dateRnFloors.remove(key);
    } else {
      database._dateMinimums[key] = minimum;
      database._dateRnFloors[key] = rnFloor!;
    }
    _recordRuleChange('date_minimum', date, before, {
      'pool': pool.value,
      'window': window.value,
      'date': _day(date),
      'minimum': minimum,
      'floor': rnFloor,
    });
  }

  @override
  Future<int> postOpenShifts(
    DateTime date,
    String shiftCode,
    CoveragePool pool,
    int count, {
    bool fillGap = false,
  }) async {
    if (!_manager) throw StateError('Only the Manager can post Open shifts');
    final code = shiftCode.trim().toUpperCase();
    final window = _windowForCode(code);
    if (!isWorkingShift(code, codes: database._shiftCodes) ||
        window == null ||
        count < 1 ||
        count > 100) {
      throw ArgumentError('Invalid Open shift');
    }
    var rnCritical = 0;
    final config = (await coveragePoolsOn(date))
        .where((item) => item.id == pool.value && !item.retired)
        .firstOrNull;
    if (config == null || config.jobRoles.isEmpty) {
      throw ArgumentError('Invalid Coverage pool');
    }
    if (fillGap) {
      final staffing = (await staffingForMonth(date)).firstWhere(
        (item) =>
            item.pool == pool &&
            item.coverageWindow == window &&
            _sameDay(item.date, date),
      );
      count = count < (staffing.unpostedCount ?? 0)
          ? count
          : (staffing.unpostedCount ?? 0);
      rnCritical = ((staffing.rnShortCount ?? 0) - staffing.rnOpenCount).clamp(
        0,
        count,
      );
    }
    for (var i = 0; i < count; i++) {
      database._shortShifts.add(
        ShortShift(
          date: date,
          shiftCode: code,
          staffMemberId: null,
          jobRole: i < rnCritical
              ? config.floorRole
              : config.jobRoles
                        .where((role) => role != config.floorRole)
                        .firstOrNull ??
                    config.floorRole ??
                    config.jobRoles.first,
          coveragePool: pool,
          coverageWindow: window,
        ),
      );
      database._openShiftApprovalOverrides['short-${identityHashCode(database._shortShifts.last)}'] =
          i < rnCritical ? true : database._openShiftApprovalDefault;
    }
    return count;
  }

  @override
  Stream<void> updates() => const Stream<void>.empty();
}
