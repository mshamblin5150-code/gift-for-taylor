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
  const inviteUrl = 'https://example.invalid/schedule?invite=sample-token';
  const body =
      'You have an Invite to the ER Schedule. Open this link, give your cell '
      'number and your email, and Taylor will confirm it is you. You can use '
      'ER Schedule on a computer afterwards too.\n\n'
      '$inviteUrl';

  test('iPhone Invite draft has readable text and a complete link', () {
    final uri = inviteSmsUri(appUri, invite, isIos: true);

    expect(uri.toString(), startsWith('sms:+15550100100&body='));
    expect(uri.toString(), isNot(contains('You+have')));
    expect(uri.toString(), contains('%0A%0A'));
    final decodedBody = smsBody(uri);
    expect(decodedBody, body);
    expect(decodedBody, endsWith(inviteUrl));
  });

  test('other phones receive the same Invite text and link', () {
    final uri = inviteSmsUri(appUri, invite, isIos: false);

    expect(uri.toString(), startsWith('sms:+15550100100?body='));
    final decodedBody = smsBody(uri);
    expect(decodedBody, body);
    expect(decodedBody, endsWith(inviteUrl));
  });
}

String smsBody(Uri uri) =>
    Uri.decodeComponent(uri.toString().split('body=').last);
