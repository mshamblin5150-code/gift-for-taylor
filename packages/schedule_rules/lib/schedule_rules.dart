library;

import 'dart:async';

import 'src/access.dart';

export 'src/access.dart';
export 'src/book_page.dart';
export 'src/first_month_transcript.dart';

part 'src/change_announcement.dart';
part 'src/swaps.dart';
part 'src/request_off.dart';
part 'src/open_shifts.dart';
part 'src/coverage_reading.dart';

/// Character budgets for text printed on the Schedule book page.
const sectionNameLimit = 32;
const staffNameLimit = 30;
const shiftCodeLimit = 5;
const shiftMeaningLimit = 40;

/// A Schedule write was rejected because the viewer's Access is no longer valid.
final class AccessRejected implements Exception {
  const AccessRejected([this.cause]);

  final Object? cause;
}

/// Client logic composed over the signed-in person's Schedule store.
abstract interface class ScheduleRules {
  factory ScheduleRules(ScheduleStore store) = _ScheduleRules;

  /// The store used by this rules instance for direct reads and writes.
  ScheduleStore get store;

  Future<MonthGrid> monthGrid(DateTime month);
  Future<List<ScheduleChange>> changeLog(DateTime month);
  Future<List<ScheduleChange>> changeLogView(
    DateTime month, {
    String? changedBy,
    DateTime? changedOn,
    bool unreachedOnly = false,
  });
  Future<ChangeAnnouncement> changeAnnouncement(DateTime month);
  Future<void> markAnnounced(
    ChangeAnnouncement announcement, {
    Set<String> draftOpenedStaffMemberIds = const {},
  });
  Future<void> startNextMonth(DateTime month);
  Future<void> startEmptyMonth(DateTime month);
  Future<void> saveCell(SaveCell action);
  Future<void> undoCell(UndoCell action);
  Future<JobRole?> jobRoleOn(String staffMemberId, DateTime date);
  Future<RequestOffEmail> requestOff(RequestOffDraft draft);
}

/// The database behind the rules. The in-memory stand-in and the Supabase
/// adapter both implement it.
abstract interface class ScheduleStore {
  Future<List<ScheduleSection>> sections();
  Future<List<LegendCode>> shiftCodes();
  Future<List<ShiftCodeChangePlan>> previewShiftCodeChange(
    LegendCode code, {
    String? originalCode,
  });
  Future<void> commitShiftCodeChange(
    LegendCode code,
    List<ShiftCodeChangePlan> expectedPlan, {
    String? originalCode,
  });
  Future<void> saveShiftCode(LegendCode code, {String? originalCode});
  Future<void> deleteShiftCode(String code);

  /// Staff list rows on [month]'s Schedule, in Section and manual order, each
  /// in the last Section they held that month.
  Future<List<ScheduleRow>> rows(DateTime month);

  Future<List<ScheduleCell>> cellsForMonth(DateTime month);

  Future<List<ScheduleChange>> changesForMonth(DateTime month);

  Future<List<ShortShift>> shortShiftsForMonth(DateTime month);

  /// Stores the cell and appends its change log entry in one step, recording
  /// the signed-in person and the time. Refuses cells outside the signed-in
  /// person's editable Sections.
  Future<void> writeCell(ScheduleCell cell);

  Future<void> writeCellPair(SaveCellPair action);

  /// Whether the signed-in Staff member is working in the department now.
  Future<bool> isOnFloorNow();

  /// Records a Call-in and returns the number of Open shifts it posted.
  Future<int> recordCallIn(String staffMemberId, DateTime date);

  /// Whether a recorded Call-in can still be withdrawn.
  Future<CallInWithdrawalState> callInWithdrawalState(
    String staffMemberId,
    DateTime date,
  );

  Future<void> withdrawCallIn(String staffMemberId, DateTime date);

  Stream<void> monthUpdates(DateTime month);

  Future<Access> currentAccess();

