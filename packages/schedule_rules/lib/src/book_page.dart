import '../schedule_rules.dart';

/// Conservative fallback height for the entire Schedule on the shorter of
/// Letter and A4 landscape pages. The browser measures its actual print page
/// before printing, including a portrait page when landscape is ignored.
const bookPageBodyHeightPt = 470.0;

const _rowHeightPt = 12.0;
const _headingHeightPt = 30.0;
const _legendWidthPt = 576.0; // Portrait fallback at Letter width.
// An 8pt glyph can be nearly 8pt wide (for example M or W). Using the widest
// allowed glyph keeps the warning ahead of the browser's actual flex wrap.
const _legendCharacterWidthPt = 8.0;
const _legendLineHeightPt = 11.0; // 8pt type plus the 2pt flex gap.
// Warn early: the final size also depends on the browser's page and legend wrap.
const _minimumReadableFontPt = 6.0;
const _fontSizePt = 9.0;

double _legendHeightPt(Iterable<LegendCode> codes) {
  var lines = 0;
  var used = 0.0;
  for (final entry in codes) {
    final detail = entry.hours ?? entry.meaning ?? '';
    final width =
        ((entry.code.runes.length + detail.runes.length + 1) *
                _legendCharacterWidthPt)
            .clamp(0.0, _legendWidthPt);
    if (lines == 0 || used + 12 + width > _legendWidthPt) {
      lines++;
      used = width;
    } else {
      used += 12 + width;
    }
  }
  return lines == 0 ? 0 : 4 + lines * _legendLineHeightPt;
}

double _initialScale(
  MonthGrid grid,
  PrintWording wording,
  Iterable<LegendCode> codes,
) {
  final lines = grid.sections.length + grid.rows.length + 2;
  // Allow for a second heading line on a portrait fallback. At 14pt Arial,
  // roughly seven points per character is a conservative width estimate.
  const portraitHeadingWidthPt = 576.0;
  final headingLines =
      (wording.titleFor(grid.month).length * 7 / portraitHeadingWidthPt).ceil();
  final height =
      lines * _rowHeightPt +
      _headingHeightPt +
      _legendHeightPt(codes) +
      (headingLines - 1).clamp(0, 1) * 18;
  final scale = (bookPageBodyHeightPt / height).clamp(0.0, 1.0);
  // Rounding down preserves the fallback height bound in the emitted CSS.
  return (scale * 1000000).floor() / 1000000;
}

/// A conservative warning that one-page printing may make text very small.
bool bookPageIsHardToRead(
  MonthGrid grid, {
  PrintWording wording = const PrintWording(),
  Iterable<LegendCode> codes = shiftLegend,
}) =>
    _fontSizePt * _initialScale(grid, wording, codes) < _minimumReadableFontPt;

/// Defaults for the unit-wide print wording.
enum PrintTooltipStyle {
  bookPage(defaultLabel);

  const PrintTooltipStyle(this.label);
  static const defaultLabel = 'Print the book page';
  final String label;
}

enum PrintTitleStyle {
  hospital(defaultLabel);

  const PrintTitleStyle(this.label);
  static const defaultLabel =
      'Welch Community Hospital - Emergency Room Schedule';
  final String label;
}

enum PrintNoticeStyle {
  subjectToChange(defaultLabel);

  const PrintNoticeStyle(this.label);
  static const defaultLabel = 'Schedule subject to change';
  final String label;
}

final class PrintWording {
  const PrintWording({
    this.tooltip = PrintTooltipStyle.defaultLabel,
    this.title = PrintTitleStyle.defaultLabel,
    this.notice = PrintNoticeStyle.defaultLabel,
  });

  final String tooltip;
  final String title;
  final String notice;

  String titleFor(DateTime month) {
    final monthName = _monthNames[month.month - 1].toUpperCase();
    return '$title - $monthName ${month.year}';
  }
}

