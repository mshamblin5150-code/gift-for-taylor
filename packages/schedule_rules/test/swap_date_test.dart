import 'package:schedule_rules/schedule_rules.dart';
import 'package:test/test.dart';

void main() {
  test('Swap days begin tomorrow regardless of the current time', () {
    final now = DateTime(2026, 9, 10, 8);

    expect(firstFutureSwapDay(now), DateTime(2026, 9, 11));
    expect(isFutureSwapDay(DateTime(2026, 9, 9, 23, 59), now: now), isFalse);
    expect(isFutureSwapDay(DateTime(2026, 9, 10, 19), now: now), isFalse);
    expect(isFutureSwapDay(DateTime(2026, 9, 11), now: now), isTrue);
  });

  test('tomorrow is a calendar date across daylight-saving changes', () {
    expect(firstFutureSwapDay(DateTime(2026, 11, 1, 8)), DateTime(2026, 11, 2));
  });
}
