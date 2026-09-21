import 'package:schedule_book/schedule_book.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:test/test.dart';

Future<MonthGrid> grid({
  int sections = 1,
  int staff = 2,
  String? firstName,
  String? firstCode,
}) async {
  final groups = [
    for (var i = 0; i < sections; i++)
      ScheduleSection(id: 'section-$i', name: 'Section $i'),
  ];
  final rows = [
    for (var i = 0; i < staff; i++)
      ScheduleRow(
        staffMemberId: 'staff-$i',
        displayName: i == 0 ? firstName ?? 'Nguyễn' : 'Staff $i',
        sectionId: groups[i % sections].id,
      ),
  ];
  final rules = ScheduleRules.inMemory(
    InMemoryScheduleDatabase(sections: groups, rows: rows),
    actingAs: 'manager',
  );
  if (firstCode != null) {
    await rules.saveCell(
      SaveCell(
        staffMemberId: 'staff-0',
        sectionId: 'section-0',
        date: DateTime(2026, 9, 5),
        shiftCode: firstCode,
      ),
    );
  }
  return rules.monthGrid(DateTime(2026, 9));
}

void main() {
  test('sparse Schedule book uses full 9pt without warning', () async {
    final page = await prepareBookPage(await grid());
    expect(page.fontSize, 9);
    expect(page.isHardToRead, isFalse);
    expect(page.causes, isEmpty);
  });

  test('dense Schedule book reports a whole-page height cause', () async {
    final page = await prepareBookPage(await grid(sections: 8, staff: 40));
    expect(page.fontSize, lessThan(9));
    expect(page.causes.first.kind, LayoutCauseKind.wholePageScale);
    expect(page.causes.first.description, contains('40 Staff'));
  });

  test('long legend meaning consumes lines and grid height', () async {
    final month = await grid(sections: 8, staff: 40);
    final short = await prepareBookPage(
      month,
      codes: const [LegendCode('X', meaning: 'Off')],
    );
    final long = await prepareBookPage(
      month,
      codes: [
        LegendCode(
          'X',
          meaning: List.filled(150, 'extended meaning').join(' '),
        ),
      ],
    );
    expect(long.legendLines.length, greaterThan(short.legendLines.length));
    expect(long.fontSize, lessThan(short.fontSize));
  });

  test('long name widens its column then records the squeeze', () async {
    final page = await prepareBookPage(
      await grid(firstName: 'Nguyễn ${'Montgomery-Williams ' * 8}'),
    );
    expect(page.nameWidth, 180);
    final name = page.squeezedItems.singleWhere(
      (item) => item.kind == SqueezedKind.name,
    );
    expect(name.effectiveSize, lessThan(page.fontSize));
    expect(page.isHardToRead, isTrue);
  });

  test(
    'long Shift code names its Staff member and date; causes are worst first',
    () async {
      final page = await prepareBookPage(
        await grid(
          firstName: 'Nguyễn ${'Montgomery-Williams ' * 8}',
          firstCode: 'EXTRALONGCODEFORTHEDAY',
        ),
      );
      final code = page.squeezedItems.singleWhere(
        (item) => item.kind == SqueezedKind.code,
      );
      expect(code.staffName, contains('Nguyễn'));
      expect(code.date, DateTime(2026, 9, 5));
      expect(
        page.causes.any((cause) => cause.description.contains('2026-9-5')),
        isTrue,
      );
      for (var i = 1; i < page.causes.length; i++) {
        expect(
          page.causes[i].effectiveSize,
          greaterThanOrEqualTo(page.causes[i - 1].effectiveSize),
        );
      }
    },
  );

  test('overwide notice is measured and named as a cause', () async {
    final page = await prepareBookPage(
      await grid(),
      wording: PrintWording(notice: 'Notice ' * 100),
    );
    expect(page.noticeScale, lessThan(1));
    expect(page.minimumEffectiveSize, lessThan(6));
    expect(page.causes.first.kind, LayoutCauseKind.squeezedNotice);
  });
}
