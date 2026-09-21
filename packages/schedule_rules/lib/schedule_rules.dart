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

/// Every schedule rule is reached through this public interface.
abstract interface class ScheduleRules {
  /// Rules backed by [store], the database seen by one signed-in person.
  factory ScheduleRules(ScheduleStore store) = _ScheduleRules;

  /// Rules backed by an in-memory [database], acting as one Staff member.
  factory ScheduleRules.inMemory(
    InMemoryScheduleDatabase database, {
    required String actingAs,
  }) {
    return _ScheduleRules(database.storeFor(actingAs));
  }

  /// The current catalog, including changes to historical Shift-code display.
  Future<List<LegendCode>> shiftCodes();
  Future<void> saveShiftCode(LegendCode code, {String? originalCode});
  Future<void> deleteShiftCode(String code);

  /// Saves a Shift code; it is live at once and written to the change log.
  /// Refused outside the signed-in person's editable Sections.
  Future<void> saveCell(SaveCell action);

  /// Saves two cells together, refusing stale values or either forbidden cell.
  Future<void> saveCellPair(SaveCellPair action);

  /// Gives [staffMemberId] the Night scheduler role limited to [sectionIds],
  /// replacing any Sections they had. Only the Manager may.
  Future<void> assignNightScheduler(
    String staffMemberId,
    Set<String> sectionIds,
  );

  /// Takes the Night scheduler role back. Only the Manager may.
  Future<void> removeNightScheduler(String staffMemberId);

  /// Everyone with the Night scheduler role and the Sections they may edit.
  Future<List<NightScheduler>> nightSchedulers();

  /// Restores a changed, unannounced cell to its published value.
  Future<void> undoCell(UndoCell action);

  Future<MonthGrid> monthGrid(DateTime month);

  /// Every change to cells in [month], oldest first.
  Future<List<ScheduleChange>> changeLog(DateTime month);

  /// The Manager's change log view of [month], newest first, optionally only
  /// the changes [changedBy] one person and made on the day [changedOn].
  Future<List<ScheduleChange>> changeLogView(
    DateTime month, {
    String? changedBy,
    DateTime? changedOn,
    bool unreachedOnly = false,
  });

  /// Emits whenever any scheduler saves a change in [month].
  Stream<void> monthUpdates(DateTime month);

  /// Takes a departing Staff member off the Staff list. Shifts through their
  /// Last day stay; later shifts are cleared, and each working shift among
  /// them is marked short. They are deactivated at once, never deleted.
  Future<void> setLastDay(SetLastDay action);

  /// Puts a past Staff member back on the Staff list, at the bottom of a
  /// Section, as the same person with their history connected. Their old
  /// sign-in no longer works; they need a fresh Invite.
  Future<void> reactivate(Reactivate action);

  /// Moves a Staff member's row to another Section from a chosen date. In the
  /// month of the move, and after it, the row is in the new Section; their
  /// scheduled shifts stay for the Manager to adjust.
  Future<void> changeSection(ChangeSection action);

  /// Changes a Staff member's role from a chosen date.
  Future<void> changeJobRole(ChangeJobRole action);

  /// The role a Staff member has on [date], if one has been set.
  Future<JobRole?> jobRoleOn(String staffMemberId, DateTime date);

  /// Every Last day, reactivation, Section and role change, oldest first.
  Future<List<StaffChange>> staffChanges();

  /// The month loaded from the printed page that the Manager has not yet
  /// checked, if any.
  Future<DateTime?> monthAwaitingConfirmation();

  /// The Manager has checked the loaded month against the printed Schedule
  /// page, and the month is released. Corrections made while checking it need
  /// no Change announcement.
  Future<void> confirmLoadedMonth(
    DateTime month, {
    bool acknowledgeShortfalls = false,
  });

  /// The unannounced changes in [month] within the signed-in person's
  /// editable Sections: who to tell, and what to say. Empty until the month
  /// is released, since releasing it announces the whole month.
  Future<ChangeAnnouncement> changeAnnouncement(DateTime month);

