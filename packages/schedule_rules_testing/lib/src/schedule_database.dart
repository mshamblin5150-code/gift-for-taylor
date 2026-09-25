part of '../schedule_rules_testing.dart';

/// An in-memory stand-in for the database, shared by every scheduler in a
/// test.
enum InMemoryStoreCall {
  sections,
  shiftCodes,
  staffingForMonth,
  writeCell,
  writeCellPair,
  markChangesAnnounced,
  startMonth,
  releaseMonth,
  confirmLoadedMonth,
}

final class InMemoryScheduleDatabase {
  InMemoryScheduleDatabase({
    required List<ScheduleSection> sections,
    List<ScheduleRow> rows = const [],
    Map<String, Grants> grants = const {},
    this.maintainerId,
    this.maintainerRepair,
    Map<String, String> names = const {},
    List<LegendCode> shiftCodes = shiftLegend,
    this.managerEmail = 'manager@example.test',
    Set<DateTime> releasedMonths = const {},
    DateTime Function()? clock,
  }) : _monthStatus = {
         for (final month in releasedMonths)
           DateTime(month.year, month.month): MonthStatus.released,
       },
       _sections = List.unmodifiable(sections),
       _rows = List.unmodifiable(rows),
       _shiftCodes = List.of(shiftCodes),
       _grants = Map.of(grants),
       _nightSchedulerSections = {
         for (final entry in grants.entries)
           if (entry.value.nightSchedulerSectionIds.isNotEmpty)
             entry.key: {...entry.value.nightSchedulerSectionIds},
       },
       _names = {
         for (final row in rows) row.staffMemberId: row.displayName,
         ...names,
       },
       _clock = clock ?? DateTime.now {
    for (final row in rows) {
      if (row.hasPushSubscription) {
        _pushSubscriptions.add(row.staffMemberId);
      }
    }
  }

  final List<ScheduleSection> _sections;
  final List<ScheduleRow> _rows;

  final String? maintainerId;
  final MaintainerRepair? maintainerRepair;
  final Map<String, Grants> _grants;
  final Map<String, Set<String>> _nightSchedulerSections;
  final Map<String, Set<DateTime>> _hiddenMonthsByActor = {};
  final String managerEmail;

  /// Display names of everyone, including people not on a Schedule row such
  /// as the Manager.
  final Map<String, String> _names;
  final Set<String> _pushSubscriptions = {};
  final DateTime Function() _clock;

  final Map<String, ScheduleCell> _cells = {};
  final List<ScheduleChange> _changes = [];
  Map<String, ({bool announced, bool moot, String? reach})>?
  _settlementsAfterNextAnnouncement;
  final List<({Set<String> changeIds, Set<String> draftOpenedStaffMemberIds})>
  announcementWrites = [];
  final List<({DateTime month, bool acknowledgeShortfalls})> releaseWrites = [];
  final List<({DateTime month, bool acknowledgeShortfalls})>
  confirmationWrites = [];
  final List<ShortShift> _shortShifts = [];
  final Map<DateTime, List<SectionStaffing>> _staffingAnswers = {};
  final Map<DateTime, List<SectionStaffing>> _staffingAfterNextCellWrite = {};

  /// Supplies SQL's answer for a month. A later seed replaces the earlier one.
  void seedStaffingForMonth(DateTime month, List<SectionStaffing> answer) {
    _staffingAnswers[DateTime(month.year, month.month)] = List.of(answer);
  }

  /// Installs a second SQL answer once the next cell write has been recorded.
  void seedStaffingAfterNextCellWrite(
    DateTime month,
    List<SectionStaffing> answer,
  ) {
    _staffingAfterNextCellWrite[DateTime(month.year, month.month)] = List.of(
      answer,
    );
  }

  bool hasStaffingForMonth(DateTime month) =>
      _staffingAnswers.containsKey(DateTime(month.year, month.month));
  final List<LegendCode> _shiftCodes;

  /// Supplies the catalog returned by the next read, including SQL-derived fields.
  void seedShiftCodes(List<LegendCode> codes) {
    _shiftCodes
      ..clear()
      ..addAll(codes);
  }

