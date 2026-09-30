import 'package:er_schedule/schedule/giveaway_proposal.dart';
import 'package:er_schedule/schedule/month_session.dart';
import 'package:er_schedule/schedule/staff_cell_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:schedule_rules_testing/schedule_rules_testing.dart';

void main() {
  testWidgets('own working-day selection offers Swap and Giveaway choices', (
    tester,
  ) async {
    const row = ScheduleRow(
      staffMemberId: 'giver',
      displayName: 'Giver RN',
      sectionId: 'rn',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showStaffCellSheet(
                context,
                row: row,
                date: DateTime(2027, 10, 4),
                review: const StaffCellReview(
                  currentCode: '7A',
                  swap: StaffCellSwapReview(),
                ),
                canGiveAway: true,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Swap these'), findsOneWidget);
    expect(find.text('Give these away'), findsOneWidget);
  });

  testWidgets('Giveaway picker lists only whole-set eligible colleagues', (
    tester,
  ) async {
    final date = DateTime(2027, 10, 4);
    final schedule =
        InMemoryScheduleDatabase(
          sections: [const ScheduleSection(id: 'rn', name: 'RN')],
          rows: const [
            ScheduleRow(
              staffMemberId: 'giver',
              displayName: 'Giver RN',
              sectionId: 'rn',
            ),
          ],
          releasedMonths: {DateTime(2027, 10)},
        )..loadFromPage(DateTime(2027, 10), [
          ScheduleCell(
            staffMemberId: 'giver',
            sectionId: 'rn',
            date: date,
            shiftCode: '7A',
          ),
        ]);
    final rules = scheduleRulesInMemory(schedule, actingAs: 'giver');
    await rules.store.saveShiftCode(
      const LegendCode('7A', hours: '7A–7P', isWorking: true),
    );
    final codes = await rules.store.shiftCodes();
    final grid = await rules.monthGrid(DateTime(2027, 10));
    final giveaways = InMemoryGiveawayDatabase(
      shifts: {('giver', date): '7A'},
      eligibleColleagues: const [
        GiveawayColleague(
          staffMemberId: 'colleague',
          displayName: 'Colleague RN',
        ),
      ],
    ).storeFor('giver');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showGiveawayProposalDialog(
                context,
                rules: rules,
                eligibleColleagues: giveaways.eligibleColleagues,
                initialGrid: grid,
                giverId: 'giver',
                codes: codes,
                now: () => DateTime(2027, 9, 1),
                initialDate: date,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Colleague RN'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Propose'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('Giveaway picker names a day that nobody can work', (
    tester,
  ) async {
    final date = DateTime(2027, 10, 4);
    final schedule =
        InMemoryScheduleDatabase(
          sections: [const ScheduleSection(id: 'rn', name: 'RN')],
          rows: const [
            ScheduleRow(
              staffMemberId: 'giver',
              displayName: 'Giver RN',
              sectionId: 'rn',
            ),
          ],
          releasedMonths: {DateTime(2027, 10)},
        )..loadFromPage(DateTime(2027, 10), [
          ScheduleCell(
            staffMemberId: 'giver',
            sectionId: 'rn',
            date: date,
            shiftCode: '7A',
          ),
        ]);
    final rules = scheduleRulesInMemory(schedule, actingAs: 'giver');
    final codes = await rules.store.shiftCodes();
    final grid = await rules.monthGrid(DateTime(2027, 10));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showGiveawayProposalDialog(
                context,
                rules: rules,
                eligibleColleagues: (_) async => const [],
                initialGrid: grid,
                giverId: 'giver',
                codes: codes,
                now: () => DateTime(2027, 9, 1),
                initialDate: date,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      find.text('No colleague in the app can work your Oct 4 7A.'),
      findsOneWidget,
    );
    expect(find.textContaining('Choose a smaller set'), findsNothing);
  });

  testWidgets('Giveaway picker excludes a Unit non-working Shift code', (
    tester,
  ) async {
    final offDate = DateTime(2027, 10, 4);
    final workingDate = DateTime(2027, 10, 5);
    final schedule = InMemoryScheduleDatabase(
      sections: [const ScheduleSection(id: 'rn', name: 'RN')],
      rows: const [
        ScheduleRow(
          staffMemberId: 'giver',
          displayName: 'Giver RN',
          sectionId: 'rn',
        ),
      ],
      shiftCodes: const [
        LegendCode('ZZ', isWorking: false),
        LegendCode('7A', hours: '7A–7P', isWorking: true),
      ],
      releasedMonths: {DateTime(2027, 10)},
    );
    final manager = scheduleRulesInMemory(schedule, actingAs: 'manager');
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'giver',
        sectionId: 'rn',
        date: offDate,
        shiftCode: 'ZZ',
      ),
    );
    await manager.saveCell(
      SaveCell(
        staffMemberId: 'giver',
        sectionId: 'rn',
        date: workingDate,
        shiftCode: '7A',
      ),
    );
    final rules = scheduleRulesInMemory(schedule, actingAs: 'giver');
    final codes = await rules.store.shiftCodes();
    final grid = await rules.monthGrid(DateTime(2027, 10));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showGiveawayProposalDialog(
                context,
                rules: rules,
                eligibleColleagues: (_) async => const [],
                initialGrid: grid,
                giverId: 'giver',
                codes: codes,
                now: () => DateTime(2027, 9, 1),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add my shift'));
    await tester.pumpAndSettle();

    expect(find.text('Oct 4 — ZZ'), findsNothing);
    expect(find.text('Oct 5 — 7A'), findsOneWidget);
  });

  testWidgets('Giveaway picker reports a failed month load', (tester) async {
    final schedule = InMemoryScheduleDatabase(
      sections: [const ScheduleSection(id: 'rn', name: 'RN')],
      rows: const [
        ScheduleRow(
          staffMemberId: 'giver',
          displayName: 'Giver RN',
          sectionId: 'rn',
        ),
      ],
      releasedMonths: {DateTime(2027, 10)},
    );
    final rules = scheduleRulesInMemory(schedule, actingAs: 'giver');
    final codes = await rules.store.shiftCodes();
    final grid = await rules.monthGrid(DateTime(2027, 10));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showGiveawayProposalDialog(
                context,
                rules: rules,
                eligibleColleagues: (_) async => const [],
                initialGrid: grid,
                giverId: 'giver',
                codes: codes,
                now: () => DateTime(2027, 9, 1),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add my shift'));
    await tester.pumpAndSettle();

    schedule.failNext(InMemoryStoreCall.sections, Exception('offline'));
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog).last,
        matching: find.byIcon(Icons.chevron_right),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('This month could not be loaded. Try again.'),
      findsOneWidget,
    );
  });
}