  /// Settles the changes in [announcement]. The database stamps Reach from
  /// push subscriptions and the drafts opened by the Manager. A newer edit to
  /// the same cell stays pending until the tray is refreshed.
  Future<void> markAnnounced(
    ChangeAnnouncement announcement, {
    Set<String> draftOpenedStaffMemberIds = const {},
  });

  /// Starts the month after [month] from it, unpublished. Each day copies the
  /// same weekday of the same week, a fifth week repeats the fourth, and
  /// R/O, H, S/L and A/L are cleared. [month] must have been started itself.
  Future<void> startNextMonth(DateTime month);

  /// Starts [month] unpublished with its current Staff rows and no Shift codes.
  Future<void> startEmptyMonth(DateTime month);

  /// Makes an unpublished month the live Schedule. Edits made while building
  /// it were never seen by staff, so they need no Change announcement.
  Future<void> releaseMonth(
    DateTime month, {
    bool acknowledgeShortfalls = false,
  });

  /// Submit a Request off as the signed-in Staff member. Returns the email
  /// draft destination and text; sending remains under the member's control.
  Future<RequestOffEmail> requestOff(RequestOffDraft draft);
  Future<void> confirmRequestOffEmail(String requestId);
  Future<List<RequestOff>> myRequestsOff();
  Future<List<RequestOff>> approvalQueue();
  Future<List<RequestOff>> requestOffHistory();
  Future<void> decideRequestOff(
    String requestId,
    RequestOffDecision decision, {
    String? reason,
  });
  Future<int> unreadRequestOffNotices();
  Future<void> acknowledgeRequestOffNotices();
}