  final Map<String, int> _weekdayMinimums = {
    for (var weekday = 0; weekday < 7; weekday++)
      for (final window in CoverageWindow.values)
        'nurses:${window.value}:$weekday': 3,
  };
  final Map<String, int> _weekdayRnFloors = {
    for (var weekday = 0; weekday < 7; weekday++)
      for (final window in CoverageWindow.values)
        'nurses:${window.value}:$weekday': 1,
  };
  final Map<String, int> _dateMinimums = {};
  final Map<String, int> _dateRnFloors = {};
  final List<Map<String, dynamic>> _coverageRuleHistory = [];
  final Map<String, List<({DateTime from, CoveragePoolConfig config})>>
  _coveragePoolVersions = {};
  final Map<
    String,
    List<({DateTime from, int minimum, JobRole? floorRole, int floor})>
  >
  _standingRuleVersions = {};
  final List<OpenShiftPickup> _openShiftPickups = [];
  final Map<String, List<OpenShiftPickup>> _pickupAnswers = {};
  final Map<String, List<OpenShift>> _openShiftAnswers = {};
  final Map<String, int> _hiddenOpenShiftCountAnswers = {};
  final List<
    ({
      DateTime date,
      String shiftCode,
      CoveragePool pool,
      int count,
      bool fillGap,
    })
  >
  recordedOpenShiftPosts = [];
  final List<int> _postOpenShiftResults = [];
  bool _openShiftApprovalDefault = true;
  final Map<DateTime, List<ScheduleRow>> _seededRows = {};
  final Map<DateTime, List<ShortShift>> _seededShortShifts = {};
  final Map<String, List<DatedJobRole>> _seededJobRoles = {};
  List<StaffChange>? _seededStaffChanges;
  final List<SetLastDay> lastDayWrites = [];
  final List<Reactivate> reactivationWrites = [];
  final List<ChangeSection> sectionWrites = [];
  final List<ChangeJobRole> jobRoleWrites = [];

  final List<RequestOff> _requestsOff = [];
  final List<RequestOff> _pendingRequestsOff = [];
  final Map<String, int> _unreadRequestOffNotices = {};
  final Map<String, bool> _onFloorNow = {};
  final Map<String, ({String previousCode, bool settled})> _callIns = {};
  final List<int> _callInPostedCounts = [];
  final StreamController<DateTime> _updates = StreamController.broadcast();
  final List<DateTime> _awaitingConfirmation = [];
  final Map<DateTime, MonthStatus> _monthStatus;
  final Map<InMemoryStoreCall, Object> _nextFailures = {};

  /// Makes the next matching store call fail, then resumes normal behavior.
  void failNext(InMemoryStoreCall call, Object error) {
    _nextFailures[call] = error;
  }

  /// SQL-derived answers are supplied by the test using this fixture.
  void seedRows(DateTime month, List<ScheduleRow> rows) =>
      _seededRows[DateTime(month.year, month.month)] = List.of(rows);

  void seedShortShifts(DateTime month, List<ShortShift> shifts) =>
      _seededShortShifts[DateTime(month.year, month.month)] = List.of(shifts);

  void seedJobRoles(String staffMemberId, List<DatedJobRole> roles) =>
      _seededJobRoles[staffMemberId] = List.of(roles);

  void seedStaffChanges(List<StaffChange> changes) =>
      _seededStaffChanges = List.of(changes);

  /// Supplies SQL's verdict for change IDs after the next announcement write.
  void seedAnnouncementSettlements(
    Map<String, ({bool announced, bool moot, String? reach})> settlements,
  ) => _settlementsAfterNextAnnouncement = Map.of(settlements);

  /// Supplies the Manager's pending Request off read without deriving a queue.
  void seedPendingRequestsOff(List<RequestOff> requests) {
    _pendingRequestsOff
      ..clear()
      ..addAll(requests);
  }

  /// Supplies the unread notice count returned to [staffMemberId].
  void seedUnreadRequestOffNotices(String staffMemberId, int count) {
    _unreadRequestOffNotices[staffMemberId] = count;
  }

  void seedOnFloorNow(String staffMemberId, bool value) {
    _onFloorNow[staffMemberId] = value;
  }

  void seedCallInPostedCount(int count) {
    _callInPostedCounts.add(count);
  }

  void settleCallIn(String staffMemberId, DateTime date) {
    final key = _cellKey(staffMemberId, date);
    final record = _callIns[key];
    if (record != null) {
      _callIns[key] = (previousCode: record.previousCode, settled: true);
    }
  }

  /// Supplies Open shifts created by SQL in a test scenario.
  void seedShortShift(ShortShift shift) => _shortShifts.add(shift);

