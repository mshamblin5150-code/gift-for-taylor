library;

import 'dart:async';

export 'src/first_month_transcript.dart';

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

  /// Whether the signed-in person is the Manager, who may change every
  /// Section, confirm a month and hand out the Night scheduler role.
  Future<bool> canEditSchedule();

  /// The Sections whose cells the signed-in person may change: every Section
  /// for the Manager, the assigned ones for a Night scheduler, none otherwise.
  Future<EditableSections> editableSections();

  /// Saves a Shift code; it is live at once and written to the change log.
  /// Refused outside the signed-in person's [editableSections].
  Future<void> saveCell(SaveCell action);

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
  });

  /// Emits whenever any scheduler saves a change in [month].
  Stream<void> monthUpdates(DateTime month);

  /// The month loaded from the printed page that the Manager has not yet
  /// checked, if any.
  Future<DateTime?> monthAwaitingConfirmation();

  /// The Manager's check of the loaded month is done: it replaces her Excel
  /// file and is released. Corrections made while checking it need no Change
  /// announcement.
  Future<void> confirmLoadedMonth(DateTime month);
}

/// The database behind the rules. The in-memory stand-in and the Supabase
/// adapter both implement it.
abstract interface class ScheduleStore {
  Future<List<ScheduleSection>> sections();

  /// Staff list rows, in Section and manual order.
  Future<List<ScheduleRow>> rows(DateTime month);

  Future<List<ScheduleCell>> cellsForMonth(DateTime month);

  Future<List<ScheduleChange>> changesForMonth(DateTime month);

  /// Stores the cell and appends its change log entry in one step, recording
  /// the signed-in person and the time. Refuses cells outside the signed-in
  /// person's editable Sections.
  Future<void> writeCell(ScheduleCell cell);

  Stream<void> monthUpdates(DateTime month);

  Future<bool> canEditSchedule();

  Future<EditableSections> editableSections();

  Future<void> assignNightScheduler(
    String staffMemberId,
    Set<String> sectionIds,
  );

  Future<void> removeNightScheduler(String staffMemberId);

  Future<List<NightScheduler>> nightSchedulers();

  /// Months loaded from the printed page and not yet confirmed, earliest first.
  Future<List<DateTime>> monthsAwaitingConfirmation();

  Future<void> confirmLoadedMonth(DateTime month);
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

final class ScheduleSection {
  const ScheduleSection({required this.id, required this.name});

  final String id;
  final String name;
}

/// One Staff list row on the Schedule.
final class ScheduleRow {
  const ScheduleRow({
    required this.staffMemberId,
    required this.displayName,
    required this.sectionId,
  });

  final String staffMemberId;
  final String displayName;
  final String sectionId;
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
    required this.staffMemberId,
    required this.date,
    required this.oldShiftCode,
    required this.newShiftCode,
    required this.changedBy,
    required this.changedByName,
    required this.changedAt,
    required this.announced,
  });

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
}

/// A common Shift code from the printed legend.
final class LegendCode {
  const LegendCode(this.code, {this.hours, this.meaning});

  final String code;

  /// Working hours, such as 7A–7P; null for codes that are not a shift.
  final String? hours;
  final String? meaning;
}

