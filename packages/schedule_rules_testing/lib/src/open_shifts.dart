part of '../schedule_rules_testing.dart';

extension InMemoryOpenShifts on InMemoryScheduleDatabase {
  OpenShiftStore openShiftStoreFor(String actor) =>
      _InMemoryOpenShiftStore(this, actor);
}

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
  Future<List<CoverageRulePlan>> previewCoveragePools(
    DateTime effectiveFrom,
    List<CoveragePoolConfig> pools,
  ) async => [];

  @override
  Future<void> commitCoveragePools(
    DateTime effectiveFrom,
    List<CoveragePoolConfig> pools,
    List<CoverageRulePlan> plan,
    List<CoverageRuleChoice> choices,
  ) => _saveCoveragePools(effectiveFrom, pools);

  @override
  Future<List<CoverageRulePlan>> previewStandingMinimum(
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
    List<CoverageRulePlan> plan,
    List<CoverageRuleChoice> choices,
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
  Future<List<CoverageRulePlan>> previewDateMinimum(
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
    List<CoverageRulePlan> plan,
    List<CoverageRuleChoice> choices,
  ) => setDateMinimum(pool, window, date, minimum, floor);
  bool get _manager => database.accessFor(actor).canRunSchedule;

  @override
  Future<List<OpenShift>> openShifts() async =>
      List.of(database._openShiftAnswers[actor] ?? const <OpenShift>[]);

  @override
  Future<int> hiddenOpenShiftCount(DateTime month) async =>
      database._hiddenOpenShiftCountAnswers[actor] ?? 0;

  @override
  Future<List<OpenShiftPickup>> pickups() async =>
      List.of(database._pickupAnswers[actor] ?? const <OpenShiftPickup>[]);

  @override
  Future<void> requestPickup(String openShiftId) async {
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
  Future<void> approvePickup(String pickupId) async =>
      _recordPickupDecision(pickupId, PickupStatus.approved);

  @override
  Future<void> declinePickup(String pickupId, {String? reason}) async =>
      _recordPickupDecision(pickupId, PickupStatus.declined);

  void _recordPickupDecision(String pickupId, PickupStatus status) {
    final index = database._openShiftPickups.indexWhere(
      (pickup) => pickup.id == pickupId,
    );
    if (index < 0) throw StateError('Pickup not seeded or recorded');
    final pickup = database._openShiftPickups[index];
    database._openShiftPickups[index] = OpenShiftPickup(
      id: pickup.id,
      openShiftId: pickup.openShiftId,
      staffMemberId: pickup.staffMemberId,
      status: status,
    );
  }

  @override
  Future<bool> approvalDefault() async => database._openShiftApprovalDefault;

  @override
  Future<void> setApprovalDefault(bool requiresApproval) async {
    database._openShiftApprovalDefault = requiresApproval;
  }

  @override
  Future<void> setShiftApproval(
    String openShiftId,
    bool requiresApproval,
  ) async {
    OpenShift revised(OpenShift shift) => shift.id != openShiftId
        ? shift
        : OpenShift(
            id: shift.id,
            sectionId: shift.sectionId,
            date: shift.date,
            shiftCode: shift.shiftCode,
            originalStaffMemberId: shift.originalStaffMemberId,
            jobRole: shift.jobRole,
            requiresApproval: requiresApproval,
          );
    for (final entry in database._openShiftAnswers.entries) {
      database._openShiftAnswers[entry.key] = entry.value.map(revised).toList();
    }
  }

  @override
  Future<List<SectionStaffing>> staffingForMonth(DateTime month) async {
    database._throwNextFailure(InMemoryStoreCall.staffingForMonth);
    return List.of(
      database._staffingAnswers[DateTime(month.year, month.month)] ?? const [],
    );
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
    database.recordedOpenShiftPosts.add((
      date: date,
      shiftCode: shiftCode,
      pool: pool,
      count: count,
      fillGap: fillGap,
    ));
    if (database._postOpenShiftResults.isNotEmpty) {
      return database._postOpenShiftResults.removeAt(0);
    }
    if (fillGap) {
      throw StateError('Seed the SQL post result for a gap fill');
    }
    return count;
  }

  @override
  Stream<void> updates() => const Stream<void>.empty();
}
