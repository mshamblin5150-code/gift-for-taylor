export 'phone_contacts.dart'
    show PhoneContacts, PickedContact, BrowserPhoneContacts;

/// Use one phone representation for typed, picked and exported numbers.
String normalizeCellNumber(String input) {
  final value = input.trim();
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length == 7 || digits.length == 10) return '+1$digits';
  if ((digits.length == 8 || digits.length == 11) && digits.startsWith('1')) {
    return '+$digits';
  }
  if (value.startsWith('+') &&
      digits.length >= 7 &&
      digits.length <= 15 &&
      !digits.startsWith('0')) {
    return '+$digits';
  }
  throw const FormatException('Enter a cell number with its area code.');
}

String staffVCard(String name, String cellNumber) {
  String escape(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\n', '\\n')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,');

  String phone;
  try {
    phone = normalizeCellNumber(cellNumber);
  } on FormatException {
    // Preserve old imported numbers that lack enough information to normalize.
    phone = cellNumber.trim();
  }

  return 'BEGIN:VCARD\r\nVERSION:3.0\r\n'
      'FN:${escape(name)}\r\n'
      'TEL;TYPE=CELL:${escape(phone)}\r\n'
      'ORG:ER Schedule\r\nEND:VCARD\r\n';
}
