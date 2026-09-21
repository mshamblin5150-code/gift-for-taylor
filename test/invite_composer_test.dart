import 'package:er_schedule/staff/invite_composer.dart';
import 'package:er_schedule/staff/staff_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const invite = StaffInvite(
    staffMemberId: 'staff-1',
    cellNumber: '+15550100100',
    token: 'sample-token',
  );
  final appUri = Uri.parse('https://example.invalid/schedule?old=1#section');
  const body =
      'You have an Invite to the ER Schedule: '
      'https://example.invalid/schedule?invite=sample-token '
      'After confirmation, you can use ER Schedule on a computer too.';

  test('iPhone Invite draft has readable text and a complete link', () {
    final uri = inviteSmsUri(appUri, invite, isIos: true);

    expect(uri.toString(), startsWith('sms:+15550100100&body='));
    expect(uri.toString(), isNot(contains('You+have')));
    expect(Uri.decodeComponent(uri.toString().split('&body=').last), body);
  });

  test('other phones receive the same Invite text and link', () {
    final uri = inviteSmsUri(appUri, invite, isIos: false);

    expect(uri.toString(), startsWith('sms:+15550100100?body='));
    expect(Uri.decodeComponent(uri.toString().split('?body=').last), body);
  });
}
