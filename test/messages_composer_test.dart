import 'package:er_schedule/schedule/messages_composer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const body = 'Hi Dana Reyes, ER Schedule change:\nFri 9/18: off (was 7A)';
  const encodedBody =
      'Hi%20Dana%20Reyes%2C%20ER%20Schedule%20change%3A%0A'
      'Fri%209%2F18%3A%20off%20(was%207A)';

  test('an iPhone text to one person carries the number and body', () {
    expect(
      messagesUri(['5550100'], body, isIos: true).toString(),
      'sms:5550100&body=$encodedBody',
    );
  });

  test('an iPhone group text addresses everyone, then the body', () {
    expect(
      messagesUri(['5550100', '5550101'], body, isIos: true).toString(),
      'sms:/open?addresses=5550100,5550101&body=$encodedBody',
    );
  });

  test('other phones use the standard link', () {
    expect(
      messagesUri(['5550100', '5550101'], body, isIos: false).toString(),
      'sms:5550100,5550101?body=$encodedBody',
    );
  });

  test('canonical Cell numbers are passed through to Messages', () {
    expect(
      messagesUri(
        ['+15550100100', '+15550100101'],
        'Hi',
        isIos: true,
      ).toString(),
      'sms:/open?addresses=+15550100100,+15550100101&body=Hi',
    );
  });
}
