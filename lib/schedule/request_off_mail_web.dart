// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:schedule_rules/schedule_rules.dart';

Future<void> openRequestOffMail(RequestOffEmail email) async {
  final uri = Uri(
    scheme: 'mailto',
    path: email.to,
    queryParameters: {'subject': email.subject, 'body': email.body},
  );
  html.window.location.assign(uri.toString());
}
