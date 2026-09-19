import '../schedule_rules.dart';

/// The printable height, in points, left for the grid's rows once the
/// heading, title and legend are placed on a landscape page. It allows for
/// the shorter of Letter and A4.
const bookPageBodyHeightPt = 470.0;

const _maxRowHeightPt = 16.0;

/// Approved, unit-wide print wording. Only these choices can be persisted;
/// arbitrary text could put patient or personal details on the book page.
enum PrintTooltipStyle {
  bookPage('Print the book page'),
  schedule('Print Schedule'),
  binder('Print for the Schedule book');

  const PrintTooltipStyle(this.label);
  final String label;
}

enum PrintTitleStyle {
  hospital('Welch Community Hospital - Emergency Room Schedule'),
  emergencyRoom('Emergency Room Schedule'),
  er('ER Schedule');

  const PrintTitleStyle(this.label);
  final String label;
}

enum PrintNoticeStyle {
  subjectToChange('Schedule subject to change'),
  checkForChanges('Check for Schedule changes'),
  none('');

  const PrintNoticeStyle(this.label);
  final String label;
}

final class PrintWording {
  const PrintWording({
    this.tooltip = PrintTooltipStyle.bookPage,
    this.title = PrintTitleStyle.hospital,
    this.notice = PrintNoticeStyle.subjectToChange,
  });

  final PrintTooltipStyle tooltip;
  final PrintTitleStyle title;
  final PrintNoticeStyle notice;

  String titleFor(DateTime month) {
    final name = _monthNames[month.month - 1];
    final monthName = title == PrintTitleStyle.hospital
        ? name.toUpperCase()
        : name;
    return '${title.label} - $monthName ${month.year}';
  }
}

/// The Schedule book page for [grid] as a standalone HTML document: "Schedule
/// subject to change," the title with the month, Section bands, staff rows,
/// weekday letters, shaded weekends and the legend, fitted to one landscape
/// page. It carries no screen chrome.
String bookPageHtml(
  MonthGrid grid, {
  Iterable<LegendCode> codes = shiftLegend,
  PrintWording wording = const PrintWording(),
}) {
  final days = grid.days;
  final title = wording.titleFor(grid.month);
  final lines = grid.sections.length + grid.rows.length + 2;
  final rowHeight = (bookPageBodyHeightPt / lines).clamp(0.0, _maxRowHeightPt);
  final fontSize = (rowHeight * 0.7).clamp(4.0, 9.0);
  final dayCount = days.length;

  final html = StringBuffer()
    ..writeln('<!DOCTYPE html>')
    ..writeln('<html lang="en">')
    ..writeln('<head>')
    ..writeln('<meta charset="utf-8">')
    ..writeln('<title>${_escape(title)}</title>')
    ..writeln('<style>')
    ..writeln(_styles(rowHeight: rowHeight, fontSize: fontSize))
    ..writeln('</style>')
    ..writeln('</head>')
    ..writeln('<body>')
    ..writeln(
      wording.notice == PrintNoticeStyle.none
          ? ''
          : '<p class="notice">${_escape(wording.notice.label)}</p>',
    )
    ..writeln('<h1>${_escape(title)}</h1>')
    ..writeln('<table>')
    ..writeln('<colgroup><col class="name">')
    ..writeln('${'<col>' * dayCount}</colgroup>')
    ..writeln('<thead>')
    ..write('<tr><th class="name"></th>');
  for (final day in days) {
    html.write('<th class="${_dayClass(day)}">${_weekdayLetter(day)}</th>');
  }
  html
    ..writeln('</tr>')
    ..write('<tr><th class="name"></th>');
  for (final day in days) {
    html.write('<th class="${_dayClass(day)}">${day.day}</th>');
  }
  html
    ..writeln('</tr>')
    ..writeln('</thead>')
    ..writeln('<tbody>');

  for (final section in grid.sections) {
    html.writeln(
      '<tr class="section"><th colspan="${dayCount + 1}">'
      '${_escape(section.name)}</th></tr>',
    );
    for (final row in grid.rowsIn(section.id)) {
      html.write('<tr><th class="name">${_escape(row.displayName)}</th>');
      for (final day in days) {
        final code = grid.shiftCodeFor(row.staffMemberId, day) ?? '';
        html.write(
          '<td class="${_isWeekend(day) ? 'code weekend' : 'code'}">'
          '${_escape(code)}</td>',
        );
      }
      html.writeln('</tr>');
    }
  }

  html
    ..writeln('</tbody>')
    ..writeln('</table>')
    ..write('<p class="legend">');
  for (final entry in codes) {
    final detail = entry.hours ?? entry.meaning;
    html.write(
      '<span><strong>${_escape(entry.code)}</strong>'
      '${detail == null ? '' : ' ${_escape(detail)}'}</span>',
    );
  }
  html
    ..writeln('</p>')
    ..writeln('</body>')
    ..writeln('</html>');
  return html.toString();
}

String _styles({required double rowHeight, required double fontSize}) {
  String pt(double value) => '${value.toStringAsFixed(2)}pt';
  return '''
@page { size: landscape; margin: 0.25in; }
:root { --row-height: ${pt(rowHeight)}; --font-size: ${pt(fontSize)}; }
* { box-sizing: border-box; }
html { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
body { margin: 0; padding: 12px; font-family: Arial, Helvetica, sans-serif; color: #000; background: #fff; }
.notice { margin: 0; font-size: 9pt; font-style: italic; text-align: center; }
h1 { margin: 2pt 0 4pt; font-size: 14pt; text-align: center; }
table { width: 100%; table-layout: fixed; border-collapse: collapse; }
col.name { width: 12%; }
th, td { height: var(--row-height); padding: 0 1pt; border: 0.5pt solid #000; font-size: var(--font-size); line-height: 1; text-align: center; white-space: nowrap; overflow: hidden; }
th.name { text-align: left; font-weight: normal; text-overflow: ellipsis; }
thead th { font-weight: bold; }
.weekend { background: #d0d0d0; }
tr.section th { background: #9fc5cc; text-align: left; font-weight: bold; }
td.code { font-weight: bold; }
tr { break-inside: avoid; }
.legend { margin: 4pt 0 0; font-size: 8pt; display: flex; flex-wrap: wrap; gap: 2pt 12pt; }
@media print { body { padding: 0; } }''';
}

String _dayClass(DateTime day) => _isWeekend(day) ? 'day weekend' : 'day';

bool _isWeekend(DateTime day) =>
    day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

String _weekdayLetter(DateTime day) => 'MTWTFSS'[day.weekday - 1];

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
