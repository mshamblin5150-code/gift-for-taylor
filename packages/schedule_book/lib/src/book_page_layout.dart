import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:schedule_rules/schedule_rules.dart';

import 'font_loader.dart' as loader;

const _width = 756.0;
const _margin = 18.0;
const _legendSize = 8.0;
const _legendHeight = 12.0;
const _rule = pw.BorderSide(width: 1.5, color: PdfColors.black);

/// Arimo faces supplied by the caller when file access is unavailable.
final class BookFontBytes {
  const BookFontBytes(this.regular, this.bold, this.italic);

  final ByteData regular;
  final ByteData bold;
  final ByteData italic;
}

enum SqueezedKind { name, code }

final class SqueezedItem {
  const SqueezedItem(
    this.kind,
    this.text,
    this.staffMemberId,
    this.staffName,
    this.date,
    this.horizontalScale,
    this.effectiveSize,
  );
  final SqueezedKind kind;
  final String text;
  final String staffMemberId;
  final String staffName;
  final DateTime? date;
  final double horizontalScale;
  final double effectiveSize;
}

enum LayoutCauseKind {
  wholePageScale,
  squeezedName,
  squeezedCode,
  squeezedSection,
  squeezedNotice,
}

final class LayoutCause {
  const LayoutCause(this.kind, this.effectiveSize, this.description);
  final LayoutCauseKind kind;
  final double effectiveSize;
  final String description;
}

final class LegendFragment {
  const LegendFragment(this.text, this.width);
  final String text;
  final double width;
}

/// All sizes and squeezes for the one Letter landscape PDF page.
final class BookPageLayout {
  BookPageLayout._(
    this.grid,
    this.wording,
    this._fonts,
    this.rowHeight,
    this.fontSize,
    this.nameWidth,
    this.legendLines,
    this.squeezedItems,
    this.causes,
    this.minimumEffectiveSize,
    this.titleScale,
    this.noticeScale,
    this.sectionScales,
  );

  final MonthGrid grid;
  final PrintWording wording;
  final BookFontBytes _fonts;
  final double rowHeight;
  final double fontSize;
  final double nameWidth;
  final List<List<LegendFragment>> legendLines;
  final List<SqueezedItem> squeezedItems;
  final List<LayoutCause> causes;
  final double minimumEffectiveSize;
  final double titleScale;
  final double noticeScale;
  final Map<String, double> sectionScales;

  double get dayWidth => (_width - nameWidth) / grid.days.length;
  bool get isHardToRead => minimumEffectiveSize < 6;

  double _nameScale(String id) =>
      squeezedItems
          .where(
            (item) =>
                item.kind == SqueezedKind.name && item.staffMemberId == id,
          )
          .firstOrNull
          ?.horizontalScale ??
      1;
  double _codeScale(String id, DateTime day) =>
      squeezedItems
          .where(
            (item) =>
                item.kind == SqueezedKind.code &&
                item.staffMemberId == id &&
                item.date == day,
          )
          .firstOrNull
          ?.horizontalScale ??
      1;

