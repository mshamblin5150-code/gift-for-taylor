import 'package:er_schedule/schedule/shift_codes_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

void main() {
  test('used Shift code returns a typed refusal outcome', () async {
    final session = ShiftCodesSession(_RefusingShiftCodeStore());

    final outcome = await session.delete('7A');

    expect(outcome, isA<ShiftCodeDeleteRefused>());
    expect((outcome as ShiftCodeDeleteRefused).code, 'P2796');
    session.dispose();
  });

  test('Access rejection is reported by a Shift-code command', () async {
    var rejections = 0;
    final session = ShiftCodesSession(
      _RefusingShiftCodeStore(const AccessRejected()),
      () => rejections++,
    );

    final outcome = await session.delete('7A');

    expect(outcome, isA<ShiftCodeWriteFailed>());
    expect(rejections, 1);
    session.dispose();
  });
}

final class _RefusingShiftCodeStore extends Fake implements ScheduleStore {
  _RefusingShiftCodeStore([this.failure = const ShiftCodeInUse()]);

  final Object failure;

  @override
  Future<List<LegendCode>> shiftCodes() async => const [LegendCode('7A')];

  @override
  Future<void> deleteShiftCode(String code) => Future.error(failure);
}