  Future<void> assignNightScheduler(
    String staffMemberId,
    Set<String> sectionIds,
  );

  Future<void> removeNightScheduler(String staffMemberId);

  Future<List<NightScheduler>> nightSchedulers();

  /// Months loaded from the printed page and not yet confirmed, earliest first.
  Future<List<DateTime>> monthsAwaitingConfirmation();

  Future<void> confirmLoadedMonth(
    DateTime month, {
    bool acknowledgeShortfalls = false,
  });

  /// Settles the selected change log entries using the database's net diff.
  /// [draftOpenedStaffMemberIds] is evidence from the Messages sheet.
  Future<void> markChangesAnnounced(
    Set<String> changeIds,
    Set<String> draftOpenedStaffMemberIds,
  );

  Future<MonthStatus> monthStatus(DateTime month);

  /// Creates [month] unpublished holding [cells], without logging changes.
  Future<void> startMonth(
    DateTime month,
    List<ScheduleCell> cells, {
    DateTime? sourceMonth,
  });

  Future<void> releaseMonth(
    DateTime month, {
    bool acknowledgeShortfalls = false,
  });

  /// Deactivates the person, clears their cells after [SetLastDay.lastDay]
  /// with a change log entry each, and records the short shifts, in one step.
  Future<void> setLastDay(SetLastDay action);

  Future<void> reactivate(Reactivate action);

  Future<void> changeSection(ChangeSection action);

  Future<void> changeJobRole(ChangeJobRole action);

  /// The person's dated roles, earliest first.
  Future<List<DatedJobRole>> jobRoles(String staffMemberId);

  Future<List<StaffChange>> staffChanges();

  Future<RequestOffEmail> createRequestOff(RequestOffDraft draft);
  Future<void> confirmRequestOffEmail(String requestId);
  Future<List<RequestOff>> requestsOff({required bool pendingOnly});
  Future<void> decideRequestOff(
    String requestId,
    RequestOffDecision decision,
    String? reason,
  );
  Future<int> unreadRequestOffNotices();
  Future<void> acknowledgeRequestOffNotices();
}

enum CallInWithdrawalState { withdrawable, settled, notRecorded }

enum CallInRefusal { recorderNotWorking, targetNotWorking, settled }

final class CallInRefused implements Exception {
  const CallInRefused(this.reason);

  final CallInRefusal reason;
}

enum MonthStatus {
  /// Nothing has been written to the month yet.
  notStarted,

  /// Being built: schedulers see it, staff do not.
  unpublished,

  /// The live Schedule.
  released,
}

/// Thrown when starting a month that already holds a Schedule.
final class MonthAlreadyStarted implements Exception {
  const MonthAlreadyStarted();

  @override
  String toString() => 'That month has already been started';
}

/// A Shift code used by a Schedule cannot be deleted.
final class ShiftCodeInUse implements Exception {
  const ShiftCodeInUse();
}

/// The month to copy from has no Schedule yet.
final class PreviousMonthNotStarted extends StateError {
  PreviousMonthNotStarted() : super('There is no Schedule to start from');
}

/// Thrown when the signed-in person may not change the Schedule.
final class ScheduleEditRefused implements Exception {
  const ScheduleEditRefused([
    this.message = 'Only the Manager can edit the Schedule',
  ]);

  final String message;

  @override
  String toString() => message;
}

/// The Sections one signed-in person may change.
final class EditableSections {
  const EditableSections.all() : _sectionIds = null;

  const EditableSections.only(Set<String> sectionIds)
    : _sectionIds = sectionIds;

  /// Null means every Section.
  final Set<String>? _sectionIds;

  bool contains(String sectionId) => _sectionIds?.contains(sectionId) ?? true;

  bool get isEmpty => _sectionIds?.isEmpty ?? false;
}

/// A Staff member the Manager allowed to edit specific Sections.
final class NightScheduler {
  const NightScheduler({required this.staffMemberId, required this.sectionIds});

  final String staffMemberId;
  final Set<String> sectionIds;
}

