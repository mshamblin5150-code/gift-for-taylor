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
    );
    const bob = ScheduleRow(
      staffMemberId: 'bob',
      displayName: 'Bob',
      sectionId: 'nurses',
      cellNumber: '5553334444',
    );
    final database = InMemoryScheduleDatabase(
      sections: const [section],
      rows: const [alice, bob],
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
    final swaps = InMemorySwapDatabase(shifts: const {});

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

    expect(find.text('Sep 11 — 7A'), findsOneWidget);
    expect(find.text('Sep 12 — 7P'), findsOneWidget);

    await tester.tap(find.text('Sep 11 — 7A'));
    await tester.pumpAndSettle();
    final picker = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    expect(picker.firstDate, DateTime(2026, 9, 11));
    expect(picker.initialDate, DateTime(2026, 9, 11));
  });
}
