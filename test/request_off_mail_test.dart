import 'package:er_schedule/schedule/request_off_mail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

void main() {
  test('Request off mail link preserves the exact email content', () {
    final email = RequestOffEmail.forRequest(
      requestId: 'request-1',
      to: 'manager@example.com',
      staffMemberName: 'Jane Doe',
      dates: [DateTime(2026, 10, 14)],
      reason: 'Coverage & family #1 + travel',
    );

    final uri = requestOffMailUri(email);

    expect(uri.scheme, 'mailto');
    expect(uri.path, 'manager@example.com');
    expect(uri.queryParameters['subject'], 'Request off - Jane Doe');
    expect(
      uri.queryParameters['body'],
      'Jane Doe requests off on 2026-10-14.\n'
      'Reason: Coverage & family #1 + travel',
    );
    expect(uri.toString(), isNot(contains('+')));
    expect(uri.toString(), contains('%0A'));
    expect(uri.toString(), contains('%26'));
    expect(uri.toString(), contains('%23'));
    expect(uri.toString(), contains('%2B'));
  });
}
