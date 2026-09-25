import 'package:schedule_rules_testing/schedule_rules_testing.dart';
import 'package:er_schedule/schedule/month_grid_page.dart';
import 'package:er_schedule/schedule/book_page_printing.dart';
import 'package:er_schedule/schedule/print_wording_gateway.dart';
import 'package:er_schedule/schedule_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'support/app_dependencies.dart';
import 'support/repair.dart';

typedef _StaffingFact = ({
  int? minimum,
  int shortfall,
  int openCount,
  int rnShortfall,
});

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

  void seedStaffing(
    DateTime month, {
    Map<(String, CoverageWindow, int), _StaffingFact> facts = const {},
    bool afterNextCellWrite = false,
  }) {
    final answer = [
      for (
        var day = 1;
        day <= DateTime(month.year, month.month + 1, 0).day;
        day++
      )
        for (final pool in CoveragePool.values)
          for (final window in CoverageWindow.values)
            SectionStaffing(
              pool: pool,
              coverageWindow: window,
              date: DateTime(month.year, month.month, day),
              minimum:
                  facts[(pool.value, window, day)]?.minimum ??
                  (window == CoverageWindow.night ? 0 : null),
              rnFloor: null,
              workingCount: 0,
              rnCount: 0,
              openCount: facts[(pool.value, window, day)]?.openCount ?? 0,
              rnOpenCount: 0,
              shortCount:
                  facts[(pool.value, window, day)]?.shortfall ??
                  (window == CoverageWindow.night ? 0 : null),
              rnShortCount:
                  facts[(pool.value, window, day)]?.rnShortfall ??
                  (window == CoverageWindow.night ? 0 : null),
              unpostedCount:
                  window == CoverageWindow.night ||
                      facts.containsKey((pool.value, window, day))
                  ? 0
                  : null,
              floorRole: pool == CoveragePool.nurses ? JobRole.rn : null,
            ),
    ];
    if (afterNextCellWrite) {
      database.seedStaffingAfterNextCellWrite(month, answer);
    } else {
      database.seedStaffingForMonth(month, answer);
    }
  }

  setUp(() async {
    database = InMemoryScheduleDatabase(
      sections: const [days, nights],
      rows: const [dayNurse, nightNurse],
      grants: {
        'manager': Grants(manager: true),
        'other-manager': Grants(nightSchedulerSectionIds: {'nights'}),
      },
      releasedMonths: {september},
    );
    for (final id in ['rn-1', 'rn-2']) {
      database.seedJobRoles(id, [
        DatedJobRole(
          jobRole: JobRole.rn,
          from: DateTime(2026, 1),
          through: null,
        ),
      ]);
    }
  });

  void seedOpenDay(DateTime date) =>
      database.seedShortShifts(DateTime(date.year, date.month), [
        ShortShift(
          date: date,
          shiftCode: '7A',
          staffMemberId: null,
          jobRole: JobRole.rn,
          coverageWindow: CoverageWindow.day,
          coveragePool: CoveragePool.nurses,
        ),
      ]);

  Future<ScheduleRules> pumpGrid(
    WidgetTester tester, {
    String actingAs = 'manager',
    String? staffMemberId,
    DateTime? month,
    BookPagePresenter? bookPagePresenter,
    PrintWordingGateway? printWordingGateway,
    DateTime Function()? now,
    bool withStaffing = false,
    Size size = const Size(2400, 1600),
  }) async {
    if (withStaffing && !database.hasStaffingForMonth(month ?? september)) {
      seedStaffing(month ?? september);
    }
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rules = scheduleRulesInMemory(database, actingAs: actingAs);
    await tester.pumpWidget(
      MaterialApp(
        home: MonthGridPage(
          swapStore: emptySwapStore(actingAs),
          noticeGateway: const NoopNoticeGateway(),
          repairController: noopRepairController(),
          access: database.accessFor(actingAs),
          key: ValueKey(month ?? september),
          rules: rules,
          month: month ?? september,
          staffMemberId: staffMemberId,
          openShiftStore: withStaffing
              ? database.openShiftStoreFor(actingAs)
              : null,
          bookPagePresenter: bookPagePresenter,
          printWordingGateway: printWordingGateway,
          now: now,
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

  testWidgets('Help opens from Schedule for a Staff member', (tester) async {
    await pumpGrid(
      tester,
      actingAs: 'rn-1',
      staffMemberId: 'rn-1',
      size: const Size(390, 844),
    );
    await tester.tap(find.byTooltip('Schedule actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle();
    expect(find.text('Help'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'release month');
    await tester.pump();
    expect(find.text('Month release'), findsNothing);
  });

  Color cellColor(WidgetTester tester, String staffMemberId, DateTime date) {
    final container = tester.widget<Container>(
      find
          .descendant(
            of: cell(staffMemberId, date),
            matching: find.byType(Container),
          )
          .first,
    );
    return (container.decoration! as BoxDecoration).color!;
  }

  testWidgets('today is distinct from weekends in light and dark themes', (
    tester,
  ) async {
    final today = DateTime(2026, 9, 19);
    await pumpGrid(tester, now: () => today);
    final todayColor = cellColor(tester, 'rn-1', today);
    final otherWeekend = cellColor(tester, 'rn-1', DateTime(2026, 9, 20));
    expect(todayColor, isNot(otherWeekend));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: MonthGridPage(
          swapStore: emptySwapStore('manager'),
          noticeGateway: const NoopNoticeGateway(),
          repairController: noopRepairController(),
          access: database.accessFor('manager'),
          rules: scheduleRulesInMemory(database, actingAs: 'manager'),
          month: september,
          now: () => today,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      cellColor(tester, 'rn-1', today),
      isNot(cellColor(tester, 'rn-1', DateTime(2026, 9, 20))),
    );
  });

  testWidgets('today highlight moves at local midnight', (tester) async {
    var now = DateTime(2026, 9, 18, 23, 59, 59);
    await pumpGrid(tester, now: () => now);
    final yesterdayColor = cellColor(tester, 'rn-1', DateTime(2026, 9, 18));
    now = DateTime(2026, 9, 19);
    await tester.pump(const Duration(seconds: 1));
    expect(
      cellColor(tester, 'rn-1', DateTime(2026, 9, 18)),
      isNot(yesterdayColor),
    );
    expect(cellColor(tester, 'rn-1', DateTime(2026, 9, 19)), yesterdayColor);
  });

  testWidgets('current month opens with today visible', (tester) async {
    await pumpGrid(
      tester,
      now: () => DateTime(2026, 9, 19),
      size: const Size(900, 800),
    );
    final horizontal = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('month-horizontal-scroll')),
    );
    expect(horizontal.controller!.offset, greaterThan(0));
    final rect = tester.getRect(cell('rn-1', DateTime(2026, 9, 19)));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(900));
    expect(
      tester.getRect(find.text('19')).center.dx,
      closeTo(rect.center.dx, 1),
    );

    await pumpGrid(
      tester,
      month: DateTime(2026, 8),
      now: () => DateTime(2026, 9, 19),
      size: const Size(900, 800),
    );
    final otherMonthScroll = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('month-horizontal-scroll')),
    );
    expect(otherMonthScroll.controller!.offset, 0);
    expect(
      cellColor(tester, 'rn-1', DateTime(2026, 8, 18)),
      cellColor(tester, 'rn-1', DateTime(2026, 8, 19)),
    );
  });

  testWidgets('day and person views mark today', (tester) async {
    await pumpGrid(tester, now: () => DateTime(2026, 9, 19));
    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();
    final dayLabel = find.text('Saturday, September 19');
    final dayContainer = tester.widget<Container>(
      find.ancestor(of: dayLabel, matching: find.byType(Container)).first,
    );
    expect((dayContainer.decoration! as BoxDecoration).color, isNotNull);

    await tester.tap(find.text('Person'));
    await tester.pumpAndSettle();
    final todayTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('Sat 19'), matching: find.byType(ListTile)),
    );
    expect(todayTile.tileColor, isNotNull);
    expect(todayTile.leading, isA<Icon>());
  });

  testWidgets('dragging across rows swaps Shift codes and Undo restores them', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final manager = scheduleRulesInMemory(database, actingAs: 'manager');
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'rn-1',
        sectionId: 'days',
        date: september18,
        shiftCode: '7A',
      ),
    );
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'rn-2',
        sectionId: 'nights',
        date: september18,
        shiftCode: 'X',
      ),
    );
    await pumpGrid(tester);
    final source = tester.getCenter(cell('rn-1', september18));
    final target = tester.getCenter(cell('rn-2', september18));
    final gesture = await tester.startGesture(source);
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.descendant(of: cell('rn-1', september18), matching: find.text('X')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cell('rn-2', september18), matching: find.text('7A')),
      findsOneWidget,
    );
    await tester.tap(find.text('Undo'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.descendant(of: cell('rn-1', september18), matching: find.text('7A')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cell('rn-2', september18), matching: find.text('X')),
      findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Ctrl-drop copies a Shift code to another day', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final manager = scheduleRulesInMemory(database, actingAs: 'manager');
    final nextDay = DateTime(2026, 9, 19);
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'rn-1',
        sectionId: 'days',
        date: september18,
        shiftCode: '7A',
      ),
    );
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'rn-1',
        sectionId: 'days',
        date: nextDay,
        shiftCode: 'X',
      ),
    );
    await pumpGrid(tester);
    final source = tester.getCenter(cell('rn-1', september18));
    final target = tester.getCenter(cell('rn-1', nextDay));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    final gesture = await tester.startGesture(source);
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(
      find.descendant(of: cell('rn-1', september18), matching: find.text('7A')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cell('rn-1', nextDay), matching: find.text('7A')),
      findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('phone long press picks up a shift', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final manager = scheduleRulesInMemory(database, actingAs: 'manager');
    final nextDay = DateTime(2026, 9, 19);
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'rn-1',
        sectionId: 'days',
        date: september18,
        shiftCode: '7A',
      ),
    );
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'rn-1',
        sectionId: 'days',
        date: nextDay,
        shiftCode: 'X',
      ),
    );
    await pumpGrid(tester);
    final source = tester.getCenter(cell('rn-1', september18));
    final target = tester.getCenter(cell('rn-1', nextDay));
    final gesture = await tester.startGesture(source);
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(
      find.descendant(of: cell('rn-1', september18), matching: find.text('X')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cell('rn-1', nextDay), matching: find.text('7A')),
      findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a swap onto a blank cell leaves the source in place', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final manager = scheduleRulesInMemory(database, actingAs: 'manager');
    final nextDay = DateTime(2026, 9, 19);
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'rn-1',
        sectionId: 'days',
        date: september18,
        shiftCode: '7A',
      ),
    );
    await pumpGrid(tester);
    final source = tester.getCenter(cell('rn-1', september18));
    final target = tester.getCenter(cell('rn-1', nextDay));
    final gesture = await tester.startGesture(source);
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(
      find.text(
        'Choose a cell with a Shift code to swap, or hold Ctrl or Option to copy here.',
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cell('rn-1', september18), matching: find.text('7A')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cell('rn-1', nextDay), matching: find.text('7A')),
      findsNothing,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('pool band label stays visible while days scroll', (
    tester,
  ) async {
    await pumpGrid(
      tester,
      withStaffing: true,
      now: () => DateTime(2026, 8, 1),
      size: const Size(900, 800),
    );

    final label = find.text('Nurses');
    final nameCell = tester.widget<Container>(
      find.ancestor(of: label, matching: find.byType(Container)).first,
    );
    final firstDay = find.byKey(const ValueKey('pool-nurses-2026-09-01'));
    final dayCell = tester.widget<Container>(
      find.descendant(of: firstDay, matching: find.byType(Container)).first,
    );
    expect(nameCell.color, isNull);
    expect((dayCell.decoration! as BoxDecoration).color, isNotNull);
    expect(find.text('− = short by'), findsWidgets);

    final before = tester.getRect(label);
    await tester.drag(
      find.byKey(const ValueKey('month-horizontal-scroll')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(label), before);
    expect(tester.getRect(label).left, greaterThanOrEqualTo(0));
    expect(tester.getRect(label).right, lessThanOrEqualTo(900));
  });

  testWidgets('Section bar stays visible and continuous while days scroll', (
    tester,
  ) async {
    await pumpGrid(
      tester,
      month: DateTime(2026, 10),
      now: () => DateTime(2026, 8, 1),
      size: const Size(900, 800),
    );

    final nameBand = find.byKey(const ValueKey('section-name-days'));
    final dayBand = find.byKey(const ValueKey('section-days-days'));
    expect(nameBand, findsOneWidget);
    expect(dayBand, findsOneWidget);
    final label = find.text('State dayshift RN');
    expect(find.descendant(of: nameBand, matching: label), findsOneWidget);
    final name = tester.widget<Container>(nameBand);
    final days = tester.widget<Container>(dayBand);
    final nameBorder = (name.decoration! as BoxDecoration).border!;
    final dayBorder = (days.decoration! as BoxDecoration).border!;
    expect(nameBorder.top, dayBorder.top);
    expect(nameBorder.top.width, greaterThan(1));
    expect((name.decoration! as BoxDecoration).color, isNull);
    expect((days.decoration! as BoxDecoration).color, isNull);
    expect(tester.getRect(nameBand).top, tester.getRect(dayBand).top);
    expect(tester.getRect(nameBand).right, tester.getRect(dayBand).left);
    expect(tester.getRect(dayBand).width, 31 * 48);
    expect(
      find.descendant(of: dayBand, matching: find.byType(InkWell)),
      findsNothing,
    );

    final before = tester.getRect(nameBand);
    final dayBefore = tester.getRect(dayBand);
    await tester.drag(
      find.byKey(const ValueKey('month-horizontal-scroll')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(nameBand), before);
    expect(tester.getRect(dayBand).top, before.top);
    expect(tester.getRect(dayBand).left, lessThan(dayBefore.left));
    expect(tester.getRect(label).left, greaterThanOrEqualTo(0));
  });

  testWidgets('empty Section retains its band', (tester) async {
    database = InMemoryScheduleDatabase(
      sections: const [days, nights],
      rows: const [dayNurse],
      grants: {'manager': Grants(manager: true)},
      releasedMonths: {september},
    );
    await pumpGrid(tester);
    expect(find.byKey(const ValueKey('section-name-nights')), findsOneWidget);
    expect(find.byKey(const ValueKey('section-days-nights')), findsOneWidget);
    expect(find.text('PRN nightshift RN'), findsOneWidget);
  });

  testWidgets('pool band fill distinguishes covered, short 1, and short 4', (
    tester,
  ) async {
    seedStaffing(
      september,
      facts: {
        ('cna', CoverageWindow.day, 18): (
          minimum: 1,
          shortfall: 1,
          openCount: 0,
          rnShortfall: 0,
        ),
        ('cna', CoverageWindow.day, 19): (
          minimum: 4,
          shortfall: 4,
          openCount: 0,
          rnShortfall: 0,
        ),
        ('cna', CoverageWindow.day, 20): (
          minimum: 0,
          shortfall: 0,
          openCount: 0,
          rnShortfall: 0,
        ),
      },
    );
    await pumpGrid(tester, now: () => september18, withStaffing: true);

    Finder poolDay(int day) => find.byKey(
      ValueKey('pool-cna-2026-09-${day.toString().padLeft(2, '0')}'),
    );
    Color fill(int day) =>
        (tester
                    .widget<Container>(
                      find
                          .descendant(
                            of: poolDay(day),
                            matching: find.byType(Container),
                          )
                          .first,
                    )
                    .decoration!
                as BoxDecoration)
            .color!;

    expect(fill(18), isNot(fill(19)));
    expect(fill(20), isNot(fill(18)));
    expect(fill(18), ScheduleGridColors.light.shortOne);
    expect(fill(19), ScheduleGridColors.light.shortSeveral);
    expect(fill(20), ScheduleGridColors.light.covered);
    expect(
      find.descendant(of: poolDay(18), matching: find.text('−1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: poolDay(19), matching: find.text('−4')),
      findsOneWidget,
    );
    expect(tester.getSize(poolDay(18)).height, greaterThanOrEqualTo(44));
    expect(
      (tester
                  .widget<Container>(
                    find
                        .descendant(
                          of: poolDay(18),
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration)
          .border!
          .top
          .color,
      ScheduleGridColors.light.todayOutline,
    );

    await tester.tap(poolDay(18));
    await tester.pumpAndSettle();
    expect(find.text('Friday, September 18'), findsOneWidget);
  });

  testWidgets('pool bands stay pinned and aligned while staff rows scroll', (
    tester,
  ) async {
    database = InMemoryScheduleDatabase(
      sections: const [days],
      rows: [
        for (var index = 0; index < 24; index++)
          ScheduleRow(
            staffMemberId: 'staff-$index',
            displayName: 'Staff $index',
            sectionId: days.id,
          ),
      ],
      grants: {'manager': Grants(manager: true)},
      releasedMonths: {september},
    );
    seedStaffing(
      september,
      facts: {
        for (final pool in CoveragePool.values)
          (pool.value, CoverageWindow.day, 4): (
            minimum: 1,
            shortfall: 1,
            openCount: 0,
            rnShortfall: 0,
          ),
      },
    );
    await pumpGrid(
      tester,
      now: () => DateTime(2026, 8, 1),
      withStaffing: true,
      size: const Size(390, 600),
    );

    final labels = [
      find.text('Nurses'),
      find.text('CNAs'),
      find.text('Unit clerks'),
    ];
    final poolDays = [
      for (final pool in ['nurses', 'cna', 'unit_clerk'])
        find.byKey(ValueKey('pool-$pool-2026-09-04')),
    ];
    final initialLabels = labels.map(tester.getRect).toList();
    final initialDays = poolDays.map(tester.getRect).toList();
    final staffRow = find.text('Staff 0');
    final initialStaff = tester.getRect(staffRow);

    final vertical = tester.widget<SingleChildScrollView>(
      find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.vertical,
      ),
    );
    vertical.controller!.jumpTo(300);
    await tester.pumpAndSettle();

    expect(tester.getRect(staffRow).top, lessThan(initialStaff.top));
    for (var index = 0; index < labels.length; index++) {
      expect(tester.getRect(labels[index]), initialLabels[index]);
      expect(tester.getRect(poolDays[index]), initialDays[index]);
      expect(tester.getRect(labels[index]).top, greaterThanOrEqualTo(0));
      expect(tester.getRect(poolDays[index]).bottom, lessThan(600));
    }

    await tester.drag(
      find.byKey(const ValueKey('month-horizontal-scroll')),
      const Offset(-96, 0),
    );
    await tester.pumpAndSettle();
    final horizontalShift =
        initialDays.first.left - tester.getRect(poolDays.first).left;
    expect(horizontalShift, greaterThan(0));
    for (var index = 0; index < labels.length; index++) {
      expect(tester.getRect(labels[index]), initialLabels[index]);
      expect(
        tester.getRect(poolDays[index]).left,
        closeTo(initialDays[index].left - horizontalShift, 1),
      );
    }
    expect(
      tester.getRect(poolDays.first).center.dx,
      closeTo(
        tester.getRect(cell('staff-0', DateTime(2026, 9, 4))).center.dx,
        1,
      ),
    );
    expect(
      tester.getRect(poolDays.first).center.dx,
      closeTo(tester.getRect(find.text('4')).center.dx, 1),
    );

    final beforePoolDrag = tester.getRect(poolDays.first);
    await tester.drag(
      find.byKey(const ValueKey('month-pool-horizontal-scroll')),
      const Offset(-48, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(poolDays.first).left, lessThan(beforePoolDrag.left));
    expect(
      tester.getRect(poolDays.first).center.dx,
      closeTo(
        tester.getRect(cell('staff-0', DateTime(2026, 9, 4))).center.dx,
        1,
      ),
    );
    expect(
      tester.getRect(poolDays.first).center.dx,
      closeTo(tester.getRect(find.text('4')).center.dx, 1),
    );
  });

  testWidgets(
    'Staff member lands on their changed shifts and opens full grid',
    (tester) async {
      final manager = scheduleRulesInMemory(database, actingAs: 'manager');
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
    final manager = scheduleRulesInMemory(database, actingAs: 'manager');
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

  testWidgets('failed drop uses retry wording without the store error', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final manager = scheduleRulesInMemory(database, actingAs: 'manager');
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'rn-1',
        sectionId: 'days',
        date: september18,
        shiftCode: '7A',
      ),
    );
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'rn-2',
        sectionId: 'nights',
        date: september18,
        shiftCode: 'X',
      ),
    );
    await pumpGrid(tester);
    database.failNext(
      InMemoryStoreCall.writeCellPair,
      StateError('secret detail'),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(cell('rn-1', september18)),
    );
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(cell('rn-2', september18)));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(find.text("The drop wasn't saved. Try again."), findsOneWidget);
    expect(find.textContaining('secret detail'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('failed drop Undo shows retry wording', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final manager = scheduleRulesInMemory(database, actingAs: 'manager');
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'rn-1',
        sectionId: 'days',
        date: september18,
        shiftCode: '7A',
      ),
    );
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'rn-2',
        sectionId: 'nights',
        date: september18,
        shiftCode: 'X',
      ),
    );
    await pumpGrid(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(cell('rn-1', september18)),
    );
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(cell('rn-2', september18)));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    database.failNext(
      InMemoryStoreCall.writeCellPair,
      StateError('undo failed'),
    );
    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("The drop wasn't saved. Try again."), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('failed cell save explains the change was not saved', (
    tester,
  ) async {
    await pumpGrid(tester);
    database.failNext(InMemoryStoreCall.writeCell, StateError('write failed'));
    await tester.tap(cell('rn-1', september18));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '7A'));
    await tester.pump();
    expect(find.text("That change wasn't saved. Try again."), findsOneWidget);
  });

  testWidgets('failed month start shows retry wording', (tester) async {
    final october = DateTime(2026, 10);
    await pumpGrid(tester, month: october);
    database.failNext(InMemoryStoreCall.startMonth, StateError('write failed'));
    await tester.tap(find.text('Start empty month'));
    await tester.pump();
    expect(find.text("The month wasn't started. Try again."), findsOneWidget);
  });

  testWidgets('already started month is explained', (tester) async {
    final october = DateTime(2026, 10);
    await pumpGrid(tester, month: october);
    database.failNext(
      InMemoryStoreCall.startMonth,
      const MonthAlreadyStarted(),
    );
    await tester.tap(find.text('Start empty month'));
    await tester.pump();
    expect(find.text('This month has already been started.'), findsOneWidget);
  });

  testWidgets('missing previous Schedule is explained', (tester) async {
    final december = DateTime(2026, 12);
    final manager = scheduleRulesInMemory(database, actingAs: 'manager');
    await manager.startEmptyMonth(DateTime(2026, 11));
    await pumpGrid(tester, month: december);
    expect(find.text('Start from November'), findsOneWidget);
    database.failNext(InMemoryStoreCall.startMonth, PreviousMonthNotStarted());
    await tester.tap(find.text('Start from November'));
    await tester.pump();
    expect(
      find.text('November has no Schedule to start from.'),
      findsOneWidget,
    );
  });

  testWidgets('release review failure shows staffing retry wording', (
    tester,
  ) async {
    final october = DateTime(2026, 10);
    await scheduleRulesInMemory(
      database,
      actingAs: 'manager',
    ).startEmptyMonth(october);
    await pumpGrid(tester, month: october, withStaffing: true);
    database.failNext(
      InMemoryStoreCall.staffingForMonth,
      StateError('read failed'),
    );
    await tester.tap(find.text('Release month'));
    await tester.pump();
    expect(
      find.text('Staffing could not be checked. Try again.'),
      findsOneWidget,
    );
  });

  testWidgets('release write failure shows release retry wording', (
    tester,
  ) async {
    final october = DateTime(2026, 10);
    await scheduleRulesInMemory(
      database,
      actingAs: 'manager',
    ).startEmptyMonth(october);
    await pumpGrid(tester, month: october, withStaffing: true);
    await tester.tap(find.text('Release month'));
    await tester.pumpAndSettle();
    database.failNext(
      InMemoryStoreCall.releaseMonth,
      StateError('write failed'),
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pump();
    expect(find.text("The month wasn't released. Try again."), findsOneWidget);
  });

  testWidgets('pasted overlong cell code stays visible and cannot save', (
    tester,
  ) async {
    await pumpGrid(tester);
    await tester.tap(cell('rn-1', september18));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Other Shift code'),
      'C' * 9,
    );
    expect(find.text('C' * 9), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Use 5 characters or fewer.'), findsOneWidget);
    expect(find.text('Other Shift code'), findsOneWidget);
  });

  testWidgets('undo restores the published value', (tester) async {
    final setup = scheduleRulesInMemory(database, actingAs: 'manager');
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
      () => scheduleRulesInMemory(database, actingAs: 'other-manager').saveCell(
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

  testWidgets('Day view separates coverage from the Schedule Sections', (
    tester,
  ) async {
    await pumpGrid(tester, withStaffing: true);

    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();

    final coverageHeader = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Nurses'),
    );
    final sectionHeader = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'State dayshift RN'),
    );
    final breakLabel = find.text('Schedule by Section');
    expect(breakLabel, findsOneWidget);
    expect(
      tester.getTopLeft(breakLabel).dy,
      greaterThan(
        tester.getBottomLeft(find.widgetWithText(ListTile, 'Unit clerks')).dy,
      ),
    );
    expect(
      tester.getBottomLeft(breakLabel).dy,
      lessThan(
        tester
            .getTopLeft(find.widgetWithText(ListTile, 'State dayshift RN'))
            .dy,
      ),
    );
    expect(coverageHeader.tileColor, isNull);
    expect(sectionHeader.tileColor, isNull);
    expect(
      (coverageHeader.title! as Text).style?.color,
      isNot((sectionHeader.title! as Text).style?.color),
    );
  });

  testWidgets('Day view keeps unset Coverage windows editable', (tester) async {
    await pumpGrid(tester, withStaffing: true, now: () => september18);

    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();

    final unsetWindow = find.widgetWithText(ListTile, 'Days: not set').first;
    expect(unsetWindow, findsOneWidget);
    await tester.tap(unsetWindow);
    await tester.pumpAndSettle();

    expect(find.text('Minimum people'), findsOneWidget);
    expect(find.textContaining('minimum not set'), findsOneWidget);
  });

  testWidgets('Day view and Staffing sheet show the mixed RN Shortfall', (
    tester,
  ) async {
    seedStaffing(
      september,
      facts: {
        ('nurses', CoverageWindow.day, 18): (
          minimum: 2,
          shortfall: 2,
          openCount: 0,
          rnShortfall: 1,
        ),
      },
    );
    await pumpGrid(tester, withStaffing: true, now: () => september18);
    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();
    final summary = find.text('Days: Short 2 nursing, 1 RN');
    expect(summary, findsOneWidget);
    await tester.tap(summary);
    await tester.pumpAndSettle();
    expect(find.text('Short 2 nursing, 1 RN'), findsOneWidget);
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
    final manager = scheduleRulesInMemory(database, actingAs: 'manager');
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'rn-1',
        sectionId: 'days',
        date: DateTime(2026, 9, 20),
        shiftCode: '7A',
      ),
    );
    await manager.store.setLastDay(
      SetLastDay(staffMemberId: 'rn-1', lastDay: september18),
    );
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'rn-1',
        sectionId: 'days',
        date: DateTime(2026, 9, 20),
        shiftCode: '',
      ),
    );
    database.seedRows(september, [
      ScheduleRow(
        staffMemberId: dayNurse.staffMemberId,
        displayName: dayNurse.displayName,
        sectionId: dayNurse.sectionId,
        lastDay: september18,
      ),
      nightNurse,
    ]);
    database.seedShortShifts(september, [
      ShortShift(
        sectionId: 'days',
        date: DateTime(2026, 9, 20),
        shiftCode: '7A',
        staffMemberId: 'rn-1',
        jobRole: JobRole.rn,
        coverageWindow: CoverageWindow.day,
        coveragePool: CoveragePool.nurses,
      ),
    ]);
    seedStaffing(
      september,
      facts: {
        ('nurses', CoverageWindow.day, 20): (
          minimum: 1,
          shortfall: 1,
          openCount: 1,
          rnShortfall: 0,
        ),
      },
    );

    await pumpGrid(tester, withStaffing: true);

    expect(cell('rn-1', september18), findsOneWidget);
    expect(cell('rn-1', DateTime(2026, 9, 19)), findsNothing);
    expect(find.byKey(const ValueKey('gone-rn-1-2026-09-19')), findsOneWidget);
    final shortCell = tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(const ValueKey('pool-nurses-2026-09-20')),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (shortCell.decoration! as BoxDecoration).color,
      ScheduleGridColors.light.shortOne,
    );
  });

  testWidgets('someone who cannot edit gets no edit sheet', (tester) async {
    database = InMemoryScheduleDatabase(
      sections: const [days, nights],
      rows: const [dayNurse, nightNurse],
      grants: {'manager': Grants(manager: true)},
      releasedMonths: {september},
    );
    await pumpGrid(tester, actingAs: 'rn-1');

    await tester.tap(cell('rn-1', september18));
    await tester.pumpAndSettle();

    expect(find.text('Other Shift code'), findsNothing);
  });

  group('building next month', () {
    setUp(() async {
      await scheduleRulesInMemory(database, actingAs: 'manager').saveCell(
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
      expect(find.text('Start empty month'), findsOneWidget);

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

    testWidgets('the Manager can choose an empty draft instead of copying', (
      tester,
    ) async {
      await pumpGrid(tester, month: DateTime(2026, 10));
      expect(find.text('Start from September'), findsOneWidget);

      await tester.tap(find.text('Start empty month'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Unpublished'), findsOneWidget);
      expect(find.text('4P-8A'), findsNothing);
      expect(find.text('Start from September'), findsNothing);
    });

    testWidgets('a month is started before it is edited', (tester) async {
      await pumpGrid(tester, month: DateTime(2026, 10));

      await tester.tap(cell('rn-1', DateTime(2026, 10, 16)));
      await tester.pumpAndSettle();

      expect(find.text('Other Shift code'), findsNothing);
      expect(find.text('Start October first.'), findsOneWidget);
    });

    testWidgets('an unpublished cell edit refreshes the nursing marker', (
      tester,
    ) async {
      final manager = scheduleRulesInMemory(database, actingAs: 'manager');
      await manager.startNextMonth(september);
      final day = DateTime(2026, 10, 16);
      seedStaffing(
        DateTime(2026, 10),
        facts: {
          ('nurses', CoverageWindow.day, 16): (
            minimum: 3,
            shortfall: 3,
            openCount: 0,
            rnShortfall: 0,
          ),
          ('nurses', CoverageWindow.night, 16): (
            minimum: 3,
            shortfall: 3,
            openCount: 0,
            rnShortfall: 0,
          ),
        },
      );
      await pumpGrid(tester, month: DateTime(2026, 10), withStaffing: true);
      final marker = find.byKey(const ValueKey('short-nurses-2026-10-16'));
      expect(
        find.descendant(of: marker, matching: find.text('−6')),
        findsOneWidget,
      );

      await tester.tap(cell('rn-1', day));
      await tester.pumpAndSettle();
      seedStaffing(
        DateTime(2026, 10),
        facts: {
          ('nurses', CoverageWindow.day, 16): (
            minimum: 3,
            shortfall: 2,
            openCount: 0,
            rnShortfall: 0,
          ),
          ('nurses', CoverageWindow.night, 16): (
            minimum: 3,
            shortfall: 3,
            openCount: 0,
            rnShortfall: 0,
          ),
        },
        afterNextCellWrite: true,
      );
      await tester.tap(find.widgetWithText(OutlinedButton, '7A'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: marker, matching: find.text('−5')),
        findsOneWidget,
      );
    });

    testWidgets('staff do not see a month before it is released', (
      tester,
    ) async {
      await scheduleRulesInMemory(
        database,
        actingAs: 'manager',
      ).startNextMonth(september);
      database.hideMonthFor('rn-1', DateTime(2026, 10));
      await pumpGrid(tester, actingAs: 'rn-1', month: DateTime(2026, 10));

      expect(find.textContaining("hasn't been released"), findsOneWidget);
      expect(find.text('4P-8A'), findsNothing);
      expect(find.text('Release month'), findsNothing);
    });
  });

  testWidgets(
    'the Manager starts without a previous Schedule, edits, and releases',
    (tester) async {
      database = InMemoryScheduleDatabase(
        sections: const [days, nights],
        rows: const [dayNurse, nightNurse],
        grants: {'manager': Grants(manager: true)},
      );
      final month = DateTime(2026, 10);
      final date = DateTime(2026, 10, 16);
      await pumpGrid(tester, month: month);

      expect(find.text('Start empty month'), findsOneWidget);
      expect(find.text('Start from September'), findsNothing);
      await tester.tap(find.text('Start empty month'));
      await tester.pumpAndSettle();

      await tester.tap(cell('rn-1', date));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '7A'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: cell('rn-1', date), matching: find.text('7A')),
        findsOneWidget,
      );

      await tester.tap(find.text('Release month'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Release'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Unpublished'), findsNothing);
      expect(
        find.descendant(of: cell('rn-1', date), matching: find.text('7A')),
        findsOneWidget,
      );
    },
  );

  testWidgets('release dialog separates Shortfall and Open shift days', (
    tester,
  ) async {
    final month = DateTime(2026, 10);
    final manager = scheduleRulesInMemory(database, actingAs: 'manager');
    await manager.startEmptyMonth(month);
    seedStaffing(
      month,
      facts: {
        ('nurses', CoverageWindow.day, 3): (
          minimum: 2,
          shortfall: 2,
          openCount: 0,
          rnShortfall: 0,
        ),
        ('nurses', CoverageWindow.day, 9): (
          minimum: 1,
          shortfall: 1,
          openCount: 0,
          rnShortfall: 0,
        ),
        ('nurses', CoverageWindow.day, 14): (
          minimum: 0,
          shortfall: 0,
          openCount: 1,
          rnShortfall: 0,
        ),
      },
    );
    seedOpenDay(DateTime(2026, 10, 14));

    await pumpGrid(tester, month: month, withStaffing: true);
    await tester.tap(find.text('Release month'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('2 days are below a Staffing minimum: Oct 3, Oct 9'),
      findsOneWidget,
    );
    expect(
      find.textContaining('1 more day has an Open shift: Oct 14'),
      findsOneWidget,
    );
    expect(find.text('Acknowledge and release'), findsOneWidget);
  });

  testWidgets('Open shifts alone leave the release button unacknowledged', (
    tester,
  ) async {
    final month = DateTime(2026, 10);
    await scheduleRulesInMemory(
      database,
      actingAs: 'manager',
    ).startEmptyMonth(month);
    seedStaffing(
      month,
      facts: {
        ('nurses', CoverageWindow.day, 14): (
          minimum: 0,
          shortfall: 0,
          openCount: 1,
          rnShortfall: 0,
        ),
      },
    );
    seedOpenDay(DateTime(2026, 10, 14));

    await pumpGrid(tester, month: month, withStaffing: true);
    await tester.tap(find.text('Release month'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('1 day has an Open shift: Oct 14'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Release'), findsOneWidget);
  });

  testWidgets('confirm dialog uses the same Shortfall and Open shift reading', (
    tester,
  ) async {
    database.loadFromPage(september, const []);
    seedStaffing(
      september,
      facts: {
        ('nurses', CoverageWindow.day, 3): (
          minimum: 1,
          shortfall: 1,
          openCount: 0,
          rnShortfall: 0,
        ),
        ('nurses', CoverageWindow.day, 14): (
          minimum: 0,
          shortfall: 0,
          openCount: 1,
          rnShortfall: 0,
        ),
      },
    );
    seedOpenDay(DateTime(2026, 9, 14));

    await pumpGrid(tester, withStaffing: true);
    await tester.tap(find.text('Confirm month'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('1 day is below a Staffing minimum: Sep 3'),
      findsOneWidget,
    );
    expect(
      find.textContaining('1 more day has an Open shift: Sep 14'),
      findsOneWidget,
    );
    expect(find.text('Acknowledge and confirm'), findsOneWidget);
  });

  testWidgets('failed Loaded month confirmation uses confirm wording', (
    tester,
  ) async {
    database.loadFromPage(september, const []);
    await pumpGrid(tester);
    await tester.tap(find.text('Confirm month'));
    await tester.pumpAndSettle();
    database.failNext(
      InMemoryStoreCall.confirmLoadedMonth,
      StateError('write failed'),
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pump();
    expect(find.text("The month wasn't confirmed. Try again."), findsOneWidget);
  });

  testWidgets('Print sends the live month as the book page', (tester) async {
    final printed = _RecordingBookPagePresenter();
    final rules = await pumpGrid(tester, bookPagePresenter: printed);
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
    expect(find.text('Print the book page'), findsOneWidget);
    expect(printed.pages, isEmpty);
    await tester.tap(find.text('Open PDF'));
    await tester.pumpAndSettle();
    expect(printed.pages, hasLength(1));
    expect(
      printed.pages.single.layout.wording.notice,
      'Schedule subject to change',
    );
    expect(
      printed.pages.single.layout.wording.titleFor(september),
      contains('SEPTEMBER 2026'),
    );
    expect(
      printed.pages.single.layout.grid.shiftCodeFor('rn-2', september18),
      '4P-8A',
    );
    expect(printed.pages.single.pdf, isNotEmpty);
  });

  testWidgets('Print warns when one page will be hard to read', (tester) async {
    database = InMemoryScheduleDatabase(
      sections: const [days],
      rows: [
        for (var index = 0; index < 80; index++)
          ScheduleRow(
            staffMemberId: 'rn-$index',
            displayName: 'RN $index',
            sectionId: 'days',
          ),
      ],
      grants: {'manager': Grants(manager: true)},
      releasedMonths: {september},
    );
    final printed = _RecordingBookPagePresenter();
    await pumpGrid(tester, bookPagePresenter: printed);

    await tester.tap(find.byTooltip('Print the book page'));
    await tester.pumpAndSettle();
    expect(find.textContaining('80 Staff members'), findsOneWidget);
    expect(printed.pages, isEmpty);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(printed.pages, isEmpty);
  });

  testWidgets('Print names a cramped Shift code and its date', (tester) async {
    final printed = _RecordingBookPagePresenter();
    final rules = await pumpGrid(tester, bookPagePresenter: printed);
    await rules.saveCell(
      SaveCell(
        staffMemberId: 'rn-1',
        sectionId: 'days',
        date: september18,
        shiftCode: 'EXTRALONGCODEFORTHEDAY',
      ),
    );

    await tester.tap(find.byTooltip('Print the book page'));
    await tester.pumpAndSettle();
    expect(find.textContaining('EXTRALONGCODEFORTHEDAY'), findsWidgets);
    expect(find.textContaining('2026-9-18'), findsOneWidget);
    expect(printed.pages, isEmpty);
    await tester.tap(find.text('Open PDF'));
    await tester.pumpAndSettle();
    expect(
      printed.pages.single.causes.first.description,
      contains('EXTRALONGCODEFORTHEDAY'),
    );
  });

  testWidgets('Manager changes the print wording default for a draft month', (
    tester,
  ) async {
    final gateway = _TestPrintWordingGateway();
    final printed = _RecordingBookPagePresenter();
    await pumpGrid(
      tester,
      bookPagePresenter: printed,
      printWordingGateway: gateway,
    );

    await tester.tap(find.byTooltip('Change print wording'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Print this Schedule');
    await tester.enterText(find.byType(TextField).at(1), 'ER Schedule');
    await tester.pumpAndSettle();
    expect(find.text('Example: ER Schedule - SEPTEMBER 2026'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(gateway.wording.title, 'ER Schedule');
    expect(find.byTooltip('Print this Schedule'), findsOneWidget);
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Print this Schedule'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open PDF'));
    await tester.pumpAndSettle();
    expect(
      printed.pages.single.layout.wording.titleFor(DateTime(2026, 10)),
      'ER Schedule - OCTOBER 2026',
    );
  });

  testWidgets('editing the Unit default keeps a released month’s wording', (
    tester,
  ) async {
    final gateway = _TestCapturedPrintWordingGateway();
    final printed = _RecordingBookPagePresenter();
    await pumpGrid(
      tester,
      printWordingGateway: gateway,
      bookPagePresenter: printed,
    );
    expect(find.byTooltip('Historical print'), findsOneWidget);

    await tester.tap(find.byTooltip('Change print wording'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
      'Current default',
    );
    await tester.enterText(find.byType(TextField).at(0), 'New default');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(gateway.wording.tooltip, 'New default');
    expect(find.byTooltip('Historical print'), findsOneWidget);
    await tester.tap(find.byTooltip('Historical print'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open PDF'));
    await tester.pumpAndSettle();
    expect(printed.pages.single.layout.wording.tooltip, 'Historical print');
  });

  testWidgets('a blocked PDF shows the existing failure snackbar', (
    tester,
  ) async {
    await pumpGrid(tester, bookPagePresenter: _FailingBookPagePresenter());
    await tester.tap(find.byTooltip('Print the book page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open PDF'));
    await tester.pumpAndSettle();
    expect(find.text("The PDF couldn't be opened. Try again."), findsOneWidget);
  });

  testWidgets('correcting released wording changes only that month', (
    tester,
  ) async {
    final gateway = _TestCapturedPrintWordingGateway();
    final printed = _RecordingBookPagePresenter();
    await pumpGrid(
      tester,
      printWordingGateway: gateway,
      bookPagePresenter: printed,
    );

    await tester.tap(find.byTooltip('More destinations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Correct this month’s print wording'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Corrected print');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(gateway.historical.tooltip, 'Corrected print');
    expect(gateway.wording.tooltip, 'Current default');
    await tester.tap(find.byTooltip('Corrected print'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open PDF'));
    await tester.pumpAndSettle();
    expect(printed.pages.single.layout.wording.tooltip, 'Corrected print');
  });

  testWidgets('wording over 80 is retained for editing but refused on save', (
    tester,
  ) async {
    final gateway = _TestPrintWordingGateway();
    await pumpGrid(tester, printWordingGateway: gateway);
    await tester.tap(find.byTooltip('Change print wording'));
    await tester.pumpAndSettle();
    final pasted = 'x' * 81;
    await tester.enterText(find.byType(TextField).at(1), pasted);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Each field must be 80 characters or fewer.'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      pasted,
    );
    expect(gateway.wording.title, PrintTitleStyle.hospital.label);

    await tester.enterText(find.byType(TextField).at(1), '😀' * 41);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(gateway.wording.title, '😀' * 41);
  });

  testWidgets('blank title can be reset to default', (tester) async {
    await pumpGrid(tester, printWordingGateway: _TestPrintWordingGateway());
    await tester.tap(find.byTooltip('Change print wording'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(1), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('The title and tooltip are required.'), findsOneWidget);
    await tester.tap(find.text('Reset Printed title to default'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      PrintTitleStyle.hospital.label,
    );
  });

  testWidgets('Staff cannot change print wording', (tester) async {
    await pumpGrid(
      tester,
      actingAs: 'staff',
      staffMemberId: 'rn-1',
      bookPagePresenter: _RecordingBookPagePresenter(),
      printWordingGateway: _TestPrintWordingGateway(),
    );
    expect(find.byTooltip('Change print wording'), findsNothing);
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

    testWidgets('the Manager proofreads it and confirms it', (tester) async {
      await pumpGrid(tester);

      expect(find.text('4P-8A'), findsOneWidget);
      expect(find.textContaining('Proofread this month'), findsOneWidget);

      await tester.tap(find.text('Confirm month'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Proofread this month'), findsNothing);
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

final class _TestPrintWordingGateway implements PrintWordingGateway {
  PrintWording wording = const PrintWording();

  @override
  Future<PrintWording> read() async => wording;

  @override
  Future<PrintWording> readForMonth(DateTime month) => read();

  @override
  Future<void> save(PrintWording next) async {
    wording = next;
  }

  @override
  Future<void> correctMonth(DateTime month, PrintWording next) async {
    wording = next;
  }
}

final class _TestCapturedPrintWordingGateway implements PrintWordingGateway {
  PrintWording wording = const PrintWording(tooltip: 'Current default');
  PrintWording historical = const PrintWording(tooltip: 'Historical print');

  @override
  Future<PrintWording> read() async => wording;

  @override
  Future<PrintWording> readForMonth(DateTime month) async => historical;

  @override
  Future<void> save(PrintWording next) async {
    wording = next;
  }

  @override
  Future<void> correctMonth(DateTime month, PrintWording wording) async {
    historical = wording;
  }
}

final class _RecordingBookPagePresenter implements BookPagePresenter {
  final pages = <PreparedBookPage>[];

  @override
  void present(PreparedBookPage page) => pages.add(page);
}

final class _FailingBookPagePresenter implements BookPagePresenter {
  @override
  void present(PreparedBookPage page) => throw StateError('blocked');
}
