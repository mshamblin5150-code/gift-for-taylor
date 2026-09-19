import 'package:flutter/material.dart';

import 'phone_contacts.dart';

/// The browser does not identify which of a contact's numbers is a cell.
/// Let the Manager select one if the contact shares several.
Future<(String, String)?> chooseContactNumber(
  BuildContext context,
  PhoneContacts contacts,
) async {
  // This must be the first asynchronous browser call after the button tap.
  final picked = await contacts.pick();
  if (picked == null || !context.mounted) return null;
  if (picked.numbers.isEmpty) {
    throw const FormatException('This contact has no phone number.');
  }
  if (picked.numbers.length == 1) {
    return (picked.name, picked.numbers.single);
  }
  final number = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Which cell number?'),
      children: [
        for (final number in picked.numbers)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, number),
            child: Text(number),
          ),
      ],
    ),
  );
  return number == null ? null : (picked.name, number);
}
