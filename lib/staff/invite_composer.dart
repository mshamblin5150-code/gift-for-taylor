import 'staff_gateway.dart';
import 'sms_launcher.dart';

abstract interface class InviteComposer {
  Future<void> open(StaffInvite invite);
}

final class SmsInviteComposer implements InviteComposer {
  SmsInviteComposer(this._appUri);

  final Uri _appUri;

  @override
  Future<void> open(StaffInvite invite) {
    final inviteUri = _appUri.replace(
      queryParameters: {'invite': invite.token},
      fragment: '',
    );
    final smsUri = Uri(
      scheme: 'sms',
      path: invite.cellNumber,
      queryParameters: {
        'body': 'You have an Invite to the ER Schedule: $inviteUri',
      },
    );
    return openSmsUrl(smsUri);
  }
}
