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
    this.editors,
    Map<String, Grants> grants = const {},
    this.maintainerId,
    Map<String, String> names = const {},
    this.managerEmail = 'manager@example.test',
    Set<DateTime> releasedMonths = const {},
    DateTime Function()? clock,
  }) : _monthStatus = {
         for (final month in releasedMonths)
           DateTime(month.year, month.month): MonthStatus.released,
       },
       _sections = List.unmodifiable(sections),
       _legacyEveryoneEdits = editors == null && grants.isEmpty,
       _grants = {
         for (final entry in grants.entries) entry.key: entry.value,
         for (final id in editors ?? const <String>{})
           id: (grants[id] ?? Grants()).copyWith(manager: true),
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
      if (row.cellNumber case final cellNumber?) {
        _cellNumbers[row.staffMemberId] = cellNumber;
      }
      _assignments.add(
        _Assignment(row.staffMemberId, row.sectionId, _assignments.length),
      );
    }
  }

  final List<ScheduleSection> _sections;

  /// Legacy test shortcut: these people receive a Manager grant.
  final Set<String>? editors;
  final String? maintainerId;
  final bool _legacyEveryoneEdits;
  final Map<String, Grants> _grants;
  final String managerEmail;

  /// Display names of everyone, including people not on a Schedule row such
  /// as the Manager.
  final Map<String, String> _names;
  final Map<String, String> _cellNumbers = {};
  final Set<String> _pushSubscriptions = {};
  final DateTime Function() _clock;

  /// Dated Section placements. A new placement goes to the bottom of its
  /// Section.
  final List<_Assignment> _assignments = [];
  final Map<String, DateTime> _lastDays = {};
  final Map<String, List<DatedJobRole>> _jobRoles = {};
  final Map<String, ScheduleCell> _cells = {};
  final List<ScheduleChange> _changes = [];
  final List<ShortShift> _shortShifts = [];
  ({int posted, int floorCritical})? _nextPostOpenShiftsAnswer;

  /// Supplies SQL's result for the next Open shift posting call.
  void seedNextPostOpenShifts({required int posted, int floorCritical = 0}) {
    _nextPostOpenShiftsAnswer = (
      posted: posted,
      floorCritical: floorCritical,
    );
  }
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
    _staffingAfterNextCellWrite[DateTime(month.year, month.month)] =
        List.of(answer);
  }

  bool hasStaffingForMonth(DateTime month) =>
      _staffingAnswers.containsKey(DateTime(month.year, month.month));
  final List<LegendCode> _shiftCodes = [...shiftLegend];
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
  bool _openShiftApprovalDefault = true;
  final Map<String, bool> _openShiftApprovalOverrides = {};
  final List<StaffChange> _staffChanges = [];
  final List<RequestOff> _requestsOff = [];
  final List<RequestOff> _pendingRequestsOff = [];
  final Map<String, int> _unreadRequestOffNotices = {};
  final StreamController<DateTime> _updates = StreamController.broadcast();
  final List<DateTime> _awaitingConfirmation = [];
  final Map<DateTime, MonthStatus> _monthStatus;
  final Map<InMemoryStoreCall, Object> _nextFailures = {};

  /// Makes the next matching store call fail, then resumes normal behavior.
  void failNext(InMemoryStoreCall call, Object error) {
    _nextFailures[call] = error;
  }

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

  /// Supplies Open shifts created by SQL in a test scenario.
  void seedShortShift(ShortShift shift) => _shortShifts.add(shift);

  void _throwNextFailure(InMemoryStoreCall call) {
    final error = _nextFailures.remove(call);
    if (error != null) throw error;
  }

  /// Moves a Staff member to [sectionId] from the first day of [from]'s month,
  /// without logging it, to set up a test.
  void moveToSection(
    String staffMemberId,
    String sectionId, {
    required DateTime from,
  }) {
    final start = DateTime(from.year, from.month);
    _openAssignment(staffMemberId)?.through = start.subtract(
      const Duration(days: 1),
    );
    _assignments.add(
      _Assignment(staffMemberId, sectionId, _assignments.length, from: start),
    );
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
    grants: _lastDays.containsKey(actor)
        ? Grants()
        : _grants[actor] ??
              (_legacyEveryoneEdits ? Grants(manager: true) : Grants()),
    maintainer: actor == maintainerId,
    ownStaffMemberId: actor == maintainerId || !_isActive(actor) ? null : actor,
  );

  bool _isActive(String staffMemberId) =>
      _names.containsKey(staffMemberId) &&
      !_lastDays.containsKey(staffMemberId);

  _Assignment? _openAssignment(String staffMemberId) => _assignments
      .where(
        (assignment) =>
            assignment.staffMemberId == staffMemberId &&
            assignment.through == null,
      )
      .firstOrNull;

  String _sectionName(String sectionId) =>
      _sections.firstWhere((section) => section.id == sectionId).name;
}

