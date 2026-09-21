import 'dart:io';

import 'package:schedule_rules/schedule_rules.dart';

/// Writes a real book page for browser print regression checks.
Future<void> main(List<String> args) async {
  if (args.length != 2 || (args[0] != 'small' && args[0] != 'dense')) {
    stderr.writeln(
      'Usage: dart run tool/book_page_print_fixture.dart small|dense output.html',
    );
    exitCode = 64;
    return;
  }

  const section = ScheduleSection(id: 'days', name: 'State dayshift RN');
  final dense = args[0] == 'dense';
  final rows = [
    for (var index = 0; index < (dense ? 42 : 2); index++)
      ScheduleRow(
        staffMemberId: 'rn-$index',
        displayName: 'RN ${index + 1}',
        sectionId: section.id,
      ),
  ];
  final rules = ScheduleRules.inMemory(
    InMemoryScheduleDatabase(sections: const [section], rows: rows),
    actingAs: 'manager',
  );
  for (var index = 0; index < rows.length; index++) {
    for (final day in [5, 6, 7, 12, 13, 19, 20, 26, 27]) {
      if ((index.isOdd && day == 5) || (index.isEven && day == 6)) {
        continue;
      }
      await rules.saveCell(
        SaveCell(
          staffMemberId: rows[index].staffMemberId,
          sectionId: section.id,
          date: DateTime(2026, 9, day),
          shiftCode: '16D',
        ),
      );
    }
  }
  final html = bookPageHtml(await rules.monthGrid(DateTime(2026, 9)));
  await File(args[1]).writeAsString(html);
}
