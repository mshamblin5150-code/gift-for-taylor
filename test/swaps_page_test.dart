import 'package:er_schedule/schedule/swaps_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:schedule_rules_testing/schedule_rules_testing.dart';

void main() {
  testWidgets('Swap choices begin tomorrow', (tester) async {
    final now = DateTime(2026, 9, 10, 8);
    final month = DateTime(2026, 9);
    const section = ScheduleSection(id: 'nurses', name: 'Nurses');
    const alice = ScheduleRow(
      staffMemberId: 'alice',
      displayName: 'Alice',
      sectionId: 'nurses',
      cellNumber: '5551112222',
      hasAcceptedInvite: true,
    );
    const bob = ScheduleRow(
      staffMemberId: 'bob',
      displayName: 'Bob',
      sectionId: 'nurses',
      cellNumber: '5553334444',
      hasAcceptedInvite: true,
    );
    const charlie = ScheduleRow(
      staffMemberId: 'charlie',
      displayName: 'Charlie',
      sectionId: 'nurses',
      cellNumber: '5556667777',
    );
    final database = InMemoryScheduleDatabase(
      sections: const [section],
      rows: const [alice, bob, charlie],
      grants: {'manager': Grants(manager: true)},
      releasedMonths: {month},
    );
    final manager = scheduleRulesInMemory(database, actingAs: 'manager');
    for (final date in [
      DateTime(2026, 9, 9),
      DateTime(2026, 9, 10),
      DateTime(2026, 9, 11),
    ]) {
      await manager.saveCell(
        SaveCell(
          staffMemberId: alice.staffMemberId,
          sectionId: section.id,
          date: date,
          shiftCode: '7A',
        ),
      );
    }
    await manager.saveCell(
      SaveCell(
        staffMemberId: bob.staffMemberId,
        sectionId: section.id,
        date: DateTime(2026, 9, 12),
        shiftCode: '7P',
      ),
    );
    await manager.saveCell(
      SaveCell(
        staffMemberId: charlie.staffMemberId,
        sectionId: section.id,
        date: DateTime(2026, 9, 13),
        shiftCode: '7P',
      ),
    );
    final swaps = InMemorySwapDatabase(
      shifts: {
        (alice.staffMemberId, DateTime(2026, 9, 11)): '7A',
        (bob.staffMemberId, DateTime(2026, 9, 12)): '7P',
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SwapsPage(
          rules: scheduleRulesInMemory(database, actingAs: alice.staffMemberId),
          swapStore: swaps.storeFor(alice.staffMemberId),
          month: month,
          staffMemberId: alice.staffMemberId,
          isManager: false,
          now: () => now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Propose a Swap'));
    await tester.pumpAndSettle();

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Charlie'), findsNothing);
    expect(find.byType(CalendarDatePicker), findsNothing);

    await tester.tap(find.text('Choose my shift'));
    await tester.pumpAndSettle();
    expect(find.text('Sep 9 — 7A'), findsNothing);
    expect(find.text('Sep 10 — 7A'), findsNothing);
    await tester.tap(find.text('Sep 11 — 7A'));
    await tester.pumpAndSettle();

    await tester.tap(find.text("Choose Bob's shift"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sep 12 — 7P'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Propose'));
    await tester.pumpAndSettle();

    final proposed = (await swaps.storeFor(alice.staffMemberId).swaps()).single;
    expect(proposed.colleagueId, bob.staffMemberId);
    expect(proposed.requesterShifts.single.date, DateTime(2026, 9, 11));
    expect(proposed.colleagueShifts.single.date, DateTime(2026, 9, 12));
  });

  testWidgets('Swap tile renders contiguous ranges and scattered dates', (
    tester,
  ) async {
    final month = DateTime(2027, 6);
    const section = ScheduleSection(id: 'nurses', name: 'Nurses');
    const alice = ScheduleRow(
      staffMemberId: 'alice',
      displayName: 'Alice',
      sectionId: 'nurses',
      hasAcceptedInvite: true,
    );
    const bob = ScheduleRow(
      staffMemberId: 'bob',
      displayName: 'Bob',
      sectionId: 'nurses',
      hasAcceptedInvite: true,
    );
    final database = InMemoryScheduleDatabase(
      sections: const [section],
      rows: const [alice, bob],
      releasedMonths: {month},
    );
    final swaps = InMemorySwapDatabase(
      shifts: const {},
      swaps: [
        Swap(
          id: 'swap',
          requesterId: 'alice',
          colleagueId: 'bob',
          requesterShifts: [
            for (final day in [20, 21, 22])
              SwapShift(
                date: DateTime(2027, 6, day),
                shiftCode: '7P',
                targetCode: 'X',
              ),
          ],
          colleagueShifts: [
            for (final day in [3, 5, 9])
              SwapShift(
                date: DateTime(2027, 7, day),
                shiftCode: '7A',
                targetCode: 'X',
              ),
          ],
          status: SwapStatus.proposed,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SwapsPage(
          rules: scheduleRulesInMemory(database, actingAs: 'alice'),
          swapStore: swaps.storeFor('alice'),
          month: month,
          staffMemberId: 'alice',
          isManager: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('my Jun 20–22 7P for your Jul 3, 5 and 9 7A'),
      findsOneWidget,
    );
  });
}