final class SaveCell {
  const SaveCell({
    required this.staffMemberId,
    required this.sectionId,
    required this.date,
    required this.shiftCode,
  });

  final String staffMemberId;
  final String sectionId;
  final DateTime date;
  final String shiftCode;
}

final class SaveCellPair {
  const SaveCellPair({
    required this.first,
    required this.second,
    required this.expectedFirstCode,
    required this.expectedSecondCode,
  });

  final SaveCell first;
  final SaveCell second;
  final String expectedFirstCode;
  final String expectedSecondCode;
}

final class UndoCell {
  const UndoCell({
    required this.staffMemberId,
    required this.sectionId,
    required this.date,
  });

  final String staffMemberId;
  final String sectionId;
  final DateTime date;
}

final class SetLastDay {
  const SetLastDay({required this.staffMemberId, required this.lastDay});

  final String staffMemberId;
  final DateTime lastDay;
}

final class Reactivate {
  const Reactivate({
    required this.staffMemberId,
    required this.sectionId,
    required this.firstDay,
  });

  final String staffMemberId;
  final String sectionId;

  /// Their first day back on the Schedule; after their Last day.
  final DateTime firstDay;
}

final class ChangeSection {
  const ChangeSection({
    required this.staffMemberId,
    required this.sectionId,
    required this.from,
  });

  final String staffMemberId;
  final String sectionId;
  final DateTime from;
}

final class ChangeJobRole {
  const ChangeJobRole({
    required this.staffMemberId,
    required this.jobRole,
    required this.from,
  });

  final String staffMemberId;
  final JobRole jobRole;
  final DateTime from;
}

/// What a Staff member does, which decides the Open shifts they may pick up.
enum JobRole {
  rn('rn', 'RN'),
  lpn('lpn', 'LPN'),
  cna('cna', 'CNA'),
  unitClerk('unit_clerk', 'Unit clerk');

  const JobRole(this.value, this.label);

  /// The database value.
  final String value;
  final String label;

  static JobRole fromValue(String value) =>
      values.firstWhere((role) => role.value == value);
}

/// Stable identity for a Coverage pool. Names and membership are read for the
/// work date; the seed constants only preserve callers' initial defaults.
final class CoveragePool {
  const CoveragePool(this.value, this.label, {this.sortOrder = 0});
  final String value;
  final String label;
  final int sortOrder;

  static const nurses = CoveragePool('nurses', 'Nurses', sortOrder: 0);
  static const cna = CoveragePool('cna', 'CNAs', sortOrder: 1);
  static const unitClerk = CoveragePool(
    'unit_clerk',
    'Unit clerks',
    sortOrder: 2,
  );
  static const values = [nurses, cna, unitClerk];

  static CoveragePool fromValue(String value) =>
      values.where((pool) => pool.value == value).firstOrNull ??
      CoveragePool(value, value);

  @override
  bool operator ==(Object other) =>
      other is CoveragePool && other.value == value;

  @override
  int get hashCode => value.hashCode;

  static CoveragePool forJobRole(JobRole role) => switch (role) {
    JobRole.rn || JobRole.lpn => nurses,
    JobRole.cna => cna,
    JobRole.unitClerk => unitClerk,
  };
}

enum CoverageWindow {
  day('day', 'Days'),
  night('night', 'Nights');

  const CoverageWindow(this.value, this.label);
  final String value;
  final String label;

  static CoverageWindow fromValue(String value) =>
      values.firstWhere((window) => window.value == value);
}

final class DatedJobRole {
  const DatedJobRole({
    required this.jobRole,
    required this.from,
    required this.through,
  });

  final JobRole jobRole;
  final DateTime from;
  final DateTime? through;
}

enum StaffChangeKind {
  name('name'),
  cellNumber('cell_number'),
  lastDay('last_day'),
  reactivated('reactivated'),
  section('section'),
  jobRole('job_role'),
  accessRole('access_role');

  const StaffChangeKind(this.value);

