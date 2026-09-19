import 'dart:convert';

/// The first month as transcribed from the printed book page: a CSV with a
/// `Section,Name,Cell,1,2,…` header and one row per person in page order. The
/// cell number is what their Invite is texted to; it may be left blank.
///
/// Transcripts hold real staff names. Keep them in the gitignored `private/`
/// folder; never commit them or post them to the tracker.
final class FirstMonthTranscript {
  FirstMonthTranscript._(this.month, this.rows);

  factory FirstMonthTranscript.parseCsv(
    String csv, {
    required DateTime month,
  }) {
    final firstDay = DateTime(month.year, month.month);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final lines = _parseCsv(csv);
    if (lines.isEmpty) {
      throw const TranscriptFormatException('The transcript is empty');
    }

    final header = lines.first.fields.map((field) => field.trim()).toList();
    final expectedHeader = [
      'Section',
      'Name',
      'Cell',
      for (var day = 1; day <= days; day++) '$day',
    ];
    if (header.join(',') != expectedHeader.join(',')) {
      throw TranscriptFormatException(
        'The header must be Section,Name,Cell,1…$days for this month',
      );
    }

    final rows = <TranscribedRow>[];
    for (final line in lines.skip(1)) {
      if (line.fields.every((field) => field.trim().isEmpty)) continue;
      if (line.fields.length != days + 3) {
        throw TranscriptFormatException(
          'Line ${line.number} has ${line.fields.length - 3} days, not $days',
        );
      }
      final section = line.fields[0].trim();
      final name = line.fields[1].trim();
      final cellNumber = line.fields[2].trim();
      if (section.isEmpty || name.isEmpty) {
        throw TranscriptFormatException(
          'Line ${line.number} needs a Section and a name',
        );
      }
      rows.add(
        TranscribedRow(
          section: section,
          name: name,
          cellNumber: cellNumber.isEmpty ? null : cellNumber,
          codes: List.unmodifiable(
            line.fields.skip(3).map((code) => code.trim()),
          ),
        ),
      );
    }
    if (rows.isEmpty) {
      throw const TranscriptFormatException('The transcript has no rows');
    }
    return FirstMonthTranscript._(firstDay, List.unmodifiable(rows));
  }

  final DateTime month;
  final List<TranscribedRow> rows;

  /// One statement to run in the Supabase SQL editor.
  String toLoadSql() {
    const tag = r'$first_month$';
    final json = jsonEncode([
      for (final row in rows)
        {
          'section': row.section,
          'name': row.name,
          'cell': row.cellNumber,
          'codes': row.codes,
        },
    ]);
    if (json.contains(tag)) {
      throw const TranscriptFormatException(
        r'The transcript may not contain $first_month$',
      );
    }
    final monthStart =
        '${month.year.toString().padLeft(4, '0')}-'
        '${month.month.toString().padLeft(2, '0')}-01';
    return "select public.load_first_month(date '$monthStart', "
        '$tag$json$tag::jsonb);\n';
  }
}

final class TranscribedRow {
  const TranscribedRow({
    required this.section,
    required this.name,
    required this.cellNumber,
    required this.codes,
  });

  final String section;
  final String name;
  final String? cellNumber;
  final List<String> codes;
}

final class TranscriptFormatException implements Exception {
  const TranscriptFormatException(this.message);

  final String message;

  @override
  String toString() => 'TranscriptFormatException: $message';
}

final class _CsvLine {
  _CsvLine(this.number, this.fields);

  final int number;
  final List<String> fields;
}

/// RFC 4180 fields: commas separate, double quotes wrap, `""` escapes a quote.
List<_CsvLine> _parseCsv(String csv) {
  final lines = <_CsvLine>[];
  var fields = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var lineNumber = 1;
  var lineStart = 1;

  void endField() {
    fields.add(field.toString());
    field.clear();
  }

  void endLine() {
    endField();
    lines.add(_CsvLine(lineStart, fields));
    fields = <String>[];
  }

  for (var index = 0; index < csv.length; index++) {
    final char = csv[index];
    if (quoted) {
      if (char == '"') {
        if (index + 1 < csv.length && csv[index + 1] == '"') {
          field.write('"');
          index++;
        } else {
          quoted = false;
        }
      } else {
        if (char == '\n') lineNumber++;
        field.write(char);
      }
    } else if (char == '"') {
      quoted = true;
    } else if (char == ',') {
      endField();
    } else if (char == '\r' || char == '\n') {
      if (char == '\r' && index + 1 < csv.length && csv[index + 1] == '\n') {
        index++;
      }
      endLine();
      lineNumber++;
      lineStart = lineNumber;
    } else {
      field.write(char);
    }
  }
  if (field.isNotEmpty || fields.isNotEmpty) endLine();
  return lines;
}