final class _Assignment {
  _Assignment(this.staffMemberId, this.sectionId, this.order, {this.from});

  final String staffMemberId;
  final String sectionId;
  final int order;

  /// Null for placements made before the test began.
  final DateTime? from;
  DateTime? through;

  bool overlaps(DateTime month) {
    final start = from;
    final end = through;
    return (start == null ||
            start.isBefore(DateTime(month.year, month.month + 1))) &&
        (end == null || !end.isBefore(month));
  }
}

final class _InMemoryScheduleStore implements ScheduleStore {
  _InMemoryScheduleStore(this._database, this._actingAs);

  final InMemoryScheduleDatabase _database;
  final String _actingAs;
  Access get _access => _database.accessFor(_actingAs);

  @override
  Future<Access> currentAccess() async => _access;

  void _requireStaffManagement() {
    if (!_database.accessFor(_actingAs).canManageStaff) {
      throw const ScheduleEditRefused();
    }
  }

  @override
  Future<List<LegendCode>> shiftCodes() async {
    _database._throwNextFailure(InMemoryStoreCall.shiftCodes);
    return List.unmodifiable(
      _database._shiftCodes.where((code) => code.active),
    );
  }

  @override
  Future<void> saveShiftCode(LegendCode code, {String? originalCode}) async {
    if (!_access.canRunSchedule) throw const ScheduleEditRefused();
    final value = code.code.trim().toUpperCase();
    if (value.isEmpty || (code.startTime == null) != (code.endTime == null)) {
      throw ArgumentError('Invalid Shift code or hours');
    }
    if (originalCode != null && originalCode != value) {
      if (_database._shiftCodes.any((item) => item.code == value)) {
        throw StateError('That Shift code already exists');
      }
      final originalIndex = _database._shiftCodes.indexWhere(
        (item) => item.code == originalCode,
      );
      if (originalIndex < 0) throw StateError('Shift code not found');
      if (_codeInUse(originalCode)) {
        final old = _database._shiftCodes[originalIndex];
        _database._shiftCodes[originalIndex] = LegendCode(
          old.code,
          hours: old.hours,
          meaning: old.meaning,
          isWorking: old.isWorking,
          startTime: old.startTime,
          endTime: old.endTime,
          coverageWindow: old.coverageWindow,
          active: false,
        );
      } else {
        _database._shiftCodes.removeAt(originalIndex);
      }
    }
    final index = _database._shiftCodes.indexWhere(
      (item) => item.code == value,
    );
    final updated = LegendCode(
      value,
      hours: shiftCodeHours(code.startTime, code.endTime) ?? code.hours,
      meaning: code.meaning,
      isWorking: code.isWorking,
      startTime: code.startTime,
      endTime: code.endTime,
      coverageWindow:
          code.coverageWindow ??
          coverageWindowForHours(code.startTime, code.endTime),
    );
    if (index < 0) {
      _database._shiftCodes.add(updated);
    } else {
      _database._shiftCodes[index] = updated;
    }
  }

