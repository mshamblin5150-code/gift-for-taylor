// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

String ticketDeviceDescription() {
  final agent = html.window.navigator.userAgent;
  final browser = switch (agent) {
    final value when value.contains('Edg/') => 'Edge',
    final value when value.contains('CriOS') => 'Chrome',
    final value when value.contains('Chrome/') => 'Chrome',
    final value when value.contains('FxiOS') => 'Firefox',
    final value when value.contains('Firefox/') => 'Firefox',
    final value when value.contains('Safari/') => 'Safari',
    _ => 'Browser',
  };
  final platform = switch (agent.toLowerCase()) {
    final value when value.contains('iphone') => 'iPhone',
    final value when value.contains('ipad') => 'iPad',
    final value when value.contains('android') => 'Android',
    final value when value.contains('windows') => 'Windows',
    final value when value.contains('macintosh') => 'Mac',
    final value when value.contains('linux') => 'Linux',
    _ => 'device',
  };
  return '$browser on $platform';
}
