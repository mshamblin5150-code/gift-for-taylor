library;

import 'dart:async';

import 'package:schedule_rules/schedule_rules.dart';

part 'src/schedule_database.dart';
part 'src/open_shifts.dart';
part 'src/swaps.dart';
part 'src/giveaways.dart';

ScheduleRules scheduleRulesInMemory(
  InMemoryScheduleDatabase database, {
  required String actingAs,
}) => ScheduleRules(database.storeFor(actingAs));

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

bool _inMonth(DateTime date, DateTime month) =>
    date.year == month.year && date.month == month.month;

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String _cellKey(String staffMemberId, DateTime date) {
  return '$staffMemberId:${date.year}-${date.month}-${date.day}';
}
