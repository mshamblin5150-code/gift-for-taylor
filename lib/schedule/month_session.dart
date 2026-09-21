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

sealed class EditableCellOutcome {
  const EditableCellOutcome();
}

final class Editable extends EditableCellOutcome {
  const Editable(this.currentCode, this.publishedCode);
  final String currentCode;
  final String? publishedCode;
}

final class NotEditable extends EditableCellOutcome {
  const NotEditable();
}

final class MonthNotStarted extends EditableCellOutcome {
  const MonthNotStarted();
}

sealed class CellEdit {
  const CellEdit();
}

final class SaveCode extends CellEdit {
  const SaveCode(this.shiftCode);
  final String shiftCode;
}

final class UndoToPublished extends CellEdit {
  const UndoToPublished();
}

sealed class EditOutcome {
  const EditOutcome();
}

final class EditSaved extends EditOutcome {
  const EditSaved();
}

final class EditFailed extends EditOutcome {
  const EditFailed();
}

sealed class AnnounceOutcome {
  const AnnounceOutcome();
}

final class Announced extends AnnounceOutcome {
  const Announced();
}

final class AnnounceFailed extends AnnounceOutcome {
  const AnnounceFailed();
}

sealed class StartMonthOutcome {
  const StartMonthOutcome();
}

final class Started extends StartMonthOutcome {
  const Started();
}

final class AlreadyStarted extends StartMonthOutcome {
  const AlreadyStarted();
}

final class NoPreviousMonth extends StartMonthOutcome {
  const NoPreviousMonth();
}

final class StartMonthFailed extends StartMonthOutcome {
  const StartMonthFailed();
}

final class CellLocation {
  const CellLocation(this.row, this.date);
  final ScheduleRow row;
  final DateTime date;
}

final class DropUndo {
  const DropUndo._(this._pair);
  final SaveCellPair _pair;
}

sealed class DropOutcome {
  const DropOutcome();
}

final class Swapped extends DropOutcome {
  const Swapped(this.undo);
  final DropUndo undo;
}

final class Copied extends DropOutcome {
  const Copied(this.undo);
  final DropUndo undo;
}

final class NothingToSwap extends DropOutcome {
  const NothingToSwap();
}

final class DropIgnored extends DropOutcome {
  const DropIgnored();
}

final class DropFailed extends DropOutcome {
  const DropFailed();
}

sealed class UndoDropOutcome {
  const UndoDropOutcome();
}

final class DropUndone extends UndoDropOutcome {
  const DropUndone();
}

final class UndoDropFailed extends UndoDropOutcome {
  const UndoDropFailed();
}

enum MonthReleaseKind { loadedMonth, builtMonth }

final class MonthReleaseReview {
  const MonthReleaseReview({
    required this.kind,
    required this.shortfallDays,
    required this.openShiftDays,
  });
  final MonthReleaseKind kind;
  final List<DateTime> shortfallDays;
  final List<DateTime> openShiftDays;
}

sealed class ReviewMonthReleaseOutcome {
  const ReviewMonthReleaseOutcome();
}

final class ReleaseReady extends ReviewMonthReleaseOutcome {
  const ReleaseReady(this.review);
  final MonthReleaseReview review;
}

final class ReviewMonthReleaseFailed extends ReviewMonthReleaseOutcome {
  const ReviewMonthReleaseFailed();
}

sealed class ReleaseMonthOutcome {
  const ReleaseMonthOutcome();
}

final class Released extends ReleaseMonthOutcome {
  const Released();
}

