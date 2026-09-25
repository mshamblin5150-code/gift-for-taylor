import 'package:er_schedule/schedule/swap_proposal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

void main() {
  Swap swap(List<SwapShift> mine, List<SwapShift> theirs) => Swap(
    id: 'swap',
    requesterId: 'me',
    colleagueId: 'you',
    requesterShifts: mine,
    colleagueShifts: theirs,
    status: SwapStatus.proposed,
  );

  SwapShift shift(int month, int day, String code) => SwapShift(
    date: DateTime(2027, month, day),
    shiftCode: code,
    targetCode: '',
  );

  test('contiguous runs collapse and uniform codes appear once', () {
    final value = swap(
      [shift(6, 20, '7P'), shift(6, 21, '7P'), shift(6, 22, '7P')],
      [shift(7, 3, '7A'), shift(7, 4, '7A'), shift(7, 5, '7A')],
    );

    expect(swapSummary(value), 'my Jun 20–22 7P for your Jul 3–5 7A');
  });

  test('scattered dates are named and mixed codes are omitted', () {
    final value = swap(
      [shift(6, 20, '7P'), shift(6, 21, '7A'), shift(6, 22, '7P')],
      [shift(7, 3, '7A'), shift(7, 5, '7A'), shift(7, 9, '7A')],
    );

    expect(swapSummary(value), 'my Jun 20–22 for your Jul 3, 5 and 9 7A');
    expect(swapSummary(value), isNot(contains('Jul 3–9')));
  });

  test('long wording falls back by length rather than date count', () {
    final value = swap(
      [
        for (final day in [1, 3, 5, 7, 9]) shift(6, day, '7P'),
      ],
      [
        for (final day in [2, 4, 6, 8, 10]) shift(7, day, '7A'),
      ],
    );

    expect(
      swapSummary(value, maxLength: 20),
      'my 5 shifts for your 5 shifts in ER Schedule',
    );
  });

  test('wording follows the viewer perspective', () {
    final value = swap([shift(6, 20, '7P')], [shift(7, 3, '7A')]);

    expect(
      swapSummaryFor(value, perspective: SwapSummaryPerspective.colleague),
      'my Jul 3 7A for your Jun 20 7P',
    );
    expect(
      swapSummaryFor(
        value,
        perspective: SwapSummaryPerspective.neutral,
        requesterName: 'Alex',
        colleagueName: 'Dana',
      ),
      'Alex’s Jun 20 7P for Dana’s Jul 3 7A',
    );
  });
}