/// The printed legend: shortcuts, not a closed list.
const shiftLegend = <LegendCode>[
  LegendCode('16D', hours: '7A–11P'),
  LegendCode('7A', hours: '7A–7P'),
  LegendCode('D', hours: '7A–3P'),
  LegendCode('MM', hours: '11A–7P'),
  LegendCode('11A', hours: '11A–11P'),
  LegendCode('3P', hours: '3P–3A'),
  LegendCode('7P', hours: '7P–7A'),
  LegendCode('ME', hours: '7P–3A'),
  LegendCode('N', hours: '11P–7A'),
  LegendCode('X', meaning: 'Off'),
  LegendCode('R/O', meaning: 'Requested off'),
  LegendCode('H'),
  LegendCode('S/L', meaning: 'Sick leave'),
];

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
    required this.month,
    required this.sections,
    required this.rows,
    required this.awaitingConfirmation,
  });

  final DateTime month;
  final List<ScheduleSection> sections;
  final List<ScheduleRow> rows;

  /// Loaded from the printed page and not yet checked by the Manager.
  final bool awaitingConfirmation;
  final Map<String, String> _codes;

  /// Published values of cells whose current code differs from them.
  final Map<String, String> _published;

  List<DateTime> get days => List.generate(
    DateTime(month.year, month.month + 1, 0).day,
    (index) => DateTime(month.year, month.month, index + 1),
  );

  List<ScheduleRow> rowsIn(String sectionId) =>
      rows.where((row) => row.sectionId == sectionId).toList(growable: false);

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

  /// The value the cell had when last announced.
  String publishedCodeFor(String staffMemberId, DateTime date) =>
      _published[_cellKey(staffMemberId, date)] ??
      shiftCodeFor(staffMemberId, date) ??
      '';

  /// Everyone's code on [date], in Section and row order.
  List<RowDay> rowsOn(DateTime date) => [
    for (final section in sections)
      for (final row in rowsIn(section.id)) _rowDay(row, date),
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
    final start = DateTime(month.year, month.month);
    final results = await Future.wait([
      _store.sections(),
      _store.rows(start),
      _store.cellsForMonth(start),
      _store.changesForMonth(start),
      _store.monthsAwaitingConfirmation(),
    ]);
    final cells = results[2] as List<ScheduleCell>;
    final changes = results[3] as List<ScheduleChange>;

    final codes = {
      for (final cell in cells)
        _cellKey(cell.staffMemberId, cell.date): cell.shiftCode,
    };
    final published = <String, String>{};
    for (final change in changes.where((change) => !change.announced)) {
      published.putIfAbsent(
        _cellKey(change.staffMemberId, change.date),
        () => change.oldShiftCode,
      );
    }
    published.removeWhere((key, value) => (codes[key] ?? '') == value);

    return MonthGrid._(
      codes,
      published,
      month: start,
      sections: results[0] as List<ScheduleSection>,
      rows: results[1] as List<ScheduleRow>,
      awaitingConfirmation: (results[4] as List<DateTime>).contains(start),
    );
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
  }) async {
    final log = await changeLog(month);
    return [
      for (final change in log.reversed)
        if ((changedBy == null || change.changedBy == changedBy) &&
            (changedOn == null || _day(change.changedAt) == _day(changedOn)))
          change,
    ];
  }

  @override
  Future<bool> canEditSchedule() => _store.canEditSchedule();

  @override
  Future<EditableSections> editableSections() => _store.editableSections();

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
  Future<void> confirmLoadedMonth(DateTime month) {
    return _store.confirmLoadedMonth(DateTime(month.year, month.month));
  }
}

/// An in-memory stand-in for the database, shared by every scheduler in a
/// test.
final class InMemoryScheduleDatabase {
  InMemoryScheduleDatabase({
    required List<ScheduleSection> sections,
    List<ScheduleRow> rows = const [],
    this.editors,
    Map<String, String> names = const {},
    DateTime Function()? clock,
  }) : _sections = List.unmodifiable(sections),
       _rows = List.unmodifiable(rows),
       _names = {
         for (final row in rows) row.staffMemberId: row.displayName,
         ...names,
       },
       _clock = clock ?? DateTime.now;

  final List<ScheduleSection> _sections;

  /// Staff member ids who act as the Manager; null lets everyone who is not a
  /// Night scheduler.
  final Set<String>? editors;
  final List<ScheduleRow> _rows;

  /// Display names of people not on a Schedule row, such as the Manager.
  final Map<String, String> _names;
  final Map<String, Set<String>> _nightSchedulers = {};
  final DateTime Function() _clock;
  final Map<String, ScheduleCell> _cells = {};
  final List<ScheduleChange> _changes = [];
  final StreamController<DateTime> _updates = StreamController.broadcast();
  final List<DateTime> _awaitingConfirmation = [];

  /// Loads [month] as transcribed from the printed page, without logging a
  /// change, to wait for the Manager's check.
  void loadFromPage(DateTime month, List<ScheduleCell> cells) {
    for (final cell in cells) {
      _cells[_cellKey(cell.staffMemberId, cell.date)] = cell;
    }
    _awaitingConfirmation.add(DateTime(month.year, month.month));
  }

  /// Marks every logged change announced.
  void markAllAnnounced() => _markAnnounced((_) => true);

