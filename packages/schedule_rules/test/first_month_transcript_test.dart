import 'dart:convert';

import 'package:schedule_rules/schedule_rules.dart';
import 'package:test/test.dart';

void main() {
  String februaryRow(
    String section,
    String name,
    String firstCode, {
    String cell = '5550000000',
  }) {
    return [section, name, cell, firstCode, ...List.filled(27, 'X')].join(',');
  }

  final februaryHeader = [
    'Section',
    'Name',
    'Cell',
    for (var day = 1; day <= 28; day++) '$day',
  ].join(',');

  test('reads each transcribed row with one Shift code per day', () {
    final transcript = FirstMonthTranscript.parseCsv(
      [
        februaryHeader,
        februaryRow('State dayshift RN', 'Day Nurse', '7A'),
        februaryRow(
          'PRN nightshift RN',
          '"Night, Nurse"',
          ' 4P-8A ',
          cell: ' 555-111-2222 ',
        ),
        '',
      ].join('\n'),
      month: DateTime(2027, 2),
    );

    expect(transcript.rows, hasLength(2));
    expect(transcript.rows.first.section, 'State dayshift RN');
    expect(transcript.rows.last.name, 'Night, Nurse');
    expect(transcript.rows.last.cellNumber, '555-111-2222');
    expect(transcript.rows.last.codes.first, '4P-8A');
    expect(transcript.rows.last.codes, hasLength(28));
  });

  test('keeps a blank cell and a missing cell number blank', () {
    final transcript = FirstMonthTranscript.parseCsv(
      '$februaryHeader\r\n${februaryRow('CNA', 'Aide', '', cell: '')}\r\n',
      month: DateTime(2027, 2),
    );

    expect(transcript.rows.single.codes.first, '');
    expect(transcript.rows.single.cellNumber, isNull);
  });

  test('refuses a header that does not match the days of the month', () {
    expect(
      () => FirstMonthTranscript.parseCsv(
        'Section,Name,Cell,1,2,3\n',
        month: DateTime(2027, 2),
      ),
      throwsA(isA<TranscriptFormatException>()),
    );
  });

  test('refuses a row with a missing day and names its line', () {
    expect(
      () => FirstMonthTranscript.parseCsv(
        '$februaryHeader\nCNA,Aide,5550000000,7A,X\n',
        month: DateTime(2027, 2),
      ),
      throwsA(
        isA<TranscriptFormatException>().having(
          (error) => error.message,
          'message',
          contains('Line 2'),
        ),
      ),
    );
  });

  test('refuses a row without a name', () {
    expect(
      () => FirstMonthTranscript.parseCsv(
        '$februaryHeader\n${februaryRow('CNA', ' ', '7A')}\n',
        month: DateTime(2027, 2),
      ),
      throwsA(isA<TranscriptFormatException>()),
    );
  });

  test('writes one load statement carrying every row as JSON', () {
    final transcript = FirstMonthTranscript.parseCsv(
      '$februaryHeader\n${februaryRow('CNA', "O'Aide", 'S/L')}\n',
      month: DateTime(2027, 2),
    );

    final sql = transcript.toLoadSql();
    final json = RegExp(
      r'\$first_month\$(.*)\$first_month\$',
      dotAll: true,
    ).firstMatch(sql)!.group(1)!;

    expect(sql, startsWith("select public.load_first_month(date '2027-02-01', "));
    expect(jsonDecode(json), [
      {
        'section': 'CNA',
        'name': "O'Aide",
        'cell': '5550000000',
        'codes': ['S/L', ...List.filled(27, 'X')],
      },
    ]);
  });
}
