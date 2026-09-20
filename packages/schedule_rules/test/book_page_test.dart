import 'package:schedule_rules/schedule_rules.dart';
import 'package:test/test.dart';

void main() {
  const days = ScheduleSection(id: 'days', name: 'State dayshift RN');
  const nights = ScheduleSection(id: 'nights', name: 'PRN nightshift RN');
  const dayNurse = ScheduleRow(
    staffMemberId: 'rn-1',
    displayName: 'Day RN',
    sectionId: 'days',
  );
  const nightNurse = ScheduleRow(
    staffMemberId: 'rn-2',
    displayName: 'Night RN',
    sectionId: 'nights',
  );
  final september = DateTime(2026, 9);
  final october = DateTime(2026, 10);

  late InMemoryScheduleDatabase database;
  late ScheduleRules rules;

  setUp(() {
    database = InMemoryScheduleDatabase(
      sections: const [days, nights],
      rows: const [dayNurse, nightNurse],
    );
    rules = ScheduleRules.inMemory(database, actingAs: 'manager');
  });

  int at(String html, String text) {
    final index = html.indexOf(text);
    expect(index, isNonNegative, reason: 'missing "$text"');
    return index;
  }

  test('the page has the book heading, title and legend in order', () async {
    final html = bookPageHtml(await rules.monthGrid(september));

    final heading = at(html, 'Schedule subject to change');
    final title = at(html, 'SEPTEMBER 2026</h1>');
    final firstSection = at(html, 'State dayshift RN');
    final legend = at(html, 'class="legend"');
    expect(heading < title && title < firstSection, isTrue);
    expect(firstSection < legend, isTrue);
    for (final entry in shiftLegend) {
      expect(html.substring(legend), contains(entry.code));
    }
    expect(html.substring(legend), contains('7A–7P'));
    expect(html.substring(legend), contains('Sick leave'));
  });

  test('default title matches the paper page for each month', () async {
    final septemberPage = bookPageHtml(await rules.monthGrid(september));
    final octoberPage = bookPageHtml(await rules.monthGrid(october));
    expect(
      septemberPage,
      contains(
        'Welch Community Hospital - Emergency Room Schedule - SEPTEMBER 2026</h1>',
      ),
    );
    expect(
      octoberPage,
      contains(
        'Welch Community Hospital - Emergency Room Schedule - OCTOBER 2026</h1>',
      ),
    );
  });

  test('custom title and empty notice appear on the printed page', () async {
    final html = bookPageHtml(
      await rules.monthGrid(september),
      wording: const PrintWording(title: 'ER <Schedule>', notice: ''),
    );
    expect(html, contains('<h1>ER &lt;Schedule&gt; - SEPTEMBER 2026</h1>'));
    expect(html, isNot(contains('Schedule subject to change')));
  });

  test('Sections band their staff rows in order', () async {
    final html = bookPageHtml(await rules.monthGrid(september));

    final daySection = at(html, '>State dayshift RN<');
    final dayRow = at(html, '>Day RN<');
    final nightSection = at(html, '>PRN nightshift RN<');
    final nightRow = at(html, '>Night RN<');
    expect(daySection < dayRow, isTrue);
    expect(dayRow < nightSection, isTrue);
    expect(nightSection < nightRow, isTrue);
  });

  test('every day has its weekday letter; weekends are shaded', () async {
    final html = bookPageHtml(await rules.monthGrid(september));

    // September 2026 starts on a Tuesday and has 30 days.
    expect(
      html,
      contains(
        '<th class="day">T</th><th class="day">W</th><th class="day">T</th>'
        '<th class="day">F</th><th class="day weekend">S</th>'
        '<th class="day weekend">S</th><th class="day">M</th>',
      ),
    );
    expect(
      RegExp('<th class="day[^"]*">\\d+</th>').allMatches(html).length,
      30,
    );
    // Four Saturdays and four Sundays in each of the two staff rows.
    expect(RegExp('<td class="code weekend">').allMatches(html).length, 16);
  });

  test(
    'cells show the live Shift code, unannounced changes included',
    () async {
      await rules.saveCell(
        SaveCell(
          staffMemberId: 'rn-1',
          sectionId: 'days',
          date: DateTime(2026, 9, 18),
          shiftCode: '16D',
        ),
      );

      final html = bookPageHtml(await rules.monthGrid(september));

      expect(html, contains('<td class="code">16D</td>'));
    },
  );

  test('prints landscape on one page', () async {
    final html = bookPageHtml(await rules.monthGrid(september));

    expect(html, contains('size: landscape'));
    expect(html, contains('print-color-adjust: exact'));
  });

  test('a large Staff list fits within the shortest printable page', () async {
    final crowded = InMemoryScheduleDatabase(
      sections: const [days],
      rows: [
        for (var index = 0; index < 160; index++)
          ScheduleRow(
            staffMemberId: 'rn-$index',
            displayName: 'RN $index',
            sectionId: 'days',
          ),
      ],
    );
    final shortGrid = await rules.monthGrid(september);
    final longGrid = await ScheduleRules.inMemory(
      crowded,
      actingAs: 'manager',
    ).monthGrid(september);
    final short = bookPageHtml(shortGrid);
    final long = bookPageHtml(longGrid);

    double scale(String html) => double.parse(
      RegExp(r'--initial-scale: ([\d.]+)').firstMatch(html)!.group(1)!,
    );
    expect(scale(long), lessThan(scale(short)));
    // The rows alone stay within the fallback height; heading and legend
    // reserve additional space in the scale calculation.
    expect(163 * 12 * scale(long), lessThanOrEqualTo(bookPageBodyHeightPt));
    expect(long, contains('height: 100vh'));
    expect(long, contains('beforeprint'));
    expect(bookPageIsHardToRead(shortGrid), isFalse);
    expect(bookPageIsHardToRead(longGrid), isTrue);
  });

  test('the longest title is priced into the readable fit budget', () async {
    final grid = await ScheduleRules.inMemory(
      InMemoryScheduleDatabase(
        sections: const [days],
        rows: [
          for (var index = 0; index < 50; index++)
            ScheduleRow(
              staffMemberId: 'rn-$index',
              displayName: 'RN $index',
              sectionId: 'days',
            ),
        ],
      ),
      actingAs: 'manager',
    ).monthGrid(september);
    const longTitle = PrintWording(
      title: 'A very long Schedule title for the emergency department and every member of staf',
    );

    expect(longTitle.title.length, 80);
    expect(bookPageIsHardToRead(grid), isFalse);
    expect(bookPageIsHardToRead(grid, wording: longTitle), isTrue);
    final html = bookPageHtml(grid, wording: longTitle);
    expect(html, contains('beforeprint'));
    expect(html, contains('A very long Schedule title'));
  });

  test('an 80-character title remains readable on a small month', () async {
    final wording = PrintWording(title: 'x' * 80);
    final grid = await rules.monthGrid(september);
    expect(bookPageIsHardToRead(grid, wording: wording), isFalse);
    final html = bookPageHtml(grid, wording: wording);
    final scale = double.parse(
      RegExp(r'--initial-scale: ([\d.]+)').firstMatch(html)!.group(1)!,
    );
    expect(scale * 9, greaterThanOrEqualTo(6));
  });

  test('a large legend contributes to the small print warning', () async {
    final grid = await ScheduleRules.inMemory(
      InMemoryScheduleDatabase(
        sections: const [days],
        rows: [
          for (var index = 0; index < 45; index++)
            ScheduleRow(
              staffMemberId: 'rn-$index',
              displayName: 'RN $index',
              sectionId: 'days',
            ),
        ],
      ),
      actingAs: 'manager',
    ).monthGrid(september);
    final largeLegend = [
      for (var index = 0; index < 40; index++)
        LegendCode('C$index', meaning: 'M' * shiftMeaningLimit),
    ];

    expect(bookPageIsHardToRead(grid), isFalse);
    expect(bookPageIsHardToRead(grid, codes: largeLegend), isTrue);
    final normal = bookPageHtml(grid);
    final large = bookPageHtml(grid, codes: largeLegend);
    double scale(String html) => double.parse(
      RegExp(r'--initial-scale: ([\d.]+)').firstMatch(html)!.group(1)!,
    );
    expect(scale(large), lessThan(scale(normal)));
  });

  test('bounded printed fields remain readable in a normal month', () async {
    final fullName = 'N' * staffNameLimit;
    final fullSection = 'S' * sectionNameLimit;
    final boundedRules = ScheduleRules.inMemory(
      InMemoryScheduleDatabase(
        sections: [ScheduleSection(id: 'full', name: fullSection)],
        rows: [
          for (var index = 0; index < 30; index++)
            ScheduleRow(
              staffMemberId: 'rn-$index',
              displayName: fullName,
              sectionId: 'full',
            ),
        ],
      ),
      actingAs: 'manager',
    );
    await boundedRules.saveCell(
      SaveCell(
        staffMemberId: 'rn-0',
        sectionId: 'full',
        date: DateTime(2026, 9, 1),
        shiftCode: 'C0000000',
      ),
    );
    final grid = await boundedRules.monthGrid(september);
    final codes = [
      for (var index = 0; index < 14; index++)
        LegendCode(
          'C${index.toString().padLeft(7, '0')}',
          meaning: 'M' * shiftMeaningLimit,
        ),
    ];

    final wording = PrintWording(
      title: 'T' * 80,
      notice: 'N' * 80,
    );
    expect(bookPageIsHardToRead(grid, codes: codes, wording: wording), isFalse);
    final html = bookPageHtml(grid, codes: codes, wording: wording);
    expect(html, contains(fullSection));
    expect(html, contains(fullName));
    expect(html, contains('M' * shiftMeaningLimit));
    expect(html, contains('<td class="code">C0000000</td>'));
  });

  test('names and codes are escaped', () async {
    final odd = InMemoryScheduleDatabase(
      sections: const [ScheduleSection(id: 'days', name: 'CNA & <techs>')],
      rows: const [
        ScheduleRow(
          staffMemberId: 'rn-1',
          displayName: "O'Brien <b>",
          sectionId: 'days',
        ),
      ],
    );

    final html = bookPageHtml(
      await ScheduleRules.inMemory(
        odd,
        actingAs: 'manager',
      ).monthGrid(september),
    );

    expect(html, contains('CNA &amp; &lt;techs&gt;'));
    expect(html, contains('O&#39;Brien &lt;b&gt;'));
    expect(html, isNot(contains('<b>')));
  });

  test('each person appears in the Section they are in that month', () async {
    database.moveToSection('rn-1', 'nights', from: october);

    final septemberPage = bookPageHtml(await rules.monthGrid(september));
    final octoberPage = bookPageHtml(await rules.monthGrid(october));

    expect(
      at(septemberPage, '>Day RN<'),
      lessThan(at(septemberPage, '>PRN nightshift RN<')),
    );
    expect(
      at(octoberPage, '>Day RN<'),
      greaterThan(at(octoberPage, '>PRN nightshift RN<')),
    );
  });
}
