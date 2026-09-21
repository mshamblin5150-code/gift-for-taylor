// Public constructor names stay distinct from the private dependencies.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:schedule_rules/schedule_rules.dart';

typedef MonthSessionTimerFactory = Timer Function(
  Duration delay,
  void Function() callback,
);

typedef UnreachedThisWeek = ({int count, DateTime month});

/// One immutable reading of a month's Schedule and its related state.
@immutable
final class MonthSessionState {
  const MonthSessionState({
    required this.today,
    this.grid,
    this.coverage,
    this.announcement,
    this.unreached,
    this.previousMonthStarted = false,
    this.shiftCodes = const [],
    this.staffing = const [],
    this.loadError,
    this.savingDrop = false,
  });

  final MonthGrid? grid;
  final CoverageReading? coverage;
  final ChangeAnnouncement? announcement;
  final UnreachedThisWeek? unreached;
  final bool previousMonthStarted;
  final List<LegendCode> shiftCodes;
  final List<SectionStaffing> staffing;
  final Object? loadError;
  final DateTime today;
  final bool savingDrop;

  @override
  bool operator ==(Object other) =>
      other is MonthSessionState &&
      listEquals(_gridValues(other.grid), _gridValues(grid)) &&
      (other.coverage == null) == (coverage == null) &&
      listEquals(
        _announcementValues(other.announcement),
        _announcementValues(announcement),
      ) &&
      other.unreached == unreached &&
      other.previousMonthStarted == previousMonthStarted &&
      listEquals(
        other.shiftCodes.map(_codeValue).toList(),
        shiftCodes.map(_codeValue).toList(),
      ) &&
      listEquals(
        other.staffing.map(_staffingValue).toList(),
        staffing.map(_staffingValue).toList(),
      ) &&
      other.loadError == loadError &&
      other.today == today &&
      other.savingDrop == savingDrop;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(_gridValues(grid)),
    coverage != null,
    Object.hashAll(_announcementValues(announcement)),
    unreached,
    previousMonthStarted,
    Object.hashAll(shiftCodes.map(_codeValue)),
    Object.hashAll(staffing.map(_staffingValue)),
    loadError,
    today,
    savingDrop,
  );
}

Object _rowValue(ScheduleRow row) => (
  row.staffMemberId,
  row.displayName,
  row.sectionId,
  row.cellNumber,
  row.lastDay,
  row.hasPushSubscription,
);

List<Object?> _gridValues(MonthGrid? grid) {
  if (grid == null) return const [null];
  final days = grid.days;
  return [
    grid.month,
    grid.status,
    grid.awaitingConfirmation,
    grid.sections.length,
    for (final section in grid.sections) (section.id, section.name),
    grid.rows.length,
    for (final row in grid.rows) _rowValue(row),
    grid.shortShifts.length,
    for (final shift in grid.shortShifts)
      (
        shift.sectionId,
        shift.date,
        shift.shiftCode,
        shift.staffMemberId,
        shift.jobRole,
        shift.coverageWindow,
        shift.coveragePool,
      ),
    for (final row in grid.rows)
      for (final day in days)
        (
          grid.shiftCodeFor(row.staffMemberId, day),
          grid.isUnannounced(row.staffMemberId, day),
          grid.publishedCodeFor(row.staffMemberId, day),
          grid.isChanged(row.staffMemberId, day),
        ),
  ];
}

List<Object?> _announcementValues(ChangeAnnouncement? announcement) {
  if (announcement == null) return const [null];
  return [
    announcement.month,
    announcement.hasPendingChanges,
    announcement.people.length,
    for (final person in announcement.people) ...[
      _rowValue(person.row),
      person.changedDays.length,
      for (final day in person.changedDays)
        (day.date, day.oldShiftCode, day.newShiftCode),
    ],
  ];
}

Object _codeValue(LegendCode code) => (
  code.code,
  code.hours,
  code.meaning,
  code.isWorking,
  code.startTime,
  code.endTime,
  code.coverageWindow,
  code.active,
);

Object _staffingValue(SectionStaffing item) => (
  item.pool,
  item.coverageWindow,
  item.date,
  item.minimum,
  item.rnFloor,
  item.workingCount,
  item.rnCount,
  item.openCount,
  item.rnOpenCount,
  item.shortCount,
  item.rnShortCount,
  item.unpostedCount,
  item.weekdayMinimum,
  item.dateMinimum,
  item.floorRole,
);

typedef _MonthRead = ({
  MonthGrid grid,
  bool previousMonthStarted,
  ChangeAnnouncement? announcement,
  List<LegendCode> codes,
  List<SectionStaffing> staffing,
  UnreachedThisWeek? unreached,
});

/// Data and liveness for exactly one calendar month.
final class MonthSession extends ChangeNotifier {
  MonthSession({
    required ScheduleRules rules,
    required Access access,
    required DateTime month,
    OpenShiftRules? openShiftRules,
    DateTime Function()? now,
    MonthSessionTimerFactory? timerFactory,
  }) : _rules = rules,
       _access = access,
       _openShiftRules = openShiftRules,
       month = DateTime(month.year, month.month),
       _now = now ?? DateTime.now,
       _timerFactory = timerFactory ?? Timer.new {
    _state = MonthSessionState(today: _dateOnly(_now()));
    _updates = _rules.monthUpdates(this.month).listen((_) => refresh());
    if (openShiftRules != null) {
      _openShiftUpdates = openShiftRules.updates().listen((_) => refresh());
    }
    _scheduleMidnight();
  }

