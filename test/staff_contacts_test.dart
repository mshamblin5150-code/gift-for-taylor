import 'package:er_schedule/staff/staff_contacts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual and picked cell numbers have the same canonical form', () {
    expect(normalizeCellNumber('(555) 867-5309'), '+15558675309');
    expect(normalizeCellNumber('1 555 867 5309'), '+15558675309');
    expect(normalizeCellNumber('+1 (555) 867-5309'), '+15558675309');
    expect(normalizeCellNumber('(555) 013-7'), '+15550137');
    expect(normalizeCellNumber('555-0137'), '+15550137');
    expect(normalizeCellNumber('+1 555 013 7'), '+15550137');
    expect(
      () => normalizeCellNumber('+0 555 013 7'),
      throwsFormatException,
    );
  });

  test('vCard escapes contact data and identifies ER Schedule', () {
    expect(
      staffVCard('Taylor, Nurse; RN', '(555) 867-5309'),
      'BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Taylor\\, Nurse\\; RN\r\n'
      'TEL;TYPE=CELL:+15558675309\r\nORG:ER Schedule\r\nEND:VCARD\r\n',
    );
  });

  test('vCard preserves a legacy short number for import', () {
    expect(
      staffVCard('Alex Tech', '555'),
      contains('TEL;TYPE=CELL:555\r\n'),
    );
  });
}
