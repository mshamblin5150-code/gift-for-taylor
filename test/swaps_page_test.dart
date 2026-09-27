import 'package:er_schedule/schedule/swaps_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:schedule_rules_testing/schedule_rules_testing.dart';

const _section = ScheduleSection(id: 'nurses', name: 'Nurses');
const _alice = ScheduleRow(
  staffMemberId: 'alice',
  displayName: 'Alice',
  sectionId: 'nurses',
  hasAcceptedInvite: true,
);
const _bob = ScheduleRow(
  staffMemberId: 'bob',
  displayName: 'Bob',
  sectionId: 'nurses',
  hasAcceptedInvite: true,
);

InMemoryScheduleDatabase _swapPageDatabase(DateTime month) =>
    InMemoryScheduleDatabase(
      sections: const [_section],
      rows: const [_alice, _bob],
      releasedMonths: {month},
    );

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
      eligibleDates: {
        (alice.staffMemberId, bob.staffMemberId): [DateTime(2026, 9, 11)],
        (bob.staffMemberId, alice.staffMemberId): [DateTime(2026, 9, 12)],
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

  testWidgets('an empty proposal can pair two working shifts on one day', (
    tester,
  ) async {
    final now = DateTime(2026, 9, 10, 8);
    final month = DateTime(2026, 9);
    final date = DateTime(2026, 9, 11);
    final database = _swapPageDatabase(month);
    final manager = scheduleRulesInMemory(database, actingAs: 'manager');
    await manager.store.saveShiftCode(
      const LegendCode('7A', hours: '7A–7P', isWorking: true),
    );
    await manager.store.saveShiftCode(
      const LegendCode('7P', hours: '7P–7A', isWorking: true),
    );
    await manager.saveCell(
      SaveCell(
        staffMemberId: _alice.staffMemberId,
        sectionId: _section.id,
        date: date,
        shiftCode: '7A',
      ),
    );
    await manager.saveCell(
      SaveCell(
        staffMemberId: _bob.staffMemberId,
        sectionId: _section.id,
        date: date,
        shiftCode: '7P',
      ),
    );
    database.markAllAnnounced();
    final swaps = InMemorySwapDatabase(
      shifts: {
        (_alice.staffMemberId, date): '7A',
        (_bob.staffMemberId, date): '7P',
      },
      eligibleDates: {
        (_alice.staffMemberId, _bob.staffMemberId): [date],
        (_bob.staffMemberId, _alice.staffMemberId): [date],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SwapsPage(
          rules: scheduleRulesInMemory(
            database,
            actingAs: _alice.staffMemberId,
          ),
          swapStore: swaps.storeFor(_alice.staffMemberId),
          month: month,
          staffMemberId: _alice.staffMemberId,
          isManager: false,
          now: () => now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Propose a Swap'));
    await tester.pumpAndSettle();
    expect(find.text('Bob'), findsOneWidget);

    await tester.tap(find.text('Choose my shift'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sep 11 — 7A'));
    await tester.pumpAndSettle();
    expect(find.text('Bob must also offer Sep 11 — 7P.'), findsOneWidget);

    await tester.tap(find.text("Choose Bob's shift"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sep 11 — 7P'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Propose'));
    await tester.pumpAndSettle();

    final proposed =
        (await swaps.storeFor(_alice.staffMemberId).swaps()).single;
    expect(proposed.requesterShifts.single.date, date);
    expect(proposed.colleagueShifts.single.date, date);
  });

  testWidgets('Swap tile renders contiguous ranges and scattered dates', (
    tester,
  ) async {
    final month = DateTime(2027, 6);
    final database = _swapPageDatabase(month);
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

  testWidgets('requester can withdraw a proposed Swap', (tester) async {
    final month = DateTime(2027, 6);
    final database = _swapPageDatabase(month);
    final swaps = InMemorySwapDatabase(
      shifts: const {},
      swaps: [
        Swap(
          id: 'swap',
          requesterId: 'alice',
          colleagueId: 'bob',
          requesterShifts: [
            SwapShift(
              date: DateTime(2027, 6, 20),
              shiftCode: '7A',
              targetCode: 'X',
            ),
          ],
          colleagueShifts: [
            SwapShift(
              date: DateTime(2027, 6, 21),
              shiftCode: '7P',
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

    await tester.tap(find.byTooltip('Withdraw Swap'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Withdrawn by requester'), findsOneWidget);
    expect(find.byTooltip('Withdraw Swap'), findsNothing);
    expect(
      (await swaps.storeFor('alice').swaps()).single.status,
      SwapStatus.withdrawn,
    );
  });
}
