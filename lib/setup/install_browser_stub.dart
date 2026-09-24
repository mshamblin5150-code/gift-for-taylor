import 'install_state.dart';

InstallState installState() => InstallState.unavailable;
Future<InstallPromptResult> promptInstall() async =>
    InstallPromptResult.unavailable;