  /// Supplies SQL's Open shift visibility answer for a test actor.
  void seedOpenShifts(String actor, List<OpenShift> shifts) {
    _openShiftAnswers[actor] = List.of(shifts);
  }

  /// Supplies SQL's count of Open shifts hidden from an actor.
  void seedHiddenOpenShiftCount(String actor, int count) {
    _hiddenOpenShiftCountAnswers[actor] = count;
  }

  /// Supplies SQL's posted count for the next Open shift post command.
  void seedPostOpenShiftResult(int count) {
    _postOpenShiftResults.add(count);
  }

  /// Supplies SQL's pickup answer when a test starts after a request.
  void seedOpenShiftPickups(String actor, List<OpenShiftPickup> pickups) {
    _pickupAnswers[actor] = List.of(pickups);
  }

  /// Pickup commands recorded so tests can seed a later SQL read.
  List<OpenShiftPickup> get recordedOpenShiftPickups =>
      List.unmodifiable(_openShiftPickups);

  /// Seeds a month that this actor cannot read.
  void hideMonthFor(String actor, DateTime month) {
    _hiddenMonthsByActor
        .putIfAbsent(actor, () => {})
        .add(DateTime(month.year, month.month));
  }

  void _throwNextFailure(InMemoryStoreCall call) {
    final error = _nextFailures.remove(call);
    if (error != null) throw error;
  }

  /// Loads [month] as transcribed from the printed page, without logging a
  /// change, to wait for the Manager's check.
  void loadFromPage(DateTime month, List<ScheduleCell> cells) {
    for (final cell in cells) {
      _cells[_cellKey(cell.staffMemberId, cell.date)] = cell;
    }
    final start = DateTime(month.year, month.month);
    _awaitingConfirmation.add(start);
    _monthStatus[start] = MonthStatus.unpublished;
  }

  /// Marks every logged change announced.
  void markAllAnnounced() => _markAnnounced((_) => true);

  void _markAnnounced(bool Function(ScheduleChange change) where) {
    for (final (index, change) in _changes.indexed) {
      if (!where(change)) continue;
      _changes[index] = ScheduleChange(
        id: change.id,
        staffMemberId: change.staffMemberId,
        date: change.date,
        oldShiftCode: change.oldShiftCode,
        newShiftCode: change.newShiftCode,
        changedBy: change.changedBy,
        changedByName: change.changedByName,
        changedAt: change.changedAt,
        announced: true,
      );
    }
  }

  /// The database as seen by [staffMemberId].
  ScheduleStore storeFor(String staffMemberId) =>
      _InMemoryScheduleStore(this, staffMemberId);

  Access accessFor(String actor) => Access(
    grants: _grants[actor] ?? Grants(),
    maintainer: actor == maintainerId,
    ownStaffMemberId: _isActive(actor) ? actor : null,
    activeRepair: actor == maintainerId ? maintainerRepair : null,
  );

  bool _isActive(String staffMemberId) => _names.containsKey(staffMemberId);
}

final class _InMemoryScheduleStore implements ScheduleStore {
  _InMemoryScheduleStore(this._database, this._actingAs);

  final InMemoryScheduleDatabase _database;
  final String _actingAs;
  Access get _access => _database.accessFor(_actingAs);

  @override
  Future<Access> currentAccess() async => _access;

  @override
  Future<List<LegendCode>> shiftCodes() async {
    _database._throwNextFailure(InMemoryStoreCall.shiftCodes);
    return List.unmodifiable(_database._shiftCodes);
  }

  @override
  Future<void> saveShiftCode(LegendCode code, {String? originalCode}) async {
    if (originalCode != null && originalCode != code.code) {
      _database._shiftCodes.removeWhere((item) => item.code == originalCode);
    }
    final index = _database._shiftCodes.indexWhere(
      (item) => item.code == code.code,
    );
    if (index == -1) {
      _database._shiftCodes.add(code);
    } else {
      _database._shiftCodes[index] = code;
    }
  }

  @override
  Future<void> deleteShiftCode(String code) async {
    _database._shiftCodes.removeWhere((item) => item.code == code);
  }