  /// The database value.
  final String value;

  static StaffChangeKind fromValue(String value) =>
      values.firstWhere((kind) => kind.value == value);
}

/// One Staff list change log entry. Sections are recorded by name and roles
/// by label, as they were at the time.
final class StaffChange {
  const StaffChange({
    required this.staffMemberId,
    required this.kind,
    required this.oldValue,
    required this.newValue,
    required this.effectiveFrom,
    required this.changedBy,
    required this.changedAt,
  });

  final String staffMemberId;
  final StaffChangeKind kind;
  final String? oldValue;
  final String? newValue;
  final DateTime effectiveFrom;
  final String changedBy;
  final DateTime changedAt;
}

/// A shift left uncovered, such as one cleared after a Last day.
final class ShortShift {
  const ShortShift({
    this.sectionId,
    required this.date,
    required this.shiftCode,
    required this.staffMemberId,
    this.jobRole,
    this.coverageWindow,
    this.coveragePool,
  });

  final String? sectionId;
  final DateTime date;

  /// The shift that is no longer covered.
  final String shiftCode;

  /// Whose shift it was.
  final String? staffMemberId;
  final JobRole? jobRole;
  final CoverageWindow? coverageWindow;
  final CoveragePool? coveragePool;
}

final class ScheduleSection {
  const ScheduleSection({required this.id, required this.name});

  final String id;
  final String name;
}

/// One Staff list row on the Schedule, in the Section the person is in
/// during that month (the new one, for a mid-month move).
final class ScheduleRow {
  const ScheduleRow({
    required this.staffMemberId,
    required this.displayName,
    required this.sectionId,
    this.cellNumber,
    this.lastDay,
    this.hasPushSubscription = false,
    this.hasAcceptedInvite = false,
  });

  final String staffMemberId;
  final String displayName;
  final String sectionId;

  /// Where their Change announcements are texted; null if not on file.
  final String? cellNumber;

  /// Whether this Staff member currently has a live notification subscription.
  final bool hasPushSubscription;

  /// Whether this Staff member has an active account from an accepted Invite.
  final bool hasAcceptedInvite;

  /// The Last day of someone who left in or before this month, even if they
  /// have since come back.
  final DateTime? lastDay;
}

final class ScheduleCell {
  const ScheduleCell({
    required this.staffMemberId,
    required this.sectionId,
    required this.date,
    required this.shiftCode,
  });

  final String staffMemberId;
  final String sectionId;
  final DateTime date;
  final String shiftCode;
}

/// One change log entry.
final class ScheduleChange {
  const ScheduleChange({
    required this.id,
    required this.staffMemberId,
    required this.date,
    required this.oldShiftCode,
    required this.newShiftCode,
    required this.changedBy,
    required this.changedByName,
    required this.changedAt,
    required this.announced,
    this.swapId,
    this.moot = false,
    this.reach,
  });

  final String id;
  final String staffMemberId;
  final DateTime date;
  final String oldShiftCode;
  final String newShiftCode;

  /// The Staff member id of the scheduler who saved it.
  final String changedBy;

  /// Their display name, kept even after they leave the Staff list.
  final String changedByName;
  final DateTime changedAt;
  final bool announced;
  final String? swapId;
  final bool moot;
  final String? reach;
}

/// A common Shift code from the printed legend.
final class LegendCode {
  const LegendCode(
    this.code, {
    this.hours,
    this.meaning,
    bool? isWorking,
    this.startTime,
    this.endTime,
    this.coverageWindow,
    this.active = true,
  }) : isWorking = isWorking ?? hours != null;

  final String code;

  /// Working hours, such as 7A–7P; null for codes that are not a shift.
  final String? hours;
  final String? meaning;
  final bool isWorking;

  /// Local 24-hour HH:mm values; null means an untimed Calendar event.
  final String? startTime;
  final String? endTime;

  /// Day or Night coverage; null means the code counts toward neither window.
  final String? coverageWindow;
  final bool active;
}

