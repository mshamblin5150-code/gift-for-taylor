import 'package:er_schedule/schedule/month_grid_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

void main() {
  const days = ScheduleSection(id: 'days', name: 'State dayshift RN');
  const nights = ScheduleSection(id: 'nights', name: 'PRN nightshift RN');
  const dayNurse = ScheduleRow(
    staffMemberId: 'rn-1',
    displayName: 'Day RN',
    sectionId: 'days',
  );
  const nightNurse = ScheduleRow(
    staffMemberId: 'rn-2',
    displayName: 'Night RN',
    sectionId: 'nights',
  );
  final september = DateTime(2026, 9);
  final september18 = DateTime(2026, 9, 18);

  late InMemoryScheduleDatabase database;

  setUp(() {
    database = InMemoryScheduleDatabase(
      sections: const [days, nights],
      rows: const [dayNurse, nightNurse],
      editors: const {'manager', 'other-manager'},
      releasedMonths: {september},
    );
  });

  Future<ScheduleRules> pumpGrid(
    WidgetTester tester, {
    String actingAs = 'manager',
    String? staffMemberId,
    DateTime? month,
    ValueChanged<String>? printBookPage,
  }) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rules = ScheduleRules.inMemory(database, actingAs: actingAs);
    await tester.pumpWidget(
      MaterialApp(
        home: MonthGridPage(
          rules: rules,
          month: month ?? september,
          staffMemberId: staffMemberId,
          printBookPage: printBookPage,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return rules;
  }

  Finder cell(String staffMemberId, DateTime date) => find.byKey(
    ValueKey('cell-$staffMemberId-${date.toIso8601String().substring(0, 10)}'),
  );

  Finder unannounced(String staffMemberId, DateTime date) => find.byKey(
    ValueKey(
      'unannounced-$staffMemberId-${date.toIso8601String().substring(0, 10)}',
    ),
  );

  testWidgets('month grid shows Sections, rows, weekdays, and weekends', (
    tester,
  ) async {
    await pumpGrid(tester);

    expect(find.text('September 2026'), findsOneWidget);
    expect(find.text('State dayshift RN'), findsOneWidget);
    expect(find.text('PRN nightshift RN'), findsOneWidget);
    expect(find.text('Day RN'), findsOneWidget);
    expect(find.text('T'), findsWidgets);
    expect(find.byKey(const ValueKey('weekday-2026-09-18')), findsNWidgets(2));
    expect(find.byKey(const ValueKey('weekend-2026-09-19')), findsNWidgets(2));
  });

  testWidgets(
    'Staff member lands on their changed shifts and opens full grid',
    (tester) async {
      final manager = ScheduleRules.inMemory(database, actingAs: 'manager');
      await manager.saveCell(
        SaveCell(
          staffMemberId: 'rn-1',
          sectionId: 'days',
          date: september18,
          shiftCode: '7A',
        ),
      );
      database.markAllAnnounced();

      await pumpGrid(tester, actingAs: 'rn-1', staffMemberId: 'rn-1');

      expect(find.text('Day RN'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('changed-rn-1-2026-09-18')),
        findsOneWidget,
      );
      expect(find.text('Other Shift code'), findsNothing);

      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();

      expect(cell('rn-1', september18), findsOneWidget);
      expect(
        find.byKey(const ValueKey('changed-rn-1-2026-09-18')),
        findsOneWidget,
      );
      expect(unannounced('rn-2', september18), findsNothing);
    },
  );

  testWidgets('Staff member sees no highlight after a shift is restored', (
    tester,
  ) async {
    final manager = ScheduleRules.inMemory(database, actingAs: 'manager');
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'rn-1',
        sectionId: 'days',
        date: september18,
        shiftCode: '7A',
      ),
    );
    database.markAllAnnounced();
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'rn-1',
        sectionId: 'days',
        date: september18,
        shiftCode: '',
      ),
    );
    database.markAllAnnounced();

    await pumpGrid(tester, actingAs: 'rn-1', staffMemberId: 'rn-1');

    expect(find.byKey(const ValueKey('changed-rn-1-2026-09-18')), findsNothing);
  });

  testWidgets('Manager picks a legend code, shown with its hours', (
    tester,
  ) async {
    await pumpGrid(tester);

    await tester.tap(cell('rn-1', september18));
    await tester.pumpAndSettle();

    expect(find.text('7A–7P'), findsOneWidget);
    expect(find.text('Sick leave'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, '7A'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: cell('rn-1', september18), matching: find.text('7A')),
      findsOneWidget,
    );
    expect(unannounced('rn-1', september18), findsOneWidget);
  });

  testWidgets('Manager types any other Shift code', (tester) async {
    await pumpGrid(tester);

    await tester.tap(cell('rn-1', september18));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Other Shift code'),
      '4P-8A',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: cell('rn-1', september18),
        matching: find.text('4P-8A'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('undo restores the published value', (tester) async {
    final setup = ScheduleRules.inMemory(database, actingAs: 'manager');
    await setup.saveCell(
      SaveCell(
        staffMemberId: 'rn-1',
        sectionId: 'days',
        date: september18,
        shiftCode: '7A',
      ),
    );
    database.markAllAnnounced();
    await setup.saveCell(
      SaveCell(
        staffMemberId: 'rn-1',
        sectionId: 'days',
        date: september18,
        shiftCode: 'X',
      ),
    );
    await pumpGrid(tester);
    expect(unannounced('rn-1', september18), findsOneWidget);

    await tester.tap(cell('rn-1', september18));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo to 7A'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: cell('rn-1', september18), matching: find.text('7A')),
      findsOneWidget,
    );
    expect(unannounced('rn-1', september18), findsNothing);
  });

  testWidgets('a save by another scheduler appears without reloading', (
    tester,
  ) async {
    await pumpGrid(tester);

    await tester.runAsync(
      () =>
          ScheduleRules.inMemory(database, actingAs: 'other-manager').saveCell(
            SaveCell(
              staffMemberId: 'rn-2',
              sectionId: 'nights',
              date: september18,
              shiftCode: 'N',
            ),
          ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: cell('rn-2', september18), matching: find.text('N')),
      findsOneWidget,
    );
  });

  testWidgets('day view shows and edits one date', (tester) async {
    await pumpGrid(tester);

    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pick a date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('18'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Friday, September 18'), findsOneWidget);
    await tester.tap(find.text('Night RN'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '7P'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, '7P'), findsOneWidget);

    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: cell('rn-2', september18), matching: find.text('7P')),
      findsOneWidget,
    );
  });

  testWidgets('one-person view shows and edits one person\'s month', (
    tester,
  ) async {
    await pumpGrid(tester);

    await tester.tap(find.text('Person'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Night RN').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fri 18'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'ME'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, 'ME'), findsOneWidget);
  });

  testWidgets('after a Last day the row ends and the hole shows short', (
    tester,
  ) async {
    final manager = ScheduleRules.inMemory(database, actingAs: 'manager');
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'rn-1',
        sectionId: 'days',
        date: DateTime(2026, 9, 20),
        shiftCode: '7A',
      ),
    );
    await manager.setLastDay(
      SetLastDay(staffMemberId: 'rn-1', lastDay: september18),
    );

    await pumpGrid(tester);

    expect(cell('rn-1', september18), findsOneWidget);
    expect(cell('rn-1', DateTime(2026, 9, 19)), findsNothing);
    expect(find.byKey(const ValueKey('gone-rn-1-2026-09-19')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('short-days-2026-09-20')),
        matching: find.text('−1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('short-nights-2026-09-20')),
        matching: find.text('−1'),
      ),
      findsNothing,
    );
  });

  testWidgets('someone who cannot edit gets no edit sheet', (tester) async {
    database = InMemoryScheduleDatabase(
      sections: const [days, nights],
      rows: const [dayNurse, nightNurse],
      editors: const {'manager'},
      releasedMonths: {september},
    );
    await pumpGrid(tester, actingAs: 'rn-1');

    await tester.tap(cell('rn-1', september18));
    await tester.pumpAndSettle();

    expect(find.text('Other Shift code'), findsNothing);
  });

  group('building next month', () {
    setUp(() async {
      await ScheduleRules.inMemory(database, actingAs: 'manager').saveCell(
        SaveCell(
          staffMemberId: 'rn-1',
          sectionId: 'days',
          date: september18,
          shiftCode: '4P-8A',
        ),
      );
      database.markAllAnnounced();
    });

    testWidgets('the Manager starts next month and releases it', (
      tester,
    ) async {
      await pumpGrid(tester);

      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();

      expect(find.text('October 2026'), findsOneWidget);
      expect(find.textContaining("hasn't been started"), findsOneWidget);

      await tester.tap(find.text('Start from September'));
      await tester.pumpAndSettle();

      // Friday September 18 lines up with Friday October 16.
      expect(find.text('4P-8A'), findsOneWidget);
      expect(
        find.descendant(
          of: cell('rn-1', DateTime(2026, 10, 16)),
          matching: find.text('4P-8A'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Unpublished'), findsOneWidget);

      await tester.tap(find.text('Release month'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Release'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Unpublished'), findsNothing);
      expect(find.text('4P-8A'), findsOneWidget);
    });

    testWidgets('a month is started before it is edited', (tester) async {
      await pumpGrid(tester, month: DateTime(2026, 10));

      await tester.tap(cell('rn-1', DateTime(2026, 10, 16)));
      await tester.pumpAndSettle();

      expect(find.text('Other Shift code'), findsNothing);
      expect(find.text('Start October first.'), findsOneWidget);
    });

    testWidgets('staff do not see a month before it is released', (
      tester,
    ) async {
      await ScheduleRules.inMemory(
        database,
        actingAs: 'manager',
      ).startNextMonth(september);
      await pumpGrid(tester, actingAs: 'rn-1', month: DateTime(2026, 10));

      expect(find.textContaining("hasn't been released"), findsOneWidget);
      expect(find.text('4P-8A'), findsNothing);
      expect(find.text('Release month'), findsNothing);
    });
  });

  testWidgets('Print sends the live month as the book page', (tester) async {
    final printed = <String>[];
    final rules = await pumpGrid(tester, printBookPage: printed.add);
    await rules.saveCell(
      SaveCell(
        staffMemberId: 'rn-2',
        sectionId: 'nights',
        date: september18,
        shiftCode: '4P-8A',
      ),
    );

    await tester.tap(find.byTooltip('Print the book page'));
    await tester.pumpAndSettle();

    expect(printed, hasLength(1));
    expect(printed.single, contains('Schedule subject to change'));
    expect(printed.single, contains('September 2026'));
    expect(printed.single, contains('>Night RN<'));
    expect(printed.single, contains('4P-8A'));
  });

  testWidgets('there is no Print button without a printer', (tester) async {
    await pumpGrid(tester);

    expect(find.byTooltip('Print the book page'), findsNothing);
  });

  group('a month loaded from the printed page', () {
    setUp(() {
      database.loadFromPage(september, [
        ScheduleCell(
          staffMemberId: 'rn-1',
          sectionId: 'days',
          date: september18,
          shiftCode: '4P-8A',
        ),
      ]);
    });

    testWidgets('the Manager checks it and confirms it', (tester) async {
      await pumpGrid(tester);

      expect(find.text('4P-8A'), findsOneWidget);
      expect(find.textContaining('Check this month'), findsOneWidget);

      await tester.tap(find.text('Confirm month'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Check this month'), findsNothing);
      expect(find.text('4P-8A'), findsOneWidget);
    });

    testWidgets('someone who cannot edit is not asked to confirm it', (
      tester,
    ) async {
      await pumpGrid(tester, actingAs: 'rn-1');

      expect(find.text('Confirm month'), findsNothing);
    });
  });
}
