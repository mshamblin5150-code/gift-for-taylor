import 'package:schedule_rules_testing/schedule_rules_testing.dart';
import 'package:er_schedule/schedule/messages_composer.dart';
import 'package:er_schedule/schedule/month_grid_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

void main() {
  const days = ScheduleSection(id: 'days', name: 'State dayshift RN');
  const dana = ScheduleRow(
    staffMemberId: 'rn-1',
    displayName: 'Dana Reyes',
    sectionId: 'days',
    cellNumber: '5550100',
  );
  const lee = ScheduleRow(
    staffMemberId: 'rn-2',
    displayName: 'Lee Park',
    sectionId: 'days',
    cellNumber: '5550102',
  );
  final september = DateTime(2026, 9);
  final september18 = DateTime(2026, 9, 18);

  late InMemoryScheduleDatabase database;
  late _FakeMessagesComposer messages;

  setUp(() {
    database = InMemoryScheduleDatabase(
      sections: const [days],
      rows: const [dana, lee],
      editors: const {'manager'},
      releasedMonths: {september},
    );
    messages = _FakeMessagesComposer();
  });

  Future<void> save(ScheduleRow row, String code) {
    return scheduleRulesInMemory(database, actingAs: 'manager').saveCell(
      SaveCell(
        staffMemberId: row.staffMemberId,
        sectionId: row.sectionId,
        date: september18,
        shiftCode: code,
      ),
    );
  }

  Future<void> pumpGrid(
    WidgetTester tester, {
    String actingAs = 'manager',
    DateTime Function()? now,
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MonthGridPage(
          access: database.accessFor(actingAs),
          rules: scheduleRulesInMemory(database, actingAs: actingAs),
          month: september,
          messagesComposer: messages,
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('no tray when there is nothing to announce', (tester) async {
    await pumpGrid(tester);

    expect(find.textContaining('unannounced'), findsNothing);
  });

  testWidgets('the tray appears after an edit and shows the count', (
    tester,
  ) async {
    await pumpGrid(tester);

    await tester.tap(find.byKey(const ValueKey('cell-rn-1-2026-09-18')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '7A'));
    await tester.pumpAndSettle();

    expect(find.text('1 unannounced change'), findsOneWidget);
  });

  testWidgets('each affected person gets a prefilled text', (tester) async {
    await save(dana, 'X');
    await pumpGrid(tester);

    await tester.tap(find.text('Announce'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Lee Park'),
      ),
      findsNothing,
    );
    expect(
      find.text(
        'Hi Dana Reyes, ER Schedule change:\nFri 9/18: off (was blank)',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Group text'), findsNothing);
    await tester.tap(find.text('Text Dana Reyes'));
    await tester.pumpAndSettle();

    expect(messages.opened.single.$1, ['5550100']);
    expect(messages.opened.single.$2, startsWith('Hi Dana Reyes'));
  });

  testWidgets('a multi-person change has a group text to everyone', (
    tester,
  ) async {
    await save(dana, 'X');
    await save(lee, 'N');
    await pumpGrid(tester);
    expect(find.text('2 unannounced changes'), findsOneWidget);

    await tester.tap(find.text('Announce'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Group text all 2'));
    await tester.pumpAndSettle();

    expect(messages.opened.single.$1, ['5550100', '5550102']);
    expect(messages.opened.single.$2, startsWith('ER Schedule changes:'));
  });

  testWidgets('failed announcement shows retry wording', (tester) async {
    await save(dana, 'X');
    await pumpGrid(tester);
    await tester.tap(find.text('Announce'));
    await tester.pumpAndSettle();
    database.failNext(
      InMemoryStoreCall.markChangesAnnounced,
      StateError('write failed'),
    );
    await tester.tap(find.text('Mark announced'));
    await tester.pump();
    expect(
      find.text("The changes weren't marked announced. Try again."),
      findsOneWidget,
    );
  });

  testWidgets('a reverted-only batch can be cleared without a text', (
    tester,
  ) async {
    await save(dana, 'X');
    await save(dana, '');
    await pumpGrid(tester);

    expect(
      find.text('Changes reverted to their announced values'),
      findsOneWidget,
    );
    await tester.tap(find.text('Clear reverted changes'));
    await tester.pumpAndSettle();

    expect(
      find.text('Changes reverted to their announced values'),
      findsNothing,
    );
    expect(messages.opened, isEmpty);
  });

  testWidgets('someone who cannot edit sees no tray', (tester) async {
    await save(dana, 'X');
    await pumpGrid(tester, actingAs: 'rn-1');

    expect(find.text('1 unannounced change'), findsNothing);
  });

  testWidgets('a subscribed Staff member needs no text', (tester) async {
    const subscribed = ScheduleRow(
      staffMemberId: 'rn-3',
      displayName: 'Robin Hall',
      sectionId: 'days',
      hasPushSubscription: true,
    );
    database = InMemoryScheduleDatabase(
      sections: const [days],
      rows: const [subscribed],
      editors: const {'manager'},
      releasedMonths: {september},
    );
    await save(subscribed, '7A');
    await pumpGrid(tester);

    await tester.tap(find.text('Announce'));
    await tester.pumpAndSettle();
    expect(find.text('Will be notified · no text needed'), findsOneWidget);
    expect(find.textContaining('Nobody will be told'), findsNothing);
    expect(find.textContaining('Text Robin Hall'), findsNothing);
    await tester.tap(find.text('Mark announced'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More destinations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change log'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Reach: Notified'), findsOneWidget);
  });

  testWidgets('an Unreached change points to the filtered Change log', (
    tester,
  ) async {
    const unreachable = ScheduleRow(
      staffMemberId: 'rn-3',
      displayName: 'Robin Hall',
      sectionId: 'days',
    );
    database = InMemoryScheduleDatabase(
      sections: const [days],
      rows: const [unreachable],
      editors: const {'manager'},
      releasedMonths: {september},
    );
    await save(unreachable, '7A');
    await pumpGrid(tester, now: () => DateTime(2026, 9, 17));

    await tester.tap(find.text('Announce'));
    await tester.pumpAndSettle();
    expect(
      find.text('Nobody will be told · no notification or cell number'),
      findsOneWidget,
    );
    await tester.tap(find.text('Mark announced'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining("wasn't reached about changes"));
    await tester.pumpAndSettle();
    expect(find.textContaining('Reach: Nobody'), findsOneWidget);
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Unreached'))
          .selected,
      isTrue,
    );
  });

  testWidgets('the weekly pointer includes changes across a month boundary', (
    tester,
  ) async {
    const unreachable = ScheduleRow(
      staffMemberId: 'rn-3',
      displayName: 'Robin Hall',
      sectionId: 'days',
    );
    final october = DateTime(2026, 10);
    database = InMemoryScheduleDatabase(
      sections: const [days],
      rows: const [unreachable],
      editors: const {'manager'},
      releasedMonths: {september, october},
    );
    final manager = scheduleRulesInMemory(database, actingAs: 'manager');
    await manager.saveCell(
      SaveCell(
        staffMemberId: unreachable.staffMemberId,
        sectionId: days.id,
        date: DateTime(2026, 10, 1),
        shiftCode: '7A',
      ),
    );
    await manager.markAnnounced(await manager.changeAnnouncement(october));
    await pumpGrid(tester, now: () => DateTime(2026, 9, 30));

    await tester.tap(find.textContaining("wasn't reached about changes"));
    await tester.pumpAndSettle();
    expect(find.text('Change log · this week'), findsOneWidget);
    expect(find.textContaining('Robin Hall · Thu 1'), findsOneWidget);
    expect(find.textContaining('Reach: Nobody'), findsOneWidget);
  });
}

final class _FakeMessagesComposer implements MessagesComposer {
  final opened = <(List<String>, String)>[];

  @override
  Future<void> open(List<String> cellNumbers, String body) async {
    opened.add((cellNumbers, body));
  }
}
