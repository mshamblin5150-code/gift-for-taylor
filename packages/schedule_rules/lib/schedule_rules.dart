library;

export 'src/first_month_transcript.dart';

/// Every schedule rule is reached through this public interface.
abstract interface class ScheduleRules {
  factory ScheduleRules.inMemory({required List<ScheduleSection> sections}) =
      _InMemoryScheduleRules;

  Future<void> saveCell(SaveCell action);

  Future<MonthGrid> monthGrid(DateTime month);
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

final class ScheduleSection {
  const ScheduleSection({required this.id, required this.name});

  final String id;
  final String name;
}

final class MonthGrid {
  const MonthGrid({
    required this.sections,
    required this.cells,
    this.rows = const [],
    this.started = false,
    this.awaitingConfirmation = false,
  });

  /// Lays out a month the way the book page does: each person once, in the
  /// Section their cells are in, in Staff list order. Current Staff members
  /// placed by the end of the month get a row even before they have cells.
  /// [displayNames] names people with cells who are no longer placed.
  factory MonthGrid.arrange({
    required DateTime month,
    required List<ScheduleSection> sections,
    required List<ScheduleCell> cells,
    required List<StaffPlacement> staff,
    Map<String, String> displayNames = const {},
    bool started = false,
    bool awaitingConfirmation = false,
  }) {
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    final placements = {for (final person in staff) person.staffMemberId: person};
    final sectionByPerson = <String, String>{};
    for (final cell in [...cells]..sort((a, b) => a.date.compareTo(b.date))) {
      sectionByPerson.putIfAbsent(cell.staffMemberId, () => cell.sectionId);
    }
    for (final person in staff) {
      if (!person.effectiveFrom.isAfter(monthEnd)) {
        sectionByPerson.putIfAbsent(person.staffMemberId, () => person.sectionId);
      }
    }

    final rows = [
      for (final MapEntry(key: staffMemberId, value: sectionId)
          in sectionByPerson.entries)
        ScheduleRow(
          staffMemberId: staffMemberId,
          displayName:
              placements[staffMemberId]?.displayName ??
              displayNames[staffMemberId] ??
              '',
          sectionId: sectionId,
        ),
    ];
    int? orderOf(ScheduleRow row) {
      final placement = placements[row.staffMemberId];
      return placement?.sectionId == row.sectionId
          ? placement!.displayOrder
          : null;
    }

    rows.sort((left, right) {
      final leftOrder = orderOf(left);
      final rightOrder = orderOf(right);
      if (leftOrder != null && rightOrder != null) {
        return leftOrder.compareTo(rightOrder);
      }
      if (leftOrder != null) return -1;
      if (rightOrder != null) return 1;
      return left.displayName.compareTo(right.displayName);
    });

    return MonthGrid(
      sections: sections,
      cells: cells,
      rows: List.unmodifiable(rows),
      started: started,
      awaitingConfirmation: awaitingConfirmation,
    );
  }

  final List<ScheduleSection> sections;
  final List<ScheduleCell> cells;
  final List<ScheduleRow> rows;

  /// Whether the month exists yet, so its cells can be edited.
  final bool started;

  /// Loaded from the printed page and not yet checked by the Manager.
  final bool awaitingConfirmation;

  List<ScheduleRow> rowsIn(String sectionId) {
    return rows.where((row) => row.sectionId == sectionId).toList();
  }

  String? shiftCodeFor(String staffMemberId, DateTime date) {
    for (final cell in cells) {
      if (cell.staffMemberId == staffMemberId &&
          _sameCalendarDay(cell.date, date)) {
        return cell.shiftCode;
      }
    }
    return null;
  }
}

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

/// A Staff member's current place on the Staff list.
final class StaffPlacement {
  const StaffPlacement({
    required this.staffMemberId,
    required this.displayName,
    required this.sectionId,
    required this.displayOrder,
    required this.effectiveFrom,
  });

  final String staffMemberId;
  final String displayName;
  final String sectionId;
  final int displayOrder;
  final DateTime effectiveFrom;
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

abstract interface class _ScheduleDatabase {
  Future<void> saveCell(ScheduleCell cell);

  Future<List<ScheduleCell>> cellsForMonth(DateTime month);
}

final class _InMemoryScheduleDatabase implements _ScheduleDatabase {
  final Map<String, ScheduleCell> _cells = {};

  @override
  Future<void> saveCell(ScheduleCell cell) async {
    _cells[_cellKey(cell.staffMemberId, cell.date)] = cell;
  }

  @override
  Future<List<ScheduleCell>> cellsForMonth(DateTime month) async {
    return _cells.values
        .where(
          (cell) =>
              cell.date.year == month.year && cell.date.month == month.month,
        )
        .toList(growable: false);
  }
}

final class _InMemoryScheduleRules implements ScheduleRules {
  _InMemoryScheduleRules({required List<ScheduleSection> sections})
    : _sections = List.unmodifiable(sections),
      _database = _InMemoryScheduleDatabase();

  final List<ScheduleSection> _sections;
  final _ScheduleDatabase _database;

  @override
  Future<void> saveCell(SaveCell action) {
    return _database.saveCell(
      ScheduleCell(
        staffMemberId: action.staffMemberId,
        sectionId: action.sectionId,
        date: DateTime(action.date.year, action.date.month, action.date.day),
        shiftCode: action.shiftCode,
      ),
    );
  }

  @override
  Future<MonthGrid> monthGrid(DateTime month) async {
    return MonthGrid(
      sections: _sections,
      cells: await _database.cellsForMonth(month),
    );
  }
}

bool _sameCalendarDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

String _cellKey(String staffMemberId, DateTime date) {
  return '$staffMemberId:${date.year}-${date.month}-${date.day}';
}

