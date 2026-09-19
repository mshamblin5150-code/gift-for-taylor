import 'package:flutter/foundation.dart';

import '../staff/sms_launcher.dart';

/// Opens Messages with recipients and a body prefilled; the scheduler taps
/// send on their own phone.
abstract interface class MessagesComposer {
  Future<void> open(List<String> cellNumbers, String body);
}

final class SmsMessagesComposer implements MessagesComposer {
  const SmsMessagesComposer();

  @override
  Future<void> open(List<String> cellNumbers, String body) {
    return openSmsUrl(
      messagesUri(
        cellNumbers,
        body,
        isIos: defaultTargetPlatform == TargetPlatform.iOS,
      ),
    );
  }
}

/// The link that opens Messages prefilled. iOS needs its own forms, the group
/// one verified on the Manager's iPhone during the prototype session.
Uri messagesUri(List<String> cellNumbers, String body, {required bool isIos}) {
  final numbers = cellNumbers.map(_dialable).join(',');
  final encodedBody = Uri.encodeComponent(body);
  if (!isIos) return Uri.parse('sms:$numbers?body=$encodedBody');
  return cellNumbers.length > 1
      ? Uri.parse('sms:/open?addresses=$numbers&body=$encodedBody')
      : Uri.parse('sms:$numbers&body=$encodedBody');
}

String _dialable(String cellNumber) =>
    cellNumber.replaceAll(RegExp(r'[^0-9+]'), '');