enum CalendarInvitationMethod {
  request('REQUEST'),
  cancel('CANCEL');

  const CalendarInvitationMethod(this.value);

  final String value;

  static CalendarInvitationMethod fromValue(String value) =>
      CalendarInvitationMethod.values.singleWhere(
        (item) => item.value == value,
      );
}

final class ShiftCodeChangePlan {
  const ShiftCodeChangePlan({
    required this.workDate,
    required this.shiftCode,
    required this.method,
    required this.count,
    this.staffMemberIds = const [],
  });

  factory ShiftCodeChangePlan.fromJson(Map<String, dynamic> json) =>
      ShiftCodeChangePlan(
        workDate: DateTime.parse(json['work_date'] as String),
        shiftCode: json['shift_code'] as String,
        method: CalendarInvitationMethod.fromValue(json['method'] as String),
        count: json['count'] as int,
        staffMemberIds: List<String>.unmodifiable(
          (json['staff_member_ids'] as List<dynamic>).cast<String>(),
        ),
      );

  final DateTime workDate;
  final String shiftCode;
  final CalendarInvitationMethod method;
  final int count;
  final List<String> staffMemberIds;

  Map<String, dynamic> toJson() => {
    'work_date': workDate.toIso8601String().substring(0, 10),
    'shift_code': shiftCode,
    'method': method.value,
    'count': count,
    'staff_member_ids': staffMemberIds,
  };
}

String? coverageWindowForHours(String? start, String? end) {
  if (start == null || end == null || start == end) return null;
  int minutes(String value) =>
      int.parse(value.substring(0, 2)) * 60 + int.parse(value.substring(3, 5));
  final first = minutes(start);
  final last = minutes(end);
  bool covers(int anchor) => first < last
      ? first <= anchor && anchor < last
      : first <= anchor || anchor < last;
  if (covers(13 * 60)) return 'day';
  if (covers(2 * 60)) return 'night';
  return null;
}

/// Printable local hours for a timed Shift code.
String? shiftCodeHours(String? start, String? end) {
  if (start == null || end == null) return null;
  String label(String time) {
    final hour = int.parse(time.substring(0, 2));
    final minute = time.substring(3, 5);
    return '${hour % 12 == 0 ? 12 : hour % 12}${minute == '00' ? '' : ':$minute'}${hour < 12 ? 'A' : 'P'}';
  }

  return '${label(start)}–${label(end)}';
}

/// In-memory test fixture. Production reads the database catalog.
const shiftLegend = <LegendCode>[
  LegendCode('16D', hours: '7A–11P', coverageWindow: 'day'),
  LegendCode('7A', hours: '7A–7P', coverageWindow: 'day'),
  LegendCode('D', hours: '7A–3P', coverageWindow: 'day'),
  LegendCode('MM', hours: '11A–7P', coverageWindow: 'day'),
  LegendCode('11A', hours: '11A–11P', coverageWindow: 'day'),
  LegendCode('3P', hours: '3P–3A', coverageWindow: 'night'),
  LegendCode('7P', hours: '7P–7A', coverageWindow: 'night'),
  LegendCode('ME', hours: '7P–3A', coverageWindow: 'night'),
  LegendCode('N', hours: '11P–7A', coverageWindow: 'night'),
  LegendCode('X', meaning: 'Off'),
  LegendCode('R/O', meaning: 'Requested off'),
  LegendCode('H'),
  LegendCode('S/L', meaning: 'Sick leave'),
  LegendCode('C/I', meaning: 'Called in'),
];

/// Whether [shiftCode] is a shift someone works: anything but blank or a
/// legend code without hours. Off-legend codes count as working. The
/// database's `is_working_shift` applies the same rule.
bool isWorkingShift(
  String shiftCode, {
  Iterable<LegendCode> codes = shiftLegend,
}) {
  final code = shiftCode.trim().toUpperCase();
  return code.isNotEmpty &&
      (codes.where((entry) => entry.code == code).firstOrNull?.isWorking ??
          true);
}

