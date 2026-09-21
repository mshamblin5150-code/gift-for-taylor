import 'package:schedule_rules/schedule_rules.dart';
import 'package:test/test.dart';

void main() {
  test('default print wording names the Schedule and month', () {
    const wording = PrintWording();
    expect(wording.tooltip, 'Print the book page');
    expect(wording.notice, 'Schedule subject to change');
    expect(
      wording.titleFor(DateTime(2026, 9)),
      'Welch Community Hospital - Emergency Room Schedule - SEPTEMBER 2026',
    );
    expect(
      wording.titleFor(DateTime(2026, 10)),
      'Welch Community Hospital - Emergency Room Schedule - OCTOBER 2026',
    );
  });

  test('custom wording retains its own title and notice', () {
    const wording = PrintWording(
      tooltip: 'Print this Schedule',
      title: 'ER Schedule',
      notice: '',
    );
    expect(wording.tooltip, 'Print this Schedule');
    expect(wording.notice, isEmpty);
    expect(wording.titleFor(DateTime(2026, 9)), 'ER Schedule - SEPTEMBER 2026');
  });
}
