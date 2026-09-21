import 'package:flutter/foundation.dart';

import '../schedule/messages_composer.dart';
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
    return openSmsUrl(
      inviteSmsUri(
        _appUri,
        invite,
        isIos: defaultTargetPlatform == TargetPlatform.iOS,
      ),
    );
  }
}

Uri inviteSmsUri(Uri appUri, StaffInvite invite, {required bool isIos}) {
  final inviteUri = appUri.replace(
    queryParameters: {'invite': invite.token},
    fragment: '',
  );
  return messagesUri(
    [invite.cellNumber],
    'You have an Invite to the ER Schedule: $inviteUri',
    isIos: isIos,
  );
}