/// A person's code on one day, for the day and one-person views.
final class RowDay {
  const RowDay({
    required this.row,
    required this.date,
    required this.shiftCode,
    required this.unannounced,
  });

  final ScheduleRow row;
  final DateTime date;
  final String shiftCode;
  final bool unannounced;
}

final class MonthGrid {
  MonthGrid._(
    this._codes,
    this._published, {
    required this.changedCells,
    required this.month,
    required this.sections,
    required this.rows,
    required this.shortShifts,
    required this.awaitingConfirmation,
    required this.status,
  });

  final DateTime month;
  final List<ScheduleSection> sections;
  final List<ScheduleRow> rows;

  /// Uncovered shifts in the month, such as those left by a Last day.
  final List<ShortShift> shortShifts;

  /// Loaded from the printed page and not yet checked by the Manager.
  final bool awaitingConfirmation;
  final MonthStatus status;
  final Map<String, String> _codes;

  /// Published values of cells whose current code differs from them.
  final Map<String, String> _published;
  final Set<String> changedCells;

  List<DateTime> get days => List.generate(
    DateTime(month.year, month.month + 1, 0).day,
    (index) => DateTime(month.year, month.month, index + 1),
  );

  List<ScheduleRow> rowsIn(String sectionId) =>
      rows.where((row) => row.sectionId == sectionId).toList(growable: false);

  /// Whether [date] is on or before the row's Last day, so its cell can be
  /// edited.
  bool isOnSchedule(ScheduleRow row, DateTime date) {
    final lastDay = row.lastDay;
    return lastDay == null || !_day(date).isAfter(lastDay);
  }

  List<ShortShift> shortShiftsOn(
    CoveragePool pool,
    CoverageWindow window,
    DateTime date,
  ) => shortShifts
      .where(
        (short) =>
            _sameDay(short.date, date) &&
            short.jobRole != null &&
            (short.coveragePool ?? CoveragePool.forJobRole(short.jobRole!)) ==
                pool &&
            short.coverageWindow == window,
      )
      .toList(growable: false);

  /// The name on [staffMemberId]'s row, or a placeholder for someone no
  /// longer on this month's Schedule.
  String displayNameOf(String staffMemberId) =>
      rows
          .where((row) => row.staffMemberId == staffMemberId)
          .firstOrNull
          ?.displayName ??
      'Former Staff member';

  String? shiftCodeFor(String staffMemberId, DateTime date) =>
      _codes[_cellKey(staffMemberId, date)];

  /// Whether the cell was changed since it was last announced.
  bool isUnannounced(String staffMemberId, DateTime date) =>
      _published.containsKey(_cellKey(staffMemberId, date));

  /// Whether a released Schedule cell has been edited since month release.
  bool isChanged(String staffMemberId, DateTime date) =>
      changedCells.contains(_cellKey(staffMemberId, date));

  /// The value the cell had when last announced.
  String publishedCodeFor(String staffMemberId, DateTime date) =>
      _published[_cellKey(staffMemberId, date)] ??
      shiftCodeFor(staffMemberId, date) ??
      '';

  /// Everyone on the Schedule on [date] and their code, in Section and row
  /// order.
  List<RowDay> rowsOn(DateTime date) => [
    for (final section in sections)
      for (final row in rowsIn(section.id))
        if (isOnSchedule(row, date)) _rowDay(row, date),
  ];

  /// One person's code for every day of the month.
  List<RowDay> monthFor(String staffMemberId) {
    final row = rows.firstWhere((row) => row.staffMemberId == staffMemberId);
    return [for (final day in days) _rowDay(row, day)];
  }

  RowDay _rowDay(ScheduleRow row, DateTime date) => RowDay(
    row: row,
    date: date,
    shiftCode: shiftCodeFor(row.staffMemberId, date) ?? '',
    unannounced: isUnannounced(row.staffMemberId, date),
  );
}

