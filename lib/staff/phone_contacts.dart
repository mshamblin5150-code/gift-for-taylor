import 'phone_contacts_stub.dart'
    if (dart.library.js_interop) 'phone_contacts_web.dart'
    as platform;

final class PickedContact {
  const PickedContact({required this.name, required this.numbers});

  final String name;
  final List<String> numbers;
}

abstract interface class PhoneContacts {
  bool get canPick;
  Future<PickedContact?> pick();
  void save(String name, String cellNumber);
}

final class BrowserPhoneContacts implements PhoneContacts {
  const BrowserPhoneContacts();

  @override
  bool get canPick => platform.canPickContact();

  @override
  Future<PickedContact?> pick() => platform.pickContact();

  @override
  void save(String name, String cellNumber) =>
      platform.saveContact(name, cellNumber);
}
