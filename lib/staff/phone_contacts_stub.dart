import 'phone_contacts.dart';

bool canPickContact() => false;
Future<PickedContact?> pickContact() async => null;
void saveContact(String name, String cellNumber) =>
    throw UnsupportedError('Saving contacts requires the web app.');