final class _ScheduleRules implements ScheduleRules {
  _ScheduleRules(this._store);

  final ScheduleStore _store;

  @override
  ScheduleStore get store => _store;

  @override
  Future<RequestOffEmail> requestOff(RequestOffDraft draft) {
    final dates = draft.dates.map(_day).toSet().toList()..sort();
    if (dates.isEmpty) throw ArgumentError('Choose at least one day');
    return _store.createRequestOff(
      RequestOffDraft(dates: dates, reason: draft.reason?.trim()),
    );
  }

  @override
  Future<void> saveCell(SaveCell action) async {
    final date = _day(action.date);
    final code = action.shiftCode.trim();
    final current = (await _store.cellsForMonth(
      DateTime(date.year, date.month),
    )).where((cell) => _sameCell(cell, action.staffMemberId, date)).firstOrNull;
    if ((current?.shiftCode ?? '') == code) return;
    await _store.writeCell(
      ScheduleCell(
        staffMemberId: action.staffMemberId,
        sectionId: action.sectionId,
        date: date,
        shiftCode: code,
      ),
    );
  }

  @override
  Future<void> undoCell(UndoCell action) async {
    final date = _day(action.date);
    final grid = await monthGrid(DateTime(date.year, date.month));
    if (!grid.isUnannounced(action.staffMemberId, date)) return;
    await saveCell(
      SaveCell(
        staffMemberId: action.staffMemberId,
        sectionId: action.sectionId,
        date: date,
        shiftCode: grid.publishedCodeFor(action.staffMemberId, date),
      ),
    );
  }

  @override
  Future<MonthGrid> monthGrid(DateTime month) async {
    return (await _monthWithChanges(month)).$1;
  }

  Future<(MonthGrid, List<ScheduleChange>)> _monthWithChanges(
    DateTime month,
  ) async {
    final start = DateTime(month.year, month.month);
    final results = await Future.wait([
      _store.sections(),
      _store.rows(start),
      _store.cellsForMonth(start),
      _store.changesForMonth(start),
      _store.monthsAwaitingConfirmation(),
      _store.monthStatus(start),
      _store.shortShiftsForMonth(start),
    ]);
    final cells = results[2] as List<ScheduleCell>;
    final changes = results[3] as List<ScheduleChange>;

    final codes = {
      for (final cell in cells)
        _cellKey(cell.staffMemberId, cell.date): cell.shiftCode,
    };
    final published = <String, String>{};
    for (final change in changes.where(
      (change) => !change.announced && !change.moot,
    )) {
      published.putIfAbsent(
        _cellKey(change.staffMemberId, change.date),
        () => change.oldShiftCode,
      );
    }
    published.removeWhere((key, value) => (codes[key] ?? '') == value);

    final releaseCodes = <String, String>{};
    for (final change in changes) {
      releaseCodes.putIfAbsent(
        _cellKey(change.staffMemberId, change.date),
        () => change.oldShiftCode,
      );
    }

    final grid = MonthGrid._(
      codes,
      published,
      changedCells: {
        for (final entry in releaseCodes.entries)
          if ((codes[entry.key] ?? '') != entry.value) entry.key,
      },
      month: start,
      sections: results[0] as List<ScheduleSection>,
      rows: results[1] as List<ScheduleRow>,
      shortShifts: results[6] as List<ShortShift>,
      awaitingConfirmation: (results[4] as List<DateTime>).contains(start),
      status: results[5] as MonthStatus,
    );
    return (grid, changes);
  }

  @override
  Future<List<ScheduleChange>> changeLog(DateTime month) {
    return _store.changesForMonth(DateTime(month.year, month.month));
  }

  @override
  Future<List<ScheduleChange>> changeLogView(
    DateTime month, {
    String? changedBy,
    DateTime? changedOn,
    bool unreachedOnly = false,
  }) async {
    final log = await changeLog(month);
    return [
      for (final change in log.reversed)
        if ((changedBy == null || change.changedBy == changedBy) &&
            (changedOn == null || _day(change.changedAt) == _day(changedOn)) &&
            (!unreachedOnly || change.reach == 'nobody'))
          change,
    ];
  }

