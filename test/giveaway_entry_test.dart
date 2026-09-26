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

  testWidgets('Giveaway picker explains when nobody can take the whole set', (
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
    final grid = await rules.monthGrid(DateTime(2027, 10));
    final giveaways = InMemoryGiveawayDatabase(shifts: {('giver', date): '7A'})
        .storeFor('giver');

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
      find.textContaining('No one colleague can take all these days'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Propose'))
          .onPressed,
      isNull,
    );
  });
}
