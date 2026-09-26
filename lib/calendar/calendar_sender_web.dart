import 'dart:js_interop';

@JS('erSaveContact')
external void _saveContact(JSString vCard);

void saveCalendarSender() => _saveContact(
  'BEGIN:VCARD\r\nVERSION:3.0\r\nFN:ER Schedule\r\n'
          'EMAIL;TYPE=INTERNET:no-reply@calendar.axion.healthcare\r\nEND:VCARD\r\n'
      .toJS,
);