  @override
  Future<RequestOffEmail> createRequestOff(RequestOffDraft draft) async {
    final request = RequestOff(
      id: 'request-${_database._requestsOff.length + 1}',
      staffMemberId: _actingAs,
      staffMemberName: _database._names[_actingAs]!,
      dates: List.unmodifiable(draft.dates),
      reason: draft.reason,
      submittedAt: _database._clock(),
      emailConfirmedAt: null,
      decision: RequestOffDecision.pending,
      decisionReason: null,
      decidedAt: null,
    );
    _database._requestsOff.add(request);
    return RequestOffEmail.forRequest(
      requestId: request.id,
      to: _database.managerEmail,
      staffMemberName: request.staffMemberName,
      dates: request.dates,
      reason: request.reason,
    );
  }

  @override
  Future<void> confirmRequestOffEmail(String requestId) async {
    final index = _database._requestsOff.indexWhere((r) => r.id == requestId);
    if (index < 0) return;
    final request = _database._requestsOff[index];
    if (request.emailConfirmedAt == null) {
      _database._requestsOff[index] = request.withEmailConfirmed(
        _database._clock(),
      );
    }
  }

  @override
  Future<List<RequestOff>> requestsOff({required bool pendingOnly}) async {
    if (!pendingOnly) return List.unmodifiable(_database._requestsOff);
    return List.unmodifiable(_database._pendingRequestsOff);
  }

  @override
  Future<void> decideRequestOff(
    String requestId,
    RequestOffDecision decision,
    String? reason,
  ) async {
    final index = _database._requestsOff.indexWhere((r) => r.id == requestId);
    if (index < 0) return;
    final request = _database._requestsOff[index];
    _database._requestsOff[index] = request.withDecision(
      decision,
      reason,
      _database._clock(),
    );
    _database._pendingRequestsOff.removeWhere((item) => item.id == requestId);
  }

  @override
  Future<int> unreadRequestOffNotices() async =>
      _database._unreadRequestOffNotices[_actingAs] ?? 0;

  @override
  Future<void> acknowledgeRequestOffNotices() async {
    _database._unreadRequestOffNotices.remove(_actingAs);
  }

  @override
  Future<List<ScheduleSection>> sections() async {
    _database._throwNextFailure(InMemoryStoreCall.sections);
    return _database._sections;
  }

  @override
  Future<List<ScheduleRow>> rows(DateTime month) async {
    final seeded = _database._seededRows[DateTime(month.year, month.month)];
    if (seeded != null) return List.unmodifiable(seeded);
    return _database._rows;
  }

  @override
  Future<List<ScheduleCell>> cellsForMonth(DateTime month) async {
    if (!await _canSee(month)) return const [];
    return _database._cells.values
        .where((cell) => _inMonth(cell.date, month))
        .toList(growable: false);
  }

  @override
  Future<List<ScheduleChange>> changesForMonth(DateTime month) async {
    return _database._changes
        .where((change) => _inMonth(change.date, month))
        .toList(growable: false);
  }

  @override
  Future<List<ShortShift>> shortShiftsForMonth(DateTime month) async {
    final seeded =
        _database._seededShortShifts[DateTime(month.year, month.month)];
    if (seeded != null) return List.unmodifiable(seeded);
    return _database._shortShifts
        .where((item) => _inMonth(item.date, month))
        .toList(growable: false);
  }

  @override
  Future<void> writeCell(ScheduleCell cell) async {
    _database._throwNextFailure(InMemoryStoreCall.writeCell);
    final row = (await rows(DateTime(cell.date.year, cell.date.month)))
        .where((row) => row.staffMemberId == cell.staffMemberId)
        .firstOrNull;
    if (row == null || row.sectionId != cell.sectionId) {
      throw StateError(
        'That Staff member is not on the Staff list in this Section',
      );
    }
    final lastDay = row.lastDay;
    if (lastDay != null && cell.date.isAfter(lastDay)) {
      throw StateError('That day is after their Last day');
    }
    _write(cell);
  }

