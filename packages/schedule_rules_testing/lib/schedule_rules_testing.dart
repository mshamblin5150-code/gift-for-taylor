library;

import 'dart:async';

import 'package:schedule_rules/schedule_rules.dart';

part 'src/schedule_database.dart';
part 'src/open_shifts.dart';
part 'src/swaps.dart';

ScheduleRules scheduleRulesInMemory(
  InMemoryScheduleDatabase database, {
  required String actingAs,
}) => ScheduleRules(database.storeFor(actingAs));

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

String _cellKey(String staffMemberId, DateTime date) {
  return '$staffMemberId:${date.year}-${date.month}-${date.day}';
}
