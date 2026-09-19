library;

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
  const MonthGrid({required this.sections, required this.cells});

  final List<ScheduleSection> sections;
  final List<ScheduleCell> cells;

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

// TODO: Export any libraries intended for clients of this package.