  @override
  Future<void> writeCellPair(SaveCellPair action) async {
    _database._throwNextFailure(InMemoryStoreCall.writeCellPair);
    final first = action.first;
    final second = action.second;
    if (first.staffMemberId == second.staffMemberId &&
        _sameDay(first.date, second.date)) {
      throw StateError('Choose two different Schedule cells');
    }
    if (!_inMonth(first.date, second.date)) {
      throw StateError('Both cells must be in the same month');
    }
    for (final cell in [first, second]) {
      final row = (await rows(DateTime(cell.date.year, cell.date.month)))
          .where((row) => row.staffMemberId == cell.staffMemberId)
          .firstOrNull;
      if (row == null ||
          row.sectionId != cell.sectionId ||
          (row.lastDay != null && cell.date.isAfter(row.lastDay!))) {
        throw StateError('That cell is outside the Staff member\'s Schedule');
      }
    }
    final firstOld =
        _database
            ._cells[_cellKey(first.staffMemberId, first.date)]
            ?.shiftCode ??
        '';
    final secondOld =
        _database
            ._cells[_cellKey(second.staffMemberId, second.date)]
            ?.shiftCode ??
        '';
    if (firstOld != first.shiftCode) {
      _write(
        ScheduleCell(
          staffMemberId: first.staffMemberId,
          sectionId: first.sectionId,
          date: first.date,
          shiftCode: first.shiftCode,
        ),
      );
    }
    if (secondOld != second.shiftCode) {
      _write(
        ScheduleCell(
          staffMemberId: second.staffMemberId,
          sectionId: second.sectionId,
          date: second.date,
          shiftCode: second.shiftCode,
        ),
      );
    }
  }

  @override
  Future<bool> isOnFloorNow() async =>
      _database._onFloorNow[_actingAs] ?? false;

  @override
  Future<int> recordCallIn(String staffMemberId, DateTime date) async {
    if (!await isOnFloorNow()) {
      throw const CallInRefused(CallInRefusal.recorderNotWorking);
    }
    final key = _cellKey(staffMemberId, date);
    final current = _database._cells[key];
    final legend = _database._shiftCodes
        .where((code) => code.code == current?.shiftCode.trim().toUpperCase())
        .firstOrNull;
    if (current == null || legend?.isWorking != true) {
      throw const CallInRefused(CallInRefusal.targetNotWorking);
    }
    _database._callIns[key] = (previousCode: current.shiftCode, settled: false);
    _write(
      ScheduleCell(
        staffMemberId: staffMemberId,
        sectionId: current.sectionId,
        date: date,
        shiftCode: 'C/I',
      ),
    );
    return _database._callInPostedCounts.isEmpty
        ? 0
        : _database._callInPostedCounts.removeAt(0);
  }

  @override
  Future<CallInWithdrawalState> callInWithdrawalState(
    String staffMemberId,
    DateTime date,
  ) async {
    final record = _database._callIns[_cellKey(staffMemberId, date)];
    if (record == null) return CallInWithdrawalState.notRecorded;
    return record.settled
        ? CallInWithdrawalState.settled
        : CallInWithdrawalState.withdrawable;
  }

  @override
  Future<void> withdrawCallIn(String staffMemberId, DateTime date) async {
    if (!await isOnFloorNow()) {
      throw const CallInRefused(CallInRefusal.recorderNotWorking);
    }
    final key = _cellKey(staffMemberId, date);
    final record = _database._callIns[key];
    if (record == null) {
      throw const CallInRefused(CallInRefusal.targetNotWorking);
    }
    if (record.settled) {
      throw const CallInRefused(CallInRefusal.settled);
    }
    final current = _database._cells[key]!;
    _write(
      ScheduleCell(
        staffMemberId: staffMemberId,
        sectionId: current.sectionId,
        date: date,
        shiftCode: record.previousCode,
      ),
    );
    _database._callIns.remove(key);
  }

  void _write(ScheduleCell cell) {
    final key = _cellKey(cell.staffMemberId, cell.date);
    final old = _database._cells[key]?.shiftCode ?? '';
    _database._monthStatus.putIfAbsent(
      DateTime(cell.date.year, cell.date.month),
      () => MonthStatus.unpublished,
    );
    _database._cells[key] = cell;
    final month = DateTime(cell.date.year, cell.date.month);
    final nextStaffing = _database._staffingAfterNextCellWrite.remove(month);
    if (nextStaffing != null) _database._staffingAnswers[month] = nextStaffing;
    _database._changes.add(
      ScheduleChange(
        id: 'change-${_database._changes.length + 1}',
        staffMemberId: cell.staffMemberId,
        date: cell.date,
        oldShiftCode: old,
        newShiftCode: cell.shiftCode,
        changedBy: _actingAs,
        changedByName: _database._names[_actingAs] ?? _actingAs,
        changedAt: _database._clock(),
        announced: false,
      ),
    );
    _database._updates.add(cell.date);
  }

  @override
  Future<void> assignNightScheduler(
    String staffMemberId,
    Set<String> sectionIds,
  ) async {
    _database._nightSchedulerSections[staffMemberId] = {...sectionIds};
  }

