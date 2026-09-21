part of '../schedule_rules.dart';

enum CoverageState { covered, short, notSet }

final class WindowCoverage {
  const WindowCoverage({
    required this.window,
    required this.minimum,
    required this.onFloor,
    required this.shortfall,
    required this.floorShortfall,
    required this.floorRole,
    required this.openCount,
    required this.summary,
  });

  final CoverageWindow window;
  final int? minimum;
  final int onFloor;
  final int shortfall;
  final int floorShortfall;
  final JobRole? floorRole;
  final int openCount;
  final String summary;
}

final class DayCoverage {
  const DayCoverage({
    required this.bandNumber,
    required this.state,
    required this.windows,
  });

  final int bandNumber;
  final CoverageState state;
  final List<WindowCoverage> windows;

  WindowCoverage window(CoverageWindow value) =>
      windows.firstWhere((item) => item.window == value);
}

/// A single, immutable reading of one month's coverage facts.
final class CoverageReading {
  CoverageReading(MonthGrid grid, List<SectionStaffing> staffing)
    : _days = List.unmodifiable(grid.days),
      _staffing = Map.unmodifiable({
        for (final item in staffing)
          (item.pool.value, item.coverageWindow, _date(item.date)): item,
      }),
      _open = Map.unmodifiable(_openByWindow(grid)) {
    final pools = <String, CoveragePool>{};
    final poolsByDay = <DateTime, Map<String, CoveragePool>>{};
    for (final item in staffing) {
      final date = _date(item.date);
      if (!_days.contains(date)) continue;
      poolsByDay.putIfAbsent(date, () => {})[item.pool.value] = item.pool;
      if (item.minimum != null || item.openCount > 0) {
        pools[item.pool.value] = item.pool;
      }
    }
    for (final shift in grid.shortShifts) {
      final pool = _poolOf(shift);
      if (pool != null && shift.coverageWindow != null) {
        pools.putIfAbsent(pool.value, () => pool);
        poolsByDay.putIfAbsent(_date(shift.date), () => {})[pool.value] = pool;
      }
    }
    _poolsByDay = Map.unmodifiable({
      for (final entry in poolsByDay.entries)
        entry.key: List<CoveragePool>.unmodifiable(
          entry.value.values.toList()
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
        ),
    });
    visiblePools = List.unmodifiable(
      pools.values.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
    );

    final short = <DateTime>[];
    final open = <DateTime>[];
    for (final date in _days) {
      var hasShortfall = false;
      var hasOpen = false;
      for (final pool in visiblePools) {
        final reading = day(pool, date);
        hasShortfall |= reading.windows.any((window) => window.shortfall > 0);
        hasOpen |= reading.windows.any((window) => window.openCount > 0);
      }
      if (hasShortfall) {
        short.add(date);
      } else if (hasOpen) {
        open.add(date);
      }
    }
    shortfallDays = List.unmodifiable(short);
    openShiftDays = List.unmodifiable(open);
  }

  final List<DateTime> _days;
  final Map<(String, CoverageWindow, DateTime), SectionStaffing> _staffing;
  final Map<(String, CoverageWindow, DateTime), int> _open;
  late final Map<DateTime, List<CoveragePool>> _poolsByDay;
  late final List<CoveragePool> visiblePools;
  late final List<DateTime> shortfallDays;
  late final List<DateTime> openShiftDays;

  /// Day view includes unset pools so their date minimum can be edited.
  List<CoveragePool> dayPools(DateTime date) =>
      _poolsByDay[_date(date)] ?? const [];

  DayCoverage day(CoveragePool pool, DateTime date) {
    final windows = <WindowCoverage>[];
    var shortfall = 0;
    var open = 0;
    var hasMinimum = false;
    for (final window in CoverageWindow.values) {
      final key = (pool.value, window, _date(date));
      final item = _staffing[key];
      final count = item?.shortCount ?? 0;
      final floor = item?.rnShortCount ?? 0;
      final openCount = item?.openCount ?? _open[key] ?? 0;
      final floorName = item?.floorRole?.label ?? '';
      final poolName = pool == CoveragePool.nurses
          ? 'nursing'
          : pool.label.toLowerCase();
      final summary = item?.minimum == null
          ? 'not set'
          : count == 0
          ? 'Covered'
          : floor > 0 && floor == count && floorName.isNotEmpty
          ? 'Short $count $floorName'
          : floor > 0 && floorName.isNotEmpty
          ? 'Short $count $poolName, $floor $floorName'
          : 'Short $count $poolName';
      windows.add(
        WindowCoverage(
          window: window,
          minimum: item?.minimum,
          onFloor: item?.workingCount ?? 0,
          shortfall: count,
          floorShortfall: floor,
          floorRole: item?.floorRole,
          openCount: openCount,
          summary: summary,
        ),
      );
      shortfall += count;
      open += openCount;
      hasMinimum |= item?.minimum != null;
    }
    return DayCoverage(
      bandNumber: shortfall > open ? shortfall : open,
      state: !hasMinimum && open == 0
          ? CoverageState.notSet
          : shortfall > 0 || open > 0
          ? CoverageState.short
          : CoverageState.covered,
      windows: List.unmodifiable(windows),
    );
  }

  static DateTime _date(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static CoveragePool? _poolOf(ShortShift shift) =>
      shift.coveragePool ??
      (shift.jobRole == null ? null : CoveragePool.forJobRole(shift.jobRole!));

  static Map<(String, CoverageWindow, DateTime), int> _openByWindow(
    MonthGrid grid,
  ) {
    final open = <(String, CoverageWindow, DateTime), int>{};
    for (final shift in grid.shortShifts) {
      final pool = _poolOf(shift);
      if (pool == null || shift.coverageWindow == null) continue;
      final key = (pool.value, shift.coverageWindow!, _date(shift.date));
      open.update(key, (count) => count + 1, ifAbsent: () => 1);
    }
    return open;
  }
}
