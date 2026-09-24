import 'dart:js_interop';

import 'install_state.dart';

@JS('erInstallState')
external JSString _installState();

@JS('erPromptInstall')
external JSPromise<JSString> _promptInstall();

InstallState installState() => switch (_installState().toDart) {
  'installed' => InstallState.installed,
  'available' => InstallState.available,
  _ => InstallState.unavailable,
};
Future<InstallPromptResult> promptInstall() async =>
    installPromptResultFromBrowser((await _promptInstall().toDart).toDart);