  @override
  Future<void> removeNightScheduler(String staffMemberId) async {
    _database._nightSchedulerSections.remove(staffMemberId);
  }

  @override
  Future<List<NightScheduler>> nightSchedulers() async => [
    for (final MapEntry(:key, :value)
        in _database._nightSchedulerSections.entries)
      if (value.isNotEmpty)
        NightScheduler(staffMemberId: key, sectionIds: {...value}),
  ];

  @override
  Stream<void> monthUpdates(DateTime month) {
    return _database._updates.stream.where((date) => _inMonth(date, month));
  }

  @override
  Future<List<DateTime>> monthsAwaitingConfirmation() async {
    return [..._database._awaitingConfirmation]..sort();
  }

  @override
  Future<void> confirmLoadedMonth(
    DateTime month, {
    bool acknowledgeShortfalls = false,
  }) async {
    _database._throwNextFailure(InMemoryStoreCall.confirmLoadedMonth);
    _database.confirmationWrites.add((
      month: month,
      acknowledgeShortfalls: acknowledgeShortfalls,
    ));
    _database._awaitingConfirmation.remove(month);
    _database._monthStatus[month] = MonthStatus.released;
  }

  @override
  Future<void> setLastDay(SetLastDay action) async {
    _database.lastDayWrites.add(action);
  }

  @override
  Future<void> reactivate(Reactivate action) async {
    _database.reactivationWrites.add(action);
  }

  @override
  Future<void> changeSection(ChangeSection action) async {
    _database.sectionWrites.add(action);
  }

  @override
  Future<void> changeJobRole(ChangeJobRole action) async {
    _database.jobRoleWrites.add(action);
  }

  @override
  Future<List<DatedJobRole>> jobRoles(String staffMemberId) async =>
      List.unmodifiable(_database._seededJobRoles[staffMemberId] ?? const []);

  @override
  Future<List<StaffChange>> staffChanges() async =>
      List.unmodifiable(_database._seededStaffChanges ?? const []);

  @override
  Future<void> markChangesAnnounced(
    Set<String> changeIds,
    Set<String> draftOpenedStaffMemberIds,
  ) async {
    _database._throwNextFailure(InMemoryStoreCall.markChangesAnnounced);
    _database.announcementWrites.add((
      changeIds: Set.of(changeIds),
      draftOpenedStaffMemberIds: Set.of(draftOpenedStaffMemberIds),
    ));
    final answer = _database._settlementsAfterNextAnnouncement;
    if (answer != null) {
      for (final (index, change) in _database._changes.indexed) {
        final settlement = answer[change.id];
        if (settlement == null) continue;
        _database._changes[index] = ScheduleChange(
          id: change.id,
          staffMemberId: change.staffMemberId,
          date: change.date,
          oldShiftCode: change.oldShiftCode,
          newShiftCode: change.newShiftCode,
          changedBy: change.changedBy,
          changedByName: change.changedByName,
          changedAt: change.changedAt,
          announced: settlement.announced,
          moot: settlement.moot,
          reach: settlement.reach,
        );
      }
      _database._settlementsAfterNextAnnouncement = null;
    }
  }

  @override
  Future<MonthStatus> monthStatus(DateTime month) async {
    return await _canSee(month)
        ? _database._monthStatus[month] ?? MonthStatus.notStarted
        : MonthStatus.notStarted;
  }

  /// Tests seed the months that this actor cannot read.
  Future<bool> _canSee(DateTime month) async =>
      !(_database._hiddenMonthsByActor[_actingAs] ?? const <DateTime>{})
          .contains(DateTime(month.year, month.month));

  @override
  Future<void> startMonth(
    DateTime month,
    List<ScheduleCell> cells, {
    DateTime? sourceMonth,
  }) async {
    _database._throwNextFailure(InMemoryStoreCall.startMonth);
    _database._monthStatus[month] = MonthStatus.unpublished;
    for (final cell in cells) {
      _database._cells[_cellKey(cell.staffMemberId, cell.date)] = cell;
    }
    _database._updates.add(month);
  }

  @override
  Future<void> releaseMonth(
    DateTime month, {
    bool acknowledgeShortfalls = false,
  }) async {
    _database._throwNextFailure(InMemoryStoreCall.releaseMonth);
    _database.releaseWrites.add((
      month: month,
      acknowledgeShortfalls: acknowledgeShortfalls,
    ));
    _database._monthStatus[month] = MonthStatus.released;
    _database._updates.add(month);
  }
}