/// The database behind the rules. The in-memory stand-in and the Supabase
/// adapter both implement it.
abstract interface class ScheduleStore {
  Future<List<ScheduleSection>> sections();
  Future<List<LegendCode>> shiftCodes();
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
  Future<void> startMonth(DateTime month, List<ScheduleCell> cells);

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
  });

  final String staffMemberId;
  final String displayName;
  final String sectionId;

  /// Where their Change announcements are texted; null if not on file.
  final String? cellNumber;

  /// Whether this Staff member currently has a live notification subscription.
  final bool hasPushSubscription;

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
  Future<List<LegendCode>> shiftCodes() => _store.shiftCodes();

  @override
  Future<void> saveShiftCode(LegendCode code, {String? originalCode}) =>
      _store.saveShiftCode(code, originalCode: originalCode);

  @override
  Future<void> deleteShiftCode(String code) => _store.deleteShiftCode(code);

  @override
  Future<RequestOffEmail> requestOff(RequestOffDraft draft) {
    final dates = draft.dates.map(_day).toSet().toList()..sort();
    if (dates.isEmpty) throw ArgumentError('Choose at least one day');
    return _store.createRequestOff(
      RequestOffDraft(dates: dates, reason: draft.reason?.trim()),
    );
  }

  @override
  Future<void> confirmRequestOffEmail(String requestId) =>
      _store.confirmRequestOffEmail(requestId);

  @override
  Future<List<RequestOff>> myRequestsOff() =>
      _store.requestsOff(pendingOnly: false);

  @override
  Future<List<RequestOff>> approvalQueue() =>
      _store.requestsOff(pendingOnly: true);

  @override
  Future<List<RequestOff>> requestOffHistory() =>
      _store.requestsOff(pendingOnly: false);

  @override
  Future<void> decideRequestOff(
    String requestId,
    RequestOffDecision decision, {
    String? reason,
  }) => _store.decideRequestOff(requestId, decision, reason?.trim());

  @override
  Future<int> unreadRequestOffNotices() => _store.unreadRequestOffNotices();

  @override
  Future<void> acknowledgeRequestOffNotices() =>
      _store.acknowledgeRequestOffNotices();

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
  Future<void> saveCellPair(SaveCellPair action) =>
      _store.writeCellPair(action);

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
  Stream<void> monthUpdates(DateTime month) {
    return _store.monthUpdates(DateTime(month.year, month.month));
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
    return _store.assignNightScheduler(staffMemberId, sectionIds);
  }

  @override
  Future<void> removeNightScheduler(String staffMemberId) {
    return _store.removeNightScheduler(staffMemberId);
  }

  @override
  Future<List<NightScheduler>> nightSchedulers() => _store.nightSchedulers();

  @override
  Future<DateTime?> monthAwaitingConfirmation() async {
    return (await _store.monthsAwaitingConfirmation()).firstOrNull;
  }

  @override
  Future<void> confirmLoadedMonth(
    DateTime month, {
    bool acknowledgeShortfalls = false,
  }) {
    return _store.confirmLoadedMonth(
      DateTime(month.year, month.month),
      acknowledgeShortfalls: acknowledgeShortfalls,
    );
  }

  @override
  Future<void> setLastDay(SetLastDay action) => _store.setLastDay(
    SetLastDay(
      staffMemberId: action.staffMemberId,
      lastDay: _day(action.lastDay),
    ),
  );

  @override
  Future<void> reactivate(Reactivate action) => _store.reactivate(
    Reactivate(
      staffMemberId: action.staffMemberId,
      sectionId: action.sectionId,
      firstDay: _day(action.firstDay),
    ),
  );

  @override
  Future<void> changeSection(ChangeSection action) => _store.changeSection(
    ChangeSection(
      staffMemberId: action.staffMemberId,
      sectionId: action.sectionId,
      from: _day(action.from),
    ),
  );

  @override
  Future<void> changeJobRole(ChangeJobRole action) => _store.changeJobRole(
    ChangeJobRole(
      staffMemberId: action.staffMemberId,
      jobRole: action.jobRole,
      from: _day(action.from),
    ),
  );

  @override
  Future<JobRole?> jobRoleOn(String staffMemberId, DateTime date) async {
    final day = _day(date);
    return (await _store.jobRoles(staffMemberId))
        .where((role) => _covers(role.from, role.through, day))
        .firstOrNull
        ?.jobRole;
  }

  @override
  Future<List<StaffChange>> staffChanges() => _store.staffChanges();

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
    if (!(await _store.currentAccess()).canRunSchedule) {
      throw const ScheduleEditRefused();
    }
    if (await _store.monthStatus(next) != MonthStatus.notStarted) {
      throw const MonthAlreadyStarted();
    }
    if (await _store.monthStatus(current) == MonthStatus.notStarted) {
      throw StateError('There is no Schedule to start from');
    }
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
    await _store.startMonth(next, cells);
  }

  @override
  Future<void> startEmptyMonth(DateTime month) async {
    final start = DateTime(month.year, month.month);
    if (!(await _store.currentAccess()).canRunSchedule) {
      throw const ScheduleEditRefused();
    }
    if (await _store.monthStatus(start) != MonthStatus.notStarted) {
      throw const MonthAlreadyStarted();
    }
    await _store.startMonth(start, const []);
  }

  @override
  Future<void> releaseMonth(
    DateTime month, {
    bool acknowledgeShortfalls = false,
  }) {
    return _store.releaseMonth(
      DateTime(month.year, month.month),
      acknowledgeShortfalls: acknowledgeShortfalls,
    );
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

/// An in-memory stand-in for the database, shared by every scheduler in a
/// test.
enum InMemoryStoreCall { sections, shiftCodes, staffingForMonth }

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
  final Map<String, int> _unreadRequestOffNotices = {};
  final StreamController<DateTime> _updates = StreamController.broadcast();
  final List<DateTime> _awaitingConfirmation = [];
  final Map<DateTime, MonthStatus> _monthStatus;
  final Map<InMemoryStoreCall, Object> _nextFailures = {};

  /// Makes the next matching read fail, then resumes normal in-memory reads.
  void failNext(InMemoryStoreCall call, Object error) {
    _nextFailures[call] = error;
  }

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
    if (!_database._isActive(_actingAs)) {
      throw StateError('Not on the Staff list');
    }
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
    for (final manager
        in _database._grants.entries
            .where((entry) => entry.value.manager)
            .map((entry) => entry.key)) {
      _database._unreadRequestOffNotices.update(
        manager,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
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
    final index = _database._requestsOff.indexWhere(
      (r) => r.id == requestId && r.staffMemberId == _actingAs,
    );
    if (index < 0) throw StateError('Request off not found');
    final request = _database._requestsOff[index];
    if (request.emailConfirmedAt == null) {
      _database._requestsOff[index] = request.withEmailConfirmed(
        _database._clock(),
      );
    }
  }

  @override
  Future<List<RequestOff>> requestsOff({required bool pendingOnly}) async {
    final manager = _access.canRunSchedule;
    if (pendingOnly && !manager) throw const ScheduleEditRefused();
    return [
      for (final request in _database._requestsOff)
        if (pendingOnly
            ? request.decision == RequestOffDecision.pending
            : manager || request.staffMemberId == _actingAs)
          request,
    ];
  }

  @override
  Future<void> decideRequestOff(
    String requestId,
    RequestOffDecision decision,
    String? reason,
  ) async {
    if (!_access.canRunSchedule) throw const ScheduleEditRefused();
    if (decision == RequestOffDecision.pending) {
      throw ArgumentError('Choose approve or decline');
    }
    final index = _database._requestsOff.indexWhere((r) => r.id == requestId);
    if (index < 0) throw StateError('Request off not found');
    final request = _database._requestsOff[index];
    if (request.decision != RequestOffDecision.pending) {
      throw StateError('Already decided');
    }
    if (decision == RequestOffDecision.approved) {
      for (final date in request.dates) {
        final row = (await rows(DateTime(date.year, date.month)))
            .where((r) => r.staffMemberId == request.staffMemberId)
            .firstOrNull;
        if (row == null ||
            (row.lastDay != null && date.isAfter(row.lastDay!))) {
          throw StateError('Staff member is not on the Schedule for that day');
        }
      }
      for (final date in request.dates) {
        final row = (await rows(DateTime(date.year, date.month)))
            .firstWhere((r) => r.staffMemberId == request.staffMemberId);
        final old =
            _database
                ._cells[_cellKey(request.staffMemberId, date)]
                ?.shiftCode ??
            '';
        if (old == 'R/O') continue;
        _write(
          ScheduleCell(
            staffMemberId: request.staffMemberId,
            sectionId: row.sectionId,
            date: date,
            shiftCode: 'R/O',
          ),
        );
        if (isWorkingShift(old, codes: _database._shiftCodes)) {
          _database._shortShifts.add(
            ShortShift(
              sectionId: row.sectionId,
              date: date,
              shiftCode: old,
              staffMemberId: request.staffMemberId,
              jobRole: await ScheduleRules.inMemory(
                _database,
                actingAs: _actingAs,
              ).jobRoleOn(request.staffMemberId, date),
              coverageWindow: _coverageWindowOf(old, _database._shiftCodes),
            ),
          );
        }
      }
    }
    _database._requestsOff[index] = request.withDecision(
      decision,
      reason,
      _database._clock(),
    );
    _database._unreadRequestOffNotices.update(
      request.staffMemberId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
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
          : (await openShifts.coveragePoolsOn(short.date))
                .where((config) => config.jobRoles.contains(role))
                .firstOrNull;
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
    final editable = _access.editableSections;
    if (!editable.contains(cell.sectionId)) {
      throw editable.isEmpty
          ? const ScheduleEditRefused()
          : const ScheduleEditRefused('Only the Manager can edit that Section');
    }
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
            jobRole: await ScheduleRules.inMemory(
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

String _dateText(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

CoverageWindow? _coverageWindowOf(String code, List<LegendCode> codes) {
  final value = codes
      .where((item) => item.code == code.trim().toUpperCase())
      .firstOrNull
      ?.coverageWindow;
  return value == null ? null : CoverageWindow.fromValue(value);
}

bool _inMonth(DateTime date, DateTime month) =>
    date.year == month.year && date.month == month.month;

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
