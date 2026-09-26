import 'package:er_schedule/schedule/month_session.dart';
import 'package:er_schedule/schedule/staff_cell_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

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
}