/// The Schedule book page for [grid] as a standalone HTML document: "Schedule
/// subject to change," the title with the month, Section bands, staff rows,
/// weekday letters, shaded weekends and the legend, fitted to one page in the
/// orientation the browser prints. It carries no screen chrome.
String bookPageHtml(
  MonthGrid grid, {
  Iterable<LegendCode> codes = shiftLegend,
  PrintWording wording = const PrintWording(),
}) {
  final days = grid.days;
  final title = wording.titleFor(grid.month);
  final initialScale = _initialScale(grid, wording, codes);
  final dayCount = days.length;

  final html = StringBuffer()
    ..writeln('<!DOCTYPE html>')
    ..writeln('<html lang="en">')
    ..writeln('<head>')
    ..writeln('<meta charset="utf-8">')
    ..writeln('<title>${_escape(title)}</title>')
    ..writeln('<style>')
    ..writeln(_styles(initialScale: initialScale))
    ..writeln('</style>')
    ..writeln('</head>')
    ..writeln('<body>')
    ..writeln('<div class="page"><div class="sheet">')
    ..writeln(
      wording.notice.isEmpty
          ? ''
          : '<p class="notice">${_escape(wording.notice)}</p>',
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
    ..writeln('</div></div>')
    ..writeln(_fitScript)
    ..writeln('</body>')
    ..writeln('</html>');
  return html.toString();
}

String _styles({required double initialScale}) {
  return '''
@page { size: landscape; margin: 0.25in; }
:root { --initial-scale: $initialScale; }
* { box-sizing: border-box; }
html { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
body { margin: 0; padding: 12px; font-family: Arial, Helvetica, sans-serif; color: #000; background: #fff; }
.page { position: relative; width: 100vw; height: 100vh; overflow: hidden; }
.sheet { position: absolute; top: 0; left: 0; width: ${(100 / initialScale).toStringAsFixed(4)}%; transform: scale(var(--initial-scale)); transform-origin: top left; }
.notice { margin: 0; font-size: 9pt; font-style: italic; text-align: center; }
h1 { margin: 2pt 0 4pt; font-size: 14pt; text-align: center; }
table { width: 100%; table-layout: fixed; border-collapse: collapse; }
col.name { width: 20%; }
th, td { height: 12pt; padding: 0 1pt; border: 0.5pt solid #000; font-size: 9pt; line-height: 1; text-align: center; white-space: nowrap; overflow: hidden; }
th.name { text-align: left; font-weight: normal; text-overflow: ellipsis; }
thead th { font-weight: bold; }
.weekend { background: #d0d0d0; }
tr.section th { background: #9fc5cc; text-align: left; font-weight: bold; }
td.code { font-weight: bold; }
tr { break-inside: avoid; }
.legend { margin: 4pt 0 0; font-size: 8pt; display: flex; flex-wrap: wrap; gap: 2pt 12pt; }
@media print { body { padding: 0; } }''';
}

const _fitScript = '''
<script>
function fitCellText() {
  for (const cell of document.querySelectorAll('tbody th.name, td.code')) {
    if (!cell.textContent.trim()) continue;
    let label = cell.querySelector('.fitted-text');
    if (!label) {
      label = document.createElement('span');
      label.className = 'fitted-text';
      label.textContent = cell.textContent;
      cell.replaceChildren(label);
      // Keep the table cell unpositioned: positioned cells can paint over
      // shared borders in a collapsed table when their background is shaded.
      cell.style.textAlign = 'left';
      label.style.display = 'inline-block';
      label.style.position = 'relative';
      label.style.width = 'max-content';
      label.style.whiteSpace = 'nowrap';
      label.style.transformOrigin = 'left center';
    }
    label.style.transform = 'none';
    const available = cell.clientWidth - 2;
    const width = label.scrollWidth;
    const ratio = width > available && available > 0 ? available / width : 1;
    label.style.left = cell.matches('th.name') ? '1px' :
      ((cell.clientWidth - width * ratio) / 2) + 'px';
    label.style.transform = 'scaleX(' + ratio + ')';
  }
}
function fitBookPage() {
  const page = document.querySelector('.page');
  const sheet = document.querySelector('.sheet');
  if (!page.clientWidth || !page.clientHeight) return;
  sheet.style.transform = 'none';
  let low = 0;
  let high = 1;
  // The sheet expands before scaling, keeping every day column on the page.
  // Measure the heading, table and wrapped legend together at each width.
  for (let i = 0; i < 18; i++) {
    const scale = (low + high) / 2;
    sheet.style.width = (100 / scale) + '%';
    if (sheet.scrollHeight * scale <= page.clientHeight - 2 &&
        sheet.scrollWidth * scale <= page.clientWidth + 1) {
      low = scale;
    } else {
      high = scale;
    }
  }
  const scale = Math.max(low, 0.000001);
  sheet.style.width = (100 / scale) + '%';
  sheet.style.transform = 'scale(' + scale + ')';
  fitCellText();
}
window.addEventListener('beforeprint', fitBookPage);
const printMedia = window.matchMedia('print');
const onPrintMediaChange = event => {
  if (event.matches) fitBookPage();
};
if (printMedia.addEventListener) {
  printMedia.addEventListener('change', onPrintMediaChange);
} else {
  printMedia.addListener(onPrintMediaChange);
}
fitCellText();
</script>''';

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