  void _markAnnounced(bool Function(ScheduleChange change) where) {
    for (final (index, change) in _changes.indexed) {
      if (!where(change)) continue;
      _changes[index] = ScheduleChange(
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
}

final class _InMemoryScheduleStore implements ScheduleStore {
  _InMemoryScheduleStore(this._database, this._actingAs);

  final InMemoryScheduleDatabase _database;
  final String _actingAs;

  @override
  Future<List<ScheduleSection>> sections() async => _database._sections;

  @override
  Future<List<ScheduleRow>> rows(DateTime month) async {
    final sectionOrder = [
      for (final section in _database._sections) section.id,
    ];
    final ordered = _database._rows.indexed.toList()
      ..sort((left, right) {
        final bySection = sectionOrder
            .indexOf(left.$2.sectionId)
            .compareTo(sectionOrder.indexOf(right.$2.sectionId));
        return bySection != 0 ? bySection : left.$1.compareTo(right.$1);
      });
    return [for (final (_, row) in ordered) row];
  }

  @override
  Future<List<ScheduleCell>> cellsForMonth(DateTime month) async {
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
  Future<void> writeCell(ScheduleCell cell) async {
    final editable = await editableSections();
    if (!editable.contains(cell.sectionId)) {
      throw editable.isEmpty
          ? const ScheduleEditRefused()
          : const ScheduleEditRefused('Only the Manager can edit that Section');
    }
    final row = _database._rows
        .where((row) => row.staffMemberId == cell.staffMemberId)
        .firstOrNull;
    if (row != null && row.sectionId != cell.sectionId) {
      throw StateError(
        'That Staff member is not on the Staff list in this Section',
      );
    }
    final key = _cellKey(cell.staffMemberId, cell.date);
    final old = _database._cells[key]?.shiftCode ?? '';
    _database._cells[key] = cell;
    _database._changes.add(
      ScheduleChange(
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
  Future<EditableSections> editableSections() async {
    final assigned = _database._nightSchedulers[_actingAs];
    if (assigned != null) return EditableSections.only({...assigned});
    if (await canEditSchedule()) return const EditableSections.all();
    return const EditableSections.only({});
  }

  @override
  Future<void> assignNightScheduler(
    String staffMemberId,
    Set<String> sectionIds,
  ) async {
    if (!await canEditSchedule()) throw const ScheduleEditRefused();
    _database._nightSchedulers[staffMemberId] = {...sectionIds};
  }

  @override
  Future<void> removeNightScheduler(String staffMemberId) async {
    if (!await canEditSchedule()) throw const ScheduleEditRefused();
    _database._nightSchedulers.remove(staffMemberId);
  }

  @override
  Future<List<NightScheduler>> nightSchedulers() async => [
    for (final MapEntry(:key, :value) in _database._nightSchedulers.entries)
      NightScheduler(staffMemberId: key, sectionIds: {...value}),
  ];

  @override
  Stream<void> monthUpdates(DateTime month) {
    return _database._updates.stream.where((date) => _inMonth(date, month));
  }

  @override
  Future<bool> canEditSchedule() async =>
      !_database._nightSchedulers.containsKey(_actingAs) &&
      (_database.editors?.contains(_actingAs) ?? true);

  @override
  Future<List<DateTime>> monthsAwaitingConfirmation() async {
    return [..._database._awaitingConfirmation]..sort();
  }

  @override
  Future<void> confirmLoadedMonth(DateTime month) async {
    if (!await canEditSchedule()) throw const ScheduleEditRefused();
    if (!_database._awaitingConfirmation.remove(month)) {
      throw StateError('There is no loaded month waiting to be confirmed');
    }
    _database._markAnnounced((change) => _inMonth(change.date, month));
  }
}

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

bool _inMonth(DateTime date, DateTime month) =>
    date.year == month.year && date.month == month.month;

bool _sameCell(ScheduleCell cell, String staffMemberId, DateTime date) =>
    cell.staffMemberId == staffMemberId &&
    cell.date.year == date.year &&
    cell.date.month == date.month &&
    cell.date.day == date.day;

String _cellKey(String staffMemberId, DateTime date) {
  return '$staffMemberId:${date.year}-${date.month}-${date.day}';
}
