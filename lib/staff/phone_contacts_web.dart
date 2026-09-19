import 'dart:convert';
import 'dart:js_interop';

import 'staff_contacts.dart';

@JS('erCanPickContact')
external JSBoolean _canPickContact();

@JS('erPickContact')
external JSPromise<JSString?> _pickContact();

@JS('erSaveContact')
external void _saveContact(JSString vCard);

bool canPickContact() => _canPickContact().toDart;

Future<PickedContact?> pickContact() async {
  // Call the browser API before the first await: it requires a user gesture.
  final result = await _pickContact().toDart;
  if (result == null) return null;
  final contact = jsonDecode(result.toDart) as Map<String, dynamic>;
  return PickedContact(
    name: contact['name'] as String,
    numbers: (contact['numbers'] as List<dynamic>).cast<String>(),
  );
}

void saveContact(String name, String cellNumber) =>
    _saveContact(staffVCard(name, cellNumber).toJS);
