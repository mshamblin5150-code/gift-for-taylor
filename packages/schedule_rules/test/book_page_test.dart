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

  test(
    'approved title and notice choices appear on the printed page',
    () async {
      final html = bookPageHtml(
        await rules.monthGrid(september),
        wording: const PrintWording(
          title: PrintTitleStyle.er,
          notice: PrintNoticeStyle.none,
        ),
      );
      expect(html, contains('<h1>ER Schedule - September 2026</h1>'));
      expect(html, isNot(contains('Schedule subject to change')));
    },
  );

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
    // 160 Staff rows, a Section band, two date rows, and heading/legend space.
    expect(
      (163 * 12 + 60) * scale(long),
      lessThanOrEqualTo(bookPageBodyHeightPt),
    );
    expect(long, contains('height: 100vh'));
    expect(long, contains('beforeprint'));
    expect(bookPageIsHardToRead(shortGrid), isFalse);
    expect(bookPageIsHardToRead(longGrid), isTrue);
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
