import 'dart:js_interop';

@JS('erInstallState')
external JSString _installState();

@JS('erPromptInstall')
external JSPromise<JSString> _promptInstall();

String installState() => _installState().toDart;
Future<void> promptInstall() async {
  await _promptInstall().toDart;
}