  Future<Uint8List> renderPdf() async {
    final document = pw.Document();
    final regular = pw.Font.ttf(_fonts.regular);
    final bold = pw.Font.ttf(_fonts.bold);
    final italic = pw.Font.ttf(_fonts.italic);

    pw.Widget squeezedText(
      String value,
      pw.Font font,
      double size,
      double scale, {
      pw.Alignment alignment = pw.Alignment.center,
    }) => pw.Transform(
      transform: _horizontalMatrix(scale),
      alignment: alignment,
      unconstrained: true,
      child: pw.Text(
        value,
        maxLines: 1,
        style: pw.TextStyle(font: font, fontSize: size),
      ),
    );

    pw.Widget cell(
      String value,
      double width, {
      bool weekend = false,
      bool name = false,
      double scale = 1,
    }) => pw.Container(
      width: width,
      height: rowHeight,
      padding: const pw.EdgeInsets.symmetric(horizontal: 1),
      decoration: pw.BoxDecoration(
        color: weekend ? const PdfColor.fromInt(0xffd0d0d0) : null,
        border: const pw.Border(right: _rule, bottom: _rule),
      ),
      alignment: name ? pw.Alignment.centerLeft : pw.Alignment.center,
      child: value.isEmpty
          ? pw.SizedBox()
          : squeezedText(
              value,
              name ? regular : bold,
              fontSize,
              scale,
              alignment: name ? pw.Alignment.centerLeft : pw.Alignment.center,
            ),
    );

    pw.Widget header(bool dates) => pw.Row(
      children: [
        cell('', nameWidth),
        for (final day in grid.days)
          cell(
            dates ? '${day.day}' : 'MTWTFSS'[day.weekday - 1],
            dayWidth,
            weekend: day.weekday >= DateTime.saturday,
          ),
      ],
    );

    final rows = <pw.Widget>[header(false), header(true)];
    for (final section in grid.sections) {
      rows.add(
        pw.Container(
          width: _width,
          height: rowHeight,
          padding: const pw.EdgeInsets.only(left: 2),
          alignment: pw.Alignment.centerLeft,
          decoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xff9fc5cc),
            border: pw.Border(right: _rule, bottom: _rule),
          ),
          child: squeezedText(
            section.name,
            bold,
            fontSize,
            sectionScales[section.id] ?? 1,
            alignment: pw.Alignment.centerLeft,
          ),
        ),
      );
      for (final row in grid.rowsIn(section.id)) {
        rows.add(
          pw.Row(
            children: [
              cell(
                row.displayName,
                nameWidth,
                name: true,
                scale: _nameScale(row.staffMemberId),
              ),
              for (final day in grid.days)
                cell(
                  grid.shiftCodeFor(row.staffMemberId, day) ?? '',
                  dayWidth,
                  weekend: day.weekday >= DateTime.saturday,
                  scale: _codeScale(row.staffMemberId, day),
                ),
            ],
          ),
        );
      }
    }

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter.landscape,
        margin: const pw.EdgeInsets.all(_margin),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (wording.notice.isNotEmpty)
              pw.Center(
                child: squeezedText(wording.notice, italic, 9, noticeScale),
              ),
            pw.SizedBox(height: 2),
            pw.Center(
              child: squeezedText(
                wording.titleFor(grid.month),
                bold,
                14,
                titleScale,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Container(
              decoration: const pw.BoxDecoration(
                border: pw.Border(top: _rule, left: _rule),
              ),
              child: pw.Column(children: rows),
            ),
            pw.SizedBox(height: 4),
            for (final line in legendLines)
              pw.SizedBox(
                height: _legendHeight,
                child: pw.Row(
                  children: [
                    for (final part in line)
                      pw.SizedBox(
                        width: part.width,
                        child: pw.Text(
                          part.text,
                          maxLines: 1,
                          style: pw.TextStyle(
                            font: regular,
                            fontSize: _legendSize,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    return document.save();
  }
}

// pdf's public Transform supplies its Matrix4 type without a direct dependency
// on vector_math.
dynamic _horizontalMatrix(double scale) =>
    (pw.Transform.scale(scale: 1).transform)..setEntry(0, 0, scale);

/// Measures all text in bundled Arimo and returns the printable layout.
Future<BookPageLayout> prepareBookPage(
  MonthGrid grid, {
  Iterable<LegendCode> codes = shiftLegend,
  PrintWording wording = const PrintWording(),
  BookFontBytes? fontBytes,
}) async {
  final fonts = fontBytes ?? await loader.loadBookFonts();
  final metricsDocument = PdfDocument();
  final regular = PdfTtfFont(metricsDocument, fonts.regular);
  final bold = PdfTtfFont(metricsDocument, fonts.bold);
  final italic = PdfTtfFont(metricsDocument, fonts.italic);
  double measure(PdfTtfFont font, String text, double size) =>
      font.stringMetrics(text).advanceWidth * size;

  final legendLines = <List<LegendFragment>>[];
  var line = <LegendFragment>[];
  var used = 0.0;
  void flush() {
    if (line.isNotEmpty) legendLines.add(line);
    line = <LegendFragment>[];
    used = 0;
  }

  for (final entry in codes) {
    final value = '${entry.code}: ${entry.hours ?? entry.meaning ?? ''}'.trim();
    // Break between measured words, then within one unbroken overwide word.
    for (final word in value.split(RegExp(r'\s+'))) {
      var chunk = '';
      for (final rune in word.runes) {
        final next = '$chunk${String.fromCharCode(rune)}';
        if (chunk.isNotEmpty && measure(regular, next, _legendSize) > _width) {
          flush();
          final width = measure(regular, chunk, _legendSize);
          legendLines.add([LegendFragment(chunk, width)]);
          chunk = String.fromCharCode(rune);
        } else {
          chunk = next;
        }
      }
      var text = line.isEmpty ? chunk : ' $chunk';
      var width = measure(regular, text, _legendSize);
      if (line.isNotEmpty && used + width > _width) {
        flush();
        text = chunk;
        width = measure(regular, text, _legendSize);
      }
      line.add(LegendFragment(text, width));
      used += width;
    }
    final gap = measure(regular, '   ', _legendSize);
    if (used + gap <= _width) {
      line.add(LegendFragment('   ', gap));
      used += gap;
    } else {
      flush();
    }
  }
  flush();

  final rowCount = 2 + grid.sections.length + grid.rows.length;
  final available =
      612 - 2 * _margin - 42 - legendLines.length * _legendHeight - 8;
  final rowHeight = math.min(12.0, math.max(0.5, available / rowCount));
  final fontSize = math.min(9.0, math.max(0.35, rowHeight * .75));
  final longestName = grid.rows.fold<double>(
    0,
    (maxWidth, row) =>
        math.max(maxWidth, measure(regular, row.displayName, fontSize) + 2),
  );
  final nameWidth = longestName.clamp(90.0, 180.0);
  final dayWidth = (_width - nameWidth) / grid.days.length;
  final squeezed = <SqueezedItem>[];
  for (final row in grid.rows) {
    final measured = measure(regular, row.displayName, fontSize);
    if (measured > nameWidth - 2) {
      final scale = (nameWidth - 2) / measured;
      squeezed.add(
        SqueezedItem(
          SqueezedKind.name,
          row.displayName,
          row.staffMemberId,
          row.displayName,
          null,
          scale,
          fontSize * scale,
        ),
      );
    }
    for (final day in grid.days) {
      final code = grid.shiftCodeFor(row.staffMemberId, day) ?? '';
      final codeWidth = measure(bold, code, fontSize);
      if (codeWidth > dayWidth - 2) {
        final scale = (dayWidth - 2) / codeWidth;
        squeezed.add(
          SqueezedItem(
            SqueezedKind.code,
            code,
            row.staffMemberId,
            row.displayName,
            day,
            scale,
            fontSize * scale,
          ),
        );
      }
    }
  }
  final sectionScales = <String, double>{};
  for (final section in grid.sections) {
    final measured = measure(bold, section.name, fontSize);
    sectionScales[section.id] = measured > _width - 4
        ? (_width - 4) / measured
        : 1;
  }
  final titleWidth = measure(bold, wording.titleFor(grid.month), 14);
  final titleScale = titleWidth > _width ? _width / titleWidth : 1.0;
  final noticeWidth = measure(italic, wording.notice, 9);
  final noticeScale = noticeWidth > _width ? _width / noticeWidth : 1.0;
  final causes = <LayoutCause>[
    if (fontSize < 9)
      LayoutCause(
        LayoutCauseKind.wholePageScale,
        fontSize,
        '${grid.sections.length} Sections, ${grid.rows.length} Staff members, '
        '${legendLines.length} legend lines take the page height',
      ),
    for (final item in squeezed)
      LayoutCause(
        item.kind == SqueezedKind.name
            ? LayoutCauseKind.squeezedName
            : LayoutCauseKind.squeezedCode,
        item.effectiveSize,
        item.kind == SqueezedKind.name
            ? 'Name ${item.staffName} is wider than its column'
            : 'Shift code ${item.text} for ${item.staffName} on '
                  '${item.date!.year}-${item.date!.month}-${item.date!.day} '
                  'is wider than its column',
      ),
    if (titleScale < 1)
      LayoutCause(
        LayoutCauseKind.wholePageScale,
        14 * titleScale,
        'Title is wider than the page',
      ),
    if (noticeScale < 1)
      LayoutCause(
        LayoutCauseKind.squeezedNotice,
        9 * noticeScale,
        'Notice is wider than the page',
      ),
    for (final section in grid.sections)
      if (sectionScales[section.id]! < 1)
        LayoutCause(
          LayoutCauseKind.squeezedSection,
          fontSize * sectionScales[section.id]!,
          'Section ${section.name} is wider than the page',
        ),
  ]..sort((a, b) => a.effectiveSize.compareTo(b.effectiveSize));
  final minimum = [
    fontSize,
    _legendSize,
    if (wording.notice.isNotEmpty) 9 * noticeScale,
    14 * titleScale,
    ...sectionScales.values.map((s) => fontSize * s),
    ...squeezed.map((item) => item.effectiveSize),
  ].reduce(math.min);
  return BookPageLayout._(
    grid,
    wording,
    fonts,
    rowHeight,
    fontSize,
    nameWidth,
    legendLines,
    squeezed,
    causes,
    minimum,
    titleScale,
    noticeScale,
    sectionScales,
  );
}
