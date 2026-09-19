import 'dart:io';

import 'package:schedule_rules/schedule_rules.dart';

/// Turns the private transcription of the printed page into the one SQL
/// statement that loads it:
///
///   dart run bin/first_month_sql.dart 2026-10 ../../private/first-month.csv
///
/// The statement is written to stdout; redirect it into `private/` too.
void main(List<String> arguments) {
  final month = arguments.length == 2
      ? RegExp(r'^(\d{4})-(\d{2})$').firstMatch(arguments[0])
      : null;
  if (month == null) {
    stderr.writeln('Usage: first_month_sql.dart <yyyy-mm> <transcript.csv>');
    exitCode = 64;
    return;
  }

  try {
    final transcript = FirstMonthTranscript.parseCsv(
      File(arguments[1]).readAsStringSync(),
      month: DateTime(int.parse(month[1]!), int.parse(month[2]!)),
    );
    stdout.write(transcript.toLoadSql());
    stderr.writeln('${transcript.rows.length} rows ready to load.');
  } on TranscriptFormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 65;
  }
}
