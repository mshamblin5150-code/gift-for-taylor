import 'package:er_schedule/setup/install_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('browser install outcomes keep dismissal distinct from acceptance', () {
    expect(
      installPromptResultFromBrowser('accepted'),
      InstallPromptResult.accepted,
    );
    expect(
      installPromptResultFromBrowser('dismissed'),
      InstallPromptResult.dismissed,
    );
    expect(
      installPromptResultFromBrowser('unavailable'),
      InstallPromptResult.unavailable,
    );
  });
}
