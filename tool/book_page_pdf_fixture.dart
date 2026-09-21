import 'dart:io';

import 'package:er_schedule/schedule/book_page_pdf.dart';
import 'package:schedule_rules/schedule_rules.dart';

Future<void> main(List<String> args) async {
  const section = ScheduleSection(id: 'days', name: 'State dayshift RN');
  final rows = [
    for (var i = 0; i < (args[0] == 'dense' ? 42 : 2); i++)
      ScheduleRow(
        staffMemberId: 'rn-$i',
        displayName: i == 0 ? 'Alexandria Montgomery-Williams' : 'RN ${i + 1}',
        sectionId: 'days',
      ),
  ];
  final rules = ScheduleRules.inMemory(
    InMemoryScheduleDatabase(sections: const [section], rows: rows),
    actingAs: 'manager',
  );
  for (var i = 0; i < rows.length; i++) {
    for (final d in [5, 6, 12, 13, 19, 20, 26, 27]) {
      await rules.saveCell(
        SaveCell(
          staffMemberId: rows[i].staffMemberId,
          sectionId: 'days',
          date: DateTime(2026, 9, d),
          shiftCode: '16D',
        ),
      );
    }
  }
  await File(
    args[1],
  ).writeAsBytes(await bookPagePdf(await rules.monthGrid(DateTime(2026, 9))));
}