  final ScheduleRules _rules;
  final Access _access;
  final OpenShiftRules? _openShiftRules;
  final DateTime month;
  final DateTime Function() _now;
  final MonthSessionTimerFactory _timerFactory;
  late MonthSessionState _state;
  MonthSessionState get state => _state;
  StreamSubscription<void>? _updates;
  StreamSubscription<void>? _openShiftUpdates;
  Timer? _midnightTimer;
  bool _disposed = false;

  void _replace(MonthSessionState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  void _scheduleMidnight() {
    _midnightTimer?.cancel();
    final now = _now();
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = _timerFactory(nextDay.difference(now), () {
      if (_disposed) return;
      _replace(_withToday(_dateOnly(_now())));
      refresh();
      _scheduleMidnight();
    });
  }

  MonthSessionState _withToday(DateTime today) => MonthSessionState(
    today: today,
    grid: _state.grid,
    coverage: _state.coverage,
    announcement: _state.announcement,
    unreached: _state.unreached,
    previousMonthStarted: _state.previousMonthStarted,
    shiftCodes: _state.shiftCodes,
    staffing: _state.staffing,
    loadError: _state.loadError,
    savingDrop: _state.savingDrop,
  );

  Future<void> load() => _readMonth(initial: true);
  Future<void> retry() => load();
  Future<void> refresh() => _readMonth(initial: false);

  Future<void> _readMonth({required bool initial}) async {
    if (_disposed) return;
    try {
      final read = await _read();
      if (_disposed) return;
      _replace(
        MonthSessionState(
          today: _state.today,
          grid: read.grid,
          coverage: CoverageReading(read.grid, read.staffing),
          announcement: read.announcement,
          unreached: read.unreached,
          previousMonthStarted: read.previousMonthStarted,
          shiftCodes: List.unmodifiable(read.codes),
          staffing: List.unmodifiable(read.staffing),
          loadError: null,
        ),
      );
    } catch (error) {
      // A failed first load sets loadError, while a failed reload keeps the last state.
      if (initial && !_disposed) {
        _replace(MonthSessionState(today: _state.today, loadError: error));
      }
    }
  }

  /// The grid, the unannounced tray for an editor, active Shift codes, and
  /// Section staffing.
  ///
  /// The grid and the tray are the Schedule and the promise to announce its
  /// changes, so either failing stops the month from opening. Both read the
  /// same Schedule the grid does, so neither can fail on its own.
  ///
  /// The Shift code legend and Section staffing are adjuncts: each is a
  /// separate backend call a Schedule can be read without, and each has an
  /// honest empty state — no legend to pick from, no minimums to fall short
  /// of. An older database missing either must not take the month down with
  /// it. The tray is deliberately not among them: no tray reads as "everyone
  /// has been told", which is a claim, not an absence.
  Future<_MonthRead> _read() async {
    // Started together so nothing here costs an extra round trip.
    final gridRead = _rules.monthGrid(month);
    final announcementRead = _access.editableSections.isEmpty
        ? Future<ChangeAnnouncement?>.value()
        : _rules.changeAnnouncement(month);
    final codesRead = _adjunct(_rules.shiftCodes, const <LegendCode>[]);
    final staffingRead = _adjunct(
      () async =>
          await _openShiftRules?.staffingForMonth(month) ??
          const <SectionStaffing>[],
      const <SectionStaffing>[],
    );
    final unreachedRead = _access.canRunSchedule
        ? _readUnreachedThisWeek()
        : Future<UnreachedThisWeek?>.value();
    // Waits for both required reads whichever fails, so a failure on one side
    // leaves no unobserved error on the other, and reports the error itself
    // rather than a wrapper.
    final required = await Future.wait<Object?>([gridRead, announcementRead]);
    final grid = required[0]! as MonthGrid;
    final previousMonthStarted =
        _access.canRunSchedule && grid.status == MonthStatus.notStarted
        ? (await _rules.monthGrid(DateTime(month.year, month.month - 1)))
                  .status !=
              MonthStatus.notStarted
        : false;
    return (
      grid: grid,
      previousMonthStarted: previousMonthStarted,
      announcement: required[1] as ChangeAnnouncement?,
      codes: await codesRead,
      staffing: await staffingRead,
      unreached: await unreachedRead,
    );
  }

  Future<UnreachedThisWeek?> _readUnreachedThisWeek() async {
    final today = _state.today;
    final end = today.add(Duration(days: 7 - today.weekday));
    final firstMonth = DateTime(today.year, today.month);
    final lastMonth = DateTime(end.year, end.month);
    final logs = await Future.wait([
      _rules.changeLogView(firstMonth, unreachedOnly: true),
      if (lastMonth != firstMonth)
        _rules.changeLogView(lastMonth, unreachedOnly: true),
    ]);
    final changes = logs.expand((log) => log);
    final upcoming = changes.where((change) {
      final date = _dateOnly(change.date);
      return !date.isBefore(today) && !date.isAfter(end);
    }).toList();
    if (upcoming.isEmpty) return null;
    return (
      count: upcoming.map((change) => change.staffMemberId).toSet().length,
      month: firstMonth,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _updates?.cancel();
    _openShiftUpdates?.cancel();
    _midnightTimer?.cancel();
    super.dispose();
  }
}

DateTime _dateOnly(DateTime day) => DateTime(day.year, day.month, day.day);

/// Reads data the Schedule is better with but still readable without, falling
/// back to [orElse] rather than failing the whole month.
///
/// Only for reads whose [orElse] is an honest empty state. Where absence would
/// instead assert something — that there is nothing left to announce, say —
/// the read belongs in the month's required set.
Future<T> _adjunct<T>(Future<T> Function() read, T orElse) async {
  try {
    return await read();
  } catch (_) {
    return orElse;
  }
}