  @override
  Future<JobRole?> jobRoleOn(String staffMemberId, DateTime date) async {
    final day = _day(date);
    return (await _store.jobRoles(staffMemberId))
        .where((role) => _covers(role.from, role.through, day))
        .firstOrNull
        ?.jobRole;
  }

  @override
  Future<ChangeAnnouncement> changeAnnouncement(DateTime month) async {
    final ((grid, changes), editable) = await (
      _monthWithChanges(month),
      _store.currentAccess(),
    ).wait;
    if (grid.status != MonthStatus.released) {
      return ChangeAnnouncement._(
        const {},
        month: grid.month,
        people: const [],
      );
    }
    return ChangeAnnouncement._from(
      grid,
      changes.where((change) => !change.announced && !change.moot),
      editable.editableSections,
    );
  }

  @override
  Future<void> markAnnounced(
    ChangeAnnouncement announcement, {
    Set<String> draftOpenedStaffMemberIds = const {},
  }) async {
    if (announcement._changeIds.isEmpty) return;
    await _store.markChangesAnnounced(
      announcement._changeIds,
      draftOpenedStaffMemberIds,
    );
  }

  @override
  Future<void> startNextMonth(DateTime month) async {
    final current = DateTime(month.year, month.month);
    final next = DateTime(month.year, month.month + 1);
    final (rows, currentCells) = await (
      _store.rows(next),
      _store.cellsForMonth(current),
    ).wait;
    final currentCodes = {
      for (final cell in currentCells)
        _cellKey(cell.staffMemberId, cell.date): cell.shiftCode,
    };
    final lastDay = DateTime(next.year, next.month + 1, 0).day;
    final cells = <ScheduleCell>[];
    for (final row in rows) {
      for (var day = 1; day <= lastDay; day++) {
        final date = DateTime(next.year, next.month, day);
        final code =
            currentCodes[_cellKey(
              row.staffMemberId,
              _sameWeekdayLastMonth(date),
            )] ??
            '';
        if (code.isEmpty || _clearedOnStart.contains(code.toUpperCase())) {
          continue;
        }
        cells.add(
          ScheduleCell(
            staffMemberId: row.staffMemberId,
            sectionId: row.sectionId,
            date: date,
            shiftCode: code,
          ),
        );
      }
    }
    await _store.startMonth(next, cells, sourceMonth: current);
  }

  @override
  Future<void> startEmptyMonth(DateTime month) async {
    final start = DateTime(month.year, month.month);
    await _store.startMonth(start, const []);
  }
}

/// Codes that belong to one month only and are not carried into the next.
const _clearedOnStart = {'R/O', 'H', 'S/L', 'A/L'};

/// The day of the previous month on the same weekday of the same week as
/// [date]: four weeks earlier, or five in a fifth week so that it repeats the
/// fourth.
DateTime _sameWeekdayLastMonth(DateTime date) {
  final fourWeeksEarlier = DateTime(date.year, date.month, date.day - 28);
  return fourWeeksEarlier.month != date.month
      ? fourWeeksEarlier
      : DateTime(date.year, date.month, date.day - 35);
}

String _dateText(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

/// Whether the dated range [from]–[through] (null for open-ended) covers
/// [day].
bool _covers(DateTime? from, DateTime? through, DateTime day) =>
    (from == null || !from.isAfter(day)) &&
    (through == null || !through.isBefore(day));

bool _sameCell(ScheduleCell cell, String staffMemberId, DateTime date) =>
    cell.staffMemberId == staffMemberId &&
    cell.date.year == date.year &&
    cell.date.month == date.month &&
    cell.date.day == date.day;

String _cellKey(String staffMemberId, DateTime date) {
  return '$staffMemberId:${date.year}-${date.month}-${date.day}';
}
