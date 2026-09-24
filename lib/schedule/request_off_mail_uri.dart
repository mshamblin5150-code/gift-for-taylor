import 'package:schedule_rules/schedule_rules.dart';

Uri requestOffMailUri(RequestOffEmail email) {
  final subject = Uri.encodeComponent(email.subject);
  final body = Uri.encodeComponent(email.body);
  return Uri.parse('mailto:${email.to}?subject=$subject&body=$body');
}
