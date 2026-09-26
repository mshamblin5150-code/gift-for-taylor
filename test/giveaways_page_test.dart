import 'package:er_schedule/schedule/giveaways_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:schedule_rules_testing/schedule_rules_testing.dart';

void main() {
  final date = DateTime(2027, 10, 4);

  testWidgets('giver can withdraw while colleague can answer', (tester) async {
    final database = InMemoryGiveawayDatabase(
      shifts: {('giver', date): '7A'},
      giveaways: [
        Giveaway(
          id: 'giveaway',
          giverId: 'giver',
          colleagueId: 'colleague',
          shifts: [GiveawayShift(date: date, shiftCode: '7A', targetCode: 'X')],
          status: GiveawayStatus.proposed,
        ),
      ],
    );
    final schedule =
        InMemoryScheduleDatabase(
          sections: [const ScheduleSection(id: 'section', name: 'RN')],
          rows: [
            ScheduleRow(
              staffMemberId: 'giver',
              displayName: 'Giver RN',
              sectionId: 'section',
              hasAcceptedInvite: true,
            ),
            ScheduleRow(
              staffMemberId: 'colleague',
              displayName: 'Colleague RN',
              sectionId: 'section',
              hasAcceptedInvite: true,
            ),
          ],
          releasedMonths: {DateTime(2027, 10)},
        )..loadFromPage(DateTime(2027, 10), [
          ScheduleCell(
            staffMemberId: 'giver',
            sectionId: 'section',
            date: date,
            shiftCode: '7A',
          ),
        ]);

    Future<void> pumpAs(String viewer) => tester.pumpWidget(
      MaterialApp(
        home: GiveawaysPage(
          rules: scheduleRulesInMemory(schedule, actingAs: viewer),
          giveawayStore: database.storeFor(viewer),
          month: DateTime(2027, 10),
          staffMemberId: viewer,
        ),
      ),
    );

    await pumpAs('giver');
    await tester.pumpAndSettle();
    expect(find.byTooltip('Withdraw Giveaway'), findsOneWidget);
    await tester.tap(find.byTooltip('Withdraw Giveaway'));
    await tester.pumpAndSettle();
    expect(find.textContaining('withdrawn'), findsOneWidget);

    await database.storeFor('giver').proposeGiveaway('colleague', [date]);
    await tester.pumpWidget(const SizedBox());
    await pumpAs('colleague');
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuButton<bool>), findsOneWidget);
  });

  testWidgets('history does not show the Manager approval warning', (
    tester,
  ) async {
    final store = InMemoryGiveawayDatabase(
      shifts: {('giver', date): '7A'},
      giveaways: [
        Giveaway(
          id: 'accepted',
          giverId: 'giver',
          colleagueId: 'colleague',
          shifts: [GiveawayShift(date: date, shiftCode: '7A', targetCode: 'X')],
          status: GiveawayStatus.accepted,
          createsShortfall: true,
        ),
      ],
    ).storeFor('manager');
    final schedule = InMemoryScheduleDatabase(
      sections: [const ScheduleSection(id: 'section', name: 'RN')],
      rows: [
        ScheduleRow(
          staffMemberId: 'giver',
          displayName: 'Giver RN',
          sectionId: 'section',
        ),
        ScheduleRow(
          staffMemberId: 'colleague',
          displayName: 'Colleague LPN',
          sectionId: 'section',
        ),
      ],
      releasedMonths: {DateTime(2027, 10)},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: GiveawaysPage(
          rules: scheduleRulesInMemory(schedule, actingAs: 'manager'),
          giveawayStore: store,
          month: DateTime(2027, 10),
          staffMemberId: 'manager',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Shortfall'), findsNothing);
    expect(find.byTooltip('Approve Giveaway'), findsNothing);
  });
}
