// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:schedule_rules/schedule_rules.dart';

import 'request_off_mail_uri.dart';

Future<void> openRequestOffMail(RequestOffEmail email) async {
  html.window.location.assign(requestOffMailUri(email).toString());
}