final class ReleaseMonthFailed extends ReleaseMonthOutcome {
  const ReleaseMonthFailed();
}

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
    VoidCallback? onAccessRejected,
  }) : _rules = rules,
       _access = access,
       _openShiftRules = openShiftRules,
       month = DateTime(month.year, month.month),
       _now = now ?? DateTime.now,
       _timerFactory = timerFactory ?? Timer.new,
       _onAccessRejected = onAccessRejected {
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
  final VoidCallback? _onAccessRejected;
  late MonthSessionState _state;
  MonthSessionState get state => _state;
  StreamSubscription<void>? _updates;
  StreamSubscription<void>? _openShiftUpdates;
  Timer? _midnightTimer;
  bool _disposed = false;

  void _rejected(Object error) {
    if (error is AccessRejected) _onAccessRejected?.call();
  }

  EditableCellOutcome editableCell(ScheduleRow row, DateTime date) {
    final grid = state.grid;
    if (!_access.canEditSection(row.sectionId) ||
        grid == null ||
        !grid.isOnSchedule(row, date)) {
      return const NotEditable();
    }
    if (grid.status == MonthStatus.notStarted) return const MonthNotStarted();
    return Editable(
      grid.shiftCodeFor(row.staffMemberId, date) ?? '',
      grid.isUnannounced(row.staffMemberId, date)
          ? grid.publishedCodeFor(row.staffMemberId, date)
          : null,
    );
  }

  Future<EditOutcome> edit(
    ScheduleRow row,
    DateTime date,
    CellEdit edit,
  ) async {
    try {
      switch (edit) {
        case SaveCode(:final shiftCode):
          await _rules.saveCell(
            SaveCell(
              staffMemberId: row.staffMemberId,
              sectionId: row.sectionId,
              date: date,
              shiftCode: shiftCode,
            ),
          );
        case UndoToPublished():
          await _rules.undoCell(
            UndoCell(
              staffMemberId: row.staffMemberId,
              sectionId: row.sectionId,
              date: date,
            ),
          );
      }
      await refresh();
      return const EditSaved();
    } catch (error) {
      _rejected(error);
      return const EditFailed();
    }
  }

  Future<AnnounceOutcome> announce(
    ChangeAnnouncement announcement,
    Set<String> draftOpenedStaffMemberIds,
  ) async {
    try {
      await _rules.markAnnounced(
        announcement,
        draftOpenedStaffMemberIds: draftOpenedStaffMemberIds,
      );
      await refresh();
      return const Announced();
    } catch (error) {
      _rejected(error);
      return const AnnounceFailed();
    }
  }

  Future<StartMonthOutcome> startMonth({required bool empty}) async {
    try {
      if (empty) {
        await _rules.startEmptyMonth(month);
      } else {
        await _rules.startNextMonth(DateTime(month.year, month.month - 1));
      }
      await refresh();
      return const Started();
    } on MonthAlreadyStarted {
      await refresh();
      return const AlreadyStarted();
    } on PreviousMonthNotStarted {
      return const NoPreviousMonth();
    } catch (error) {
      _rejected(error);
      return const StartMonthFailed();
    }
  }

  Future<DropOutcome> drop(
    CellLocation source,
    CellLocation target, {
    required bool copy,
  }) async {
    final grid = state.grid;
    if (state.savingDrop ||
        grid == null ||
        grid.status == MonthStatus.notStarted ||
        !_access.canEditSection(source.row.sectionId) ||
        !_access.canEditSection(target.row.sectionId) ||
        !grid.isOnSchedule(source.row, source.date) ||
        !grid.isOnSchedule(target.row, target.date)) {
      return const DropIgnored();
    }
    final sourceCode =
        grid.shiftCodeFor(source.row.staffMemberId, source.date) ?? '';
    final targetCode =
        grid.shiftCodeFor(target.row.staffMemberId, target.date) ?? '';
    if (sourceCode.isEmpty || sourceCode == targetCode) {
      return const DropIgnored();
    }
    if (!copy && targetCode.isEmpty) return const NothingToSwap();
    SaveCell cell(CellLocation location, String code) => SaveCell(
      staffMemberId: location.row.staffMemberId,
      sectionId: location.row.sectionId,
      date: location.date,
      shiftCode: code,
    );
    final pair = SaveCellPair(
      first: cell(source, copy ? sourceCode : targetCode),
      second: cell(target, sourceCode),
      expectedFirstCode: sourceCode,
      expectedSecondCode: targetCode,
    );
    final undo = DropUndo._(
      SaveCellPair(
        first: cell(source, sourceCode),
        second: cell(target, targetCode),
        expectedFirstCode: pair.first.shiftCode,
        expectedSecondCode: pair.second.shiftCode,
      ),
    );
    _replace(_withState(savingDrop: true));
    try {
      await _rules.saveCellPair(pair);
      await refresh();
      return copy ? Copied(undo) : Swapped(undo);
    } catch (error) {
      _rejected(error);
      await refresh();
      return const DropFailed();
    } finally {
      _replace(_withState(savingDrop: false));
    }
  }

  Future<UndoDropOutcome> undoDrop(DropUndo token) async {
    if (state.savingDrop) return const UndoDropFailed();
    _replace(_withState(savingDrop: true));
    try {
      await _rules.saveCellPair(token._pair);
      await refresh();
      return const DropUndone();
    } catch (error) {
      _rejected(error);
      await refresh();
      return const UndoDropFailed();
    } finally {
      _replace(_withState(savingDrop: false));
    }
  }

  Future<ReviewMonthReleaseOutcome> reviewMonthRelease() async {
    final grid = state.grid;
    if (grid == null) return const ReviewMonthReleaseFailed();
    try {
      final staffing =
          await _openShiftRules?.staffingForMonth(month) ?? state.staffing;
      final reading = CoverageReading(grid, staffing);
      return ReleaseReady(
        MonthReleaseReview(
          kind: grid.awaitingConfirmation
              ? MonthReleaseKind.loadedMonth
              : MonthReleaseKind.builtMonth,
          shortfallDays: reading.shortfallDays,
          openShiftDays: reading.openShiftDays,
        ),
      );
    } catch (_) {
      return const ReviewMonthReleaseFailed();
    }
  }

  Future<ReleaseMonthOutcome> releaseMonth(MonthReleaseReview review) async {
    try {
      if (review.kind == MonthReleaseKind.loadedMonth) {
        await _rules.confirmLoadedMonth(
          month,
          acknowledgeShortfalls: review.shortfallDays.isNotEmpty,
        );
      } else {
        await _rules.releaseMonth(
          month,
          acknowledgeShortfalls: review.shortfallDays.isNotEmpty,
        );
      }
      await refresh();
      return const Released();
    } catch (error) {
      _rejected(error);
      return const ReleaseMonthFailed();
    }
  }

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
      _replace(_withState(today: _dateOnly(_now())));
      refresh();
      _scheduleMidnight();
    });
  }

  MonthSessionState _withState({DateTime? today, bool? savingDrop}) =>
      MonthSessionState(
        today: today ?? _state.today,
        grid: _state.grid,
        coverage: _state.coverage,
        announcement: _state.announcement,
        unreached: _state.unreached,
        previousMonthStarted: _state.previousMonthStarted,
        shiftCodes: _state.shiftCodes,
        staffing: _state.staffing,
        loadError: _state.loadError,
        savingDrop: savingDrop ?? _state.savingDrop,
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
          savingDrop: _state.savingDrop,
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