  @override
  Future<void> deleteShiftCode(String code) async {
    if (!_access.canRunSchedule) throw const ScheduleEditRefused();
    final key = code.trim().toUpperCase();
    if (_codeInUse(key)) {
      throw StateError('A Shift code in use cannot be deleted');
    }
    _database._shiftCodes.removeWhere((item) => item.code == key);
  }

  bool _codeInUse(String key) =>
      _database._cells.values.any(
        (cell) => cell.shiftCode.trim().toUpperCase() == key,
      ) ||
      _database._changes.any(
        (change) =>
            change.oldShiftCode.trim().toUpperCase() == key ||
            change.newShiftCode.trim().toUpperCase() == key,
      ) ||
      _database._shortShifts.any(
        (shift) => shift.shiftCode.trim().toUpperCase() == key,
      );

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
    final sectionOrder = [
      for (final section in _database._sections) section.id,
    ];
    // Each person's latest placement in the month decides their row.
    final latest = <String, _Assignment>{};
    for (final assignment in _database._assignments) {
      if (!assignment.overlaps(month)) continue;
      final current = latest[assignment.staffMemberId];
      if (current == null ||
          (assignment.from ?? DateTime(0)).isAfter(
            current.from ?? DateTime(0),
          )) {
        latest[assignment.staffMemberId] = assignment;
      }
    }
    final ordered = latest.values.toList()
      ..sort((left, right) {
        final bySection = sectionOrder
            .indexOf(left.sectionId)
            .compareTo(sectionOrder.indexOf(right.sectionId));
        return bySection != 0 ? bySection : left.order.compareTo(right.order);
      });
    return [
      for (final assignment in ordered)
        ScheduleRow(
          staffMemberId: assignment.staffMemberId,
          displayName: _database._names[assignment.staffMemberId]!,
          sectionId: assignment.sectionId,
          cellNumber: _database._isActive(assignment.staffMemberId)
              ? _database._cellNumbers[assignment.staffMemberId]
              : null,
          hasPushSubscription: _database._pushSubscriptions.contains(
            assignment.staffMemberId,
          ),
          lastDay: assignment.through,
        ),
    ];
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
    final openShifts = _InMemoryOpenShiftStore(_database, _actingAs);
    final result = <ShortShift>[];
    for (final short in _database._shortShifts.where(
      (item) => _inMonth(item.date, month),
    )) {
      final role =
          short.jobRole ??
          openShifts._originalRole(short.staffMemberId, short.date);
      final pool = role == null
          ? null
          : (await openShifts.coveragePoolsOn(
              short.date,
            )).where((config) => config.jobRoles.contains(role)).firstOrNull;
      result.add(
        ShortShift(
          sectionId: short.sectionId,
          date: short.date,
          shiftCode: short.shiftCode,
          staffMemberId: short.staffMemberId,
          jobRole: role,
          coverageWindow: short.coverageWindow,
          coveragePool: pool == null
              ? null
              : CoveragePool(pool.id, pool.name, sortOrder: pool.sortOrder),
        ),
      );
    }
    return result;
  }

  @override
  Future<void> writeCell(ScheduleCell cell) async {
    _database._throwNextFailure(InMemoryStoreCall.writeCell);
    final editable = _access.editableSections;
    if (!editable.contains(cell.sectionId)) {
      throw editable.isEmpty
          ? const ScheduleEditRefused()
          : const ScheduleEditRefused('Only the Manager can edit that Section');
    }
    final row = (await rows(
      DateTime(cell.date.year, cell.date.month),
    )).where((row) => row.staffMemberId == cell.staffMemberId).firstOrNull;
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
    final editable = _access.editableSections;
    for (final cell in [first, second]) {
      if (!editable.contains(cell.sectionId)) throw const ScheduleEditRefused();
      final row = (await rows(
        DateTime(cell.date.year, cell.date.month),
      )).where((row) => row.staffMemberId == cell.staffMemberId).firstOrNull;
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
    if (firstOld != action.expectedFirstCode ||
        secondOld != action.expectedSecondCode) {
      throw StateError('The Schedule changed. Reload and try again.');
    }
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

  void _write(ScheduleCell cell) {
    final code = cell.shiftCode.trim().toUpperCase();
    if (code.isNotEmpty &&
        !_database._shiftCodes.any((entry) => entry.code == code)) {
      _database._shiftCodes.add(LegendCode(code, isWorking: true));
    }
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
    if (sectionIds.isEmpty) {
      throw ArgumentError.value(
        sectionIds,
        'sectionIds',
        'The Night scheduler needs at least one Section',
      );
    }
    _requireStaffManagement();
    // Preserve the old no-grants test default: assigning a Section made that
    // actor a Night scheduler rather than an implicit Manager.
    final existing =
        _database._grants[staffMemberId] ??
        (_database._legacyEveryoneEdits
            ? Grants()
            : _database.accessFor(staffMemberId).grants);
    _database._grants[staffMemberId] = existing.copyWith(
      nightSchedulerSectionIds: sectionIds,
    );
  }

  @override
  Future<void> removeNightScheduler(String staffMemberId) async {
    _requireStaffManagement();
    if (_database._legacyEveryoneEdits) {
      _database._grants.remove(staffMemberId);
      return;
    }
    _database._grants[staffMemberId] = _database
        .accessFor(staffMemberId)
        .grants
        .copyWith(nightSchedulerSectionIds: {});
  }

  @override
  Future<List<NightScheduler>> nightSchedulers() async => [
    for (final MapEntry(:key, :value) in _database._grants.entries)
      if (value.nightSchedulerSectionIds.isNotEmpty)
        NightScheduler(
          staffMemberId: key,
          sectionIds: {...value.nightSchedulerSectionIds},
        ),
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
    if (!_access.canRunSchedule) throw const ScheduleEditRefused();
    if (!_database._awaitingConfirmation.remove(month)) {
      throw StateError('There is no loaded month waiting to be confirmed');
    }
    _database._monthStatus[month] = MonthStatus.released;
    _database._markAnnounced((change) => _inMonth(change.date, month));
  }

  @override
  Future<void> setLastDay(SetLastDay action) async {
    _requireStaffManagement();
    final id = action.staffMemberId;
    final lastDay = action.lastDay;
    if (id == _actingAs) throw StateError("You can't set your own Last day");
    if (!_database._isActive(id)) {
      throw StateError('That person is not on the Staff list');
    }
    _database._lastDays[id] = lastDay;
    _database._grants[id] = Grants();

    // Placements planned to start after the Last day no longer apply.
    _database._assignments.removeWhere(
      (assignment) =>
          assignment.staffMemberId == id &&
          (assignment.from?.isAfter(lastDay) ?? false),
    );
    for (final assignment in _database._assignments) {
      final through = assignment.through;
      if (assignment.staffMemberId == id &&
          (through == null || through.isAfter(lastDay))) {
        assignment.through = lastDay;
      }
    }
    _database._jobRoles[id] = [
      for (final role in _database._jobRoles[id] ?? const <DatedJobRole>[])
        if (!role.from.isAfter(lastDay))
          DatedJobRole(
            jobRole: role.jobRole,
            from: role.from,
            through: role.through == null || role.through!.isAfter(lastDay)
                ? lastDay
                : role.through,
          ),
    ];

    final later =
        _database._cells.values
            .where(
              (cell) =>
                  cell.staffMemberId == id &&
                  cell.date.isAfter(lastDay) &&
                  cell.shiftCode.isNotEmpty,
            )
            .toList()
          ..sort((left, right) => left.date.compareTo(right.date));
    for (final cell in later) {
      _write(
        ScheduleCell(
          staffMemberId: id,
          sectionId: cell.sectionId,
          date: cell.date,
          shiftCode: '',
        ),
      );
      if (isWorkingShift(cell.shiftCode, codes: _database._shiftCodes)) {
        _database._shortShifts.add(
          ShortShift(
            sectionId: cell.sectionId,
            date: cell.date,
            shiftCode: cell.shiftCode,
            staffMemberId: id,
            jobRole: await scheduleRulesInMemory(
              _database,
              actingAs: _actingAs,
            ).jobRoleOn(id, lastDay),
            coverageWindow: _coverageWindowOf(
              cell.shiftCode,
              _database._shiftCodes,
            ),
          ),
        );
      }
    }
    _log(id, StaffChangeKind.lastDay, null, _dateText(lastDay), lastDay);
  }

  @override
  Future<void> reactivate(Reactivate action) async {
    _requireStaffManagement();
    final id = action.staffMemberId;
    final lastDay = _database._lastDays[id];
    if (lastDay == null) {
      throw StateError('That person is already on the Staff list');
    }
    if (!action.firstDay.isAfter(lastDay)) {
      throw StateError('Their first day back must be after their Last day');
    }
    _database._lastDays.remove(id);
    _database._assignments.add(
      _Assignment(
        id,
        action.sectionId,
        _database._assignments.length,
        from: action.firstDay,
      ),
    );
    final roles = _database._jobRoles[id];
    final lastRole = roles?.lastOrNull;
    if (roles != null && lastRole != null) {
      roles.add(
        DatedJobRole(
          jobRole: lastRole.jobRole,
          from: action.firstDay,
          through: null,
        ),
      );
    }
    _log(
      id,
      StaffChangeKind.reactivated,
      null,
      _database._sectionName(action.sectionId),
      action.firstDay,
    );
  }

  @override
  Future<void> changeSection(ChangeSection action) async {
    _requireStaffManagement();
    final id = action.staffMemberId;
    final open = _database._openAssignment(id);
    if (!_database._isActive(id) || open == null) {
      throw StateError('That person is not on the Staff list');
    }
    if (open.sectionId == action.sectionId) {
      throw StateError('They are already in that Section');
    }
    final openFrom = open.from;
    if (openFrom != null && action.from.isBefore(openFrom)) {
      throw StateError(
        'The move must start on or after their current Section did',
      );
    }
    if (openFrom == action.from) {
      _database._assignments.remove(open);
    } else {
      open.through = action.from.subtract(const Duration(days: 1));
    }
    _database._assignments.add(
      _Assignment(
        id,
        action.sectionId,
        _database._assignments.length,
        from: action.from,
      ),
    );
    _log(
      id,
      StaffChangeKind.section,
      _database._sectionName(open.sectionId),
      _database._sectionName(action.sectionId),
      action.from,
    );
  }

  @override
  Future<void> changeJobRole(ChangeJobRole action) async {
    _requireStaffManagement();
    final id = action.staffMemberId;
    if (!_database._isActive(id)) {
      throw StateError('That person is not on the Staff list');
    }
    final roles = _database._jobRoles.putIfAbsent(id, () => []);
    final open = roles.lastOrNull;
    if (open?.jobRole == action.jobRole) {
      throw StateError('They already have that role');
    }
    if (open != null) {
      if (action.from.isBefore(open.from)) {
        throw StateError(
          'The change must start on or after their current role did',
        );
      }
      roles.removeLast();
      if (open.from != action.from) {
        roles.add(
          DatedJobRole(
            jobRole: open.jobRole,
            from: open.from,
            through: action.from.subtract(const Duration(days: 1)),
          ),
        );
      }
    }
    roles.add(
      DatedJobRole(jobRole: action.jobRole, from: action.from, through: null),
    );
    _log(
      id,
      StaffChangeKind.jobRole,
      open?.jobRole.label,
      action.jobRole.label,
      action.from,
    );
  }

  @override
  Future<List<DatedJobRole>> jobRoles(String staffMemberId) async =>
      List.unmodifiable(_database._jobRoles[staffMemberId] ?? const []);

  @override
  Future<List<StaffChange>> staffChanges() async =>
      List.unmodifiable(_database._staffChanges);

  void _log(
    String staffMemberId,
    StaffChangeKind kind,
    String? oldValue,
    String? newValue,
    DateTime effectiveFrom,
  ) {
    _database._staffChanges.add(
      StaffChange(
        staffMemberId: staffMemberId,
        kind: kind,
        oldValue: oldValue,
        newValue: newValue,
        effectiveFrom: effectiveFrom,
        changedBy: _actingAs,
        changedAt: _database._clock(),
      ),
    );
  }

  @override
  Future<void> markChangesAnnounced(
    Set<String> changeIds,
    Set<String> draftOpenedStaffMemberIds,
  ) async {
    _database._throwNextFailure(InMemoryStoreCall.markChangesAnnounced);
    final editable = _access.editableSections;
    if (editable.isEmpty) throw const ScheduleEditRefused();
    final months = {
      for (final change in _database._changes)
        if (changeIds.contains(change.id))
          DateTime(change.date.year, change.date.month),
    };
    final sectionOf = {
      for (final month in months)
        for (final row in await rows(month))
          (row.staffMemberId, month): row.sectionId,
    };
    final movedByCell = <String, bool>{};
    for (final change in _database._changes) {
      if (change.announced || change.moot) continue;
      final key = _cellKey(change.staffMemberId, change.date);
      movedByCell.putIfAbsent(
        key,
        () => (_database._cells[key]?.shiftCode ?? '') != change.oldShiftCode,
      );
    }
    final unselectedPendingCells = {
      for (final change in _database._changes)
        if (!change.announced && !change.moot && !changeIds.contains(change.id))
          _cellKey(change.staffMemberId, change.date),
    };
    for (final (index, change) in _database._changes.indexed) {
      final key = _cellKey(change.staffMemberId, change.date);
      if (!changeIds.contains(change.id) ||
          change.announced ||
          change.moot ||
          unselectedPendingCells.contains(key) ||
          !editable.contains(
            sectionOf[(
                  change.staffMemberId,
                  DateTime(change.date.year, change.date.month),
                )] ??
                '',
          )) {
        continue;
      }
      final moved = movedByCell[key]!;
      _database._changes[index] = ScheduleChange(
        id: change.id,
        staffMemberId: change.staffMemberId,
        date: change.date,
        oldShiftCode: change.oldShiftCode,
        newShiftCode: change.newShiftCode,
        changedBy: change.changedBy,
        changedByName: change.changedByName,
        changedAt: change.changedAt,
        announced: moved,
        moot: !moved,
        reach: !moved
            ? null
            : _database._pushSubscriptions.contains(change.staffMemberId)
            ? 'notified'
            : draftOpenedStaffMemberIds.contains(change.staffMemberId)
            ? 'draft_opened'
            : 'nobody',
      );
    }
  }

  @override
  Future<MonthStatus> monthStatus(DateTime month) async {
    return await _canSee(month)
        ? _database._monthStatus[month] ?? MonthStatus.notStarted
        : MonthStatus.notStarted;
  }

  /// Only schedulers see a month before it is released.
  Future<bool> _canSee(DateTime month) async =>
      _database._monthStatus[month] != MonthStatus.unpublished ||
      _database.accessFor(_actingAs).canReadUnreleased;

  @override
  Future<void> startMonth(DateTime month, List<ScheduleCell> cells) async {
    _database._throwNextFailure(InMemoryStoreCall.startMonth);
    if (!_access.canRunSchedule) throw const ScheduleEditRefused();
    if (_database._monthStatus.containsKey(month)) {
      throw const MonthAlreadyStarted();
    }
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
    if (!_access.canRunSchedule) throw const ScheduleEditRefused();
    if (_database._monthStatus[month] != MonthStatus.unpublished ||
        _database._awaitingConfirmation.contains(month)) {
      throw StateError('There is no unpublished month to release');
    }
    _database._monthStatus[month] = MonthStatus.released;
    _database._markAnnounced((change) => _inMonth(change.date, month));
    _database._updates.add(month);
  }
}
