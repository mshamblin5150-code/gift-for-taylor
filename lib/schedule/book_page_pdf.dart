import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:schedule_rules/schedule_rules.dart';

/// Builds the phone book page as a PDF with a landscape media box. Safari's
/// HTML print path can ignore @page orientation and omit transformed borders.
Future<Uint8List> bookPagePdf(
  MonthGrid grid, {
  PrintWording wording = const PrintWording(),
  Iterable<LegendCode> codes = shiftLegend,
}) async {
  final document = pw.Document();
  final days = grid.days;
  const pageWidth = 792.0;
  const pageHeight = 612.0;
  const margin = 18.0;
  const contentWidth = pageWidth - 2 * margin;
  const nameWidth = 150.0;
  final dayWidth = (contentWidth - nameWidth) / days.length;
  final entries = codes.toList();
  final rowCount = 2 + grid.sections.length + grid.rows.length;
  // Leave room for the heading and wrapped legend on a single Letter sheet.
  final legendLines = (entries.length / 5).ceil();
  final availableGridHeight =
      pageHeight - 2 * margin - 42 - 12 * legendLines - 8;
  final rowHeight = (availableGridHeight / rowCount).clamp(0.5, 12.0);
  final fontSize = (rowHeight * 0.7).clamp(0.35, 9.0);
  const rule = pw.BorderSide(width: 1.5, color: PdfColors.black);

  pw.Widget cell(
    String value,
    double width, {
    bool weekend = false,
    bool name = false,
  }) => pw.Container(
    width: width,
    height: rowHeight,
    padding: const pw.EdgeInsets.symmetric(horizontal: 1),
    decoration: pw.BoxDecoration(
      color: weekend ? const PdfColor.fromInt(0xffd0d0d0) : null,
      border: const pw.Border(right: rule, bottom: rule),
    ),
    alignment: name ? pw.Alignment.centerLeft : pw.Alignment.center,
    child: value.isEmpty
        ? pw.SizedBox()
        : pw.FittedBox(
            fit: pw.BoxFit.scaleDown,
            child: pw.Text(
              value,
              maxLines: 1,
              style: pw.TextStyle(
                fontSize: fontSize,
                fontWeight: name ? pw.FontWeight.normal : pw.FontWeight.bold,
              ),
            ),
          ),
  );

  pw.Widget header(bool dates) => pw.Row(
    children: [
      cell('', nameWidth),
      for (final day in days)
        cell(
          dates ? '${day.day}' : 'MTWTFSS'[day.weekday - 1],
          dayWidth,
          weekend: day.weekday >= DateTime.saturday,
        ),
    ],
  );

  final gridRows = <pw.Widget>[header(false), header(true)];
  for (final section in grid.sections) {
    gridRows.add(
      pw.Container(
        width: contentWidth,
        height: rowHeight,
        padding: const pw.EdgeInsets.only(left: 2),
        alignment: pw.Alignment.centerLeft,
        decoration: const pw.BoxDecoration(
          color: PdfColor.fromInt(0xff9fc5cc),
          border: pw.Border(right: rule, bottom: rule),
        ),
        child: pw.Text(
          section.name,
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
    );
    for (final row in grid.rowsIn(section.id)) {
      gridRows.add(
        pw.Row(
          children: [
            cell(row.displayName, nameWidth, name: true),
            for (final day in days)
              cell(
                grid.shiftCodeFor(row.staffMemberId, day) ?? '',
                dayWidth,
                weekend: day.weekday >= DateTime.saturday,
              ),
          ],
        ),
      );
    }
  }

  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.letter.landscape,
      margin: const pw.EdgeInsets.all(margin),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (wording.notice.isNotEmpty)
            pw.Center(
              child: pw.Text(
                wording.notice,
                style: const pw.TextStyle(
                  fontSize: 9,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
            ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              child: pw.Text(
                wording.titleFor(grid.month),
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: rule, left: rule),
            ),
            child: pw.Column(children: gridRows),
          ),
          pw.SizedBox(height: 4),
          for (var offset = 0; offset < entries.length; offset += 5)
            pw.SizedBox(
              height: 12,
              child: pw.Row(
                children: [
                  for (final entry in entries.skip(offset).take(5))
                    pw.SizedBox(
                      width: contentWidth / 5,
                      child: pw.FittedBox(
                        fit: pw.BoxFit.scaleDown,
                        alignment: pw.Alignment.centerLeft,
                        child: pw.Text(
                          '${entry.code}: ${(entry.hours ?? entry.meaning ?? '').replaceAll('–', '-')}',
                          style: const pw.TextStyle(fontSize: 8),
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
