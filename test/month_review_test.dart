import 'package:er_schedule/schedule/month_grid_page.dart';
import 'package:er_schedule/schedule/schedule_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

void main() {
  const days = ScheduleSection(id: 'days', name: 'State dayshift RN');
  final october = DateTime(2026, 10);

  testWidgets('Manager reviews the loaded month, corrects a cell, and confirms', (
    tester,
  ) async {
    final gateway = _FakeScheduleGateway(canEdit: true);
    await tester.pumpWidget(
      MonthGridPage.testable(
        month: october,
        sections: const [days],
        scheduleGateway: gateway,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Page Nurse'), findsOneWidget);
    expect(find.text('4P-8A'), findsOneWidget);
    expect(find.textContaining('Check this month'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cell-page-2026-10-01')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Shift code'), '7P');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(gateway.savedCode, '7P');
    expect(gateway.savedDate, DateTime(2026, 10, 1));
    expect(find.text('7P'), findsOneWidget);
    expect(find.text('4P-8A'), findsNothing);

    await tester.tap(find.text('Confirm month'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(gateway.confirmedMonth, october);
    expect(find.textContaining('Check this month'), findsNothing);
  });

  testWidgets('Staff member sees the month but cannot edit or confirm it', (
    tester,
  ) async {
    final gateway = _FakeScheduleGateway(canEdit: false);
    await tester.pumpWidget(
      MonthGridPage.testable(
        month: october,
        sections: const [days],
        scheduleGateway: gateway,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('4P-8A'), findsOneWidget);
    expect(find.text('Confirm month'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('cell-page-2026-10-01')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Shift code'), findsNothing);
  });

  testWidgets('Manager moves to the next month', (tester) async {
    final gateway = _FakeScheduleGateway(canEdit: true);
    await tester.pumpWidget(
      MonthGridPage.testable(
        month: DateTime(2026, 9),
        sections: const [days],
        scheduleGateway: gateway,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Page Nurse'), findsNothing);

    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();

    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('Page Nurse'), findsOneWidget);
  });
}

final class _FakeScheduleGateway implements ScheduleGateway {
  _FakeScheduleGateway({required this.canEdit});

  final bool canEdit;
  String code = '4P-8A';
  bool confirmed = false;
  String? savedCode;
  DateTime? savedDate;
  DateTime? confirmedMonth;

  @override
  Future<bool> canEditSchedule() async => canEdit;

  @override
  Future<MonthGrid> loadMonth(DateTime month) async {
    const days = ScheduleSection(id: 'days', name: 'State dayshift RN');
    if (month != DateTime(2026, 10)) {
      return const MonthGrid(sections: [days], cells: []);
    }
    return MonthGrid(
      sections: const [days],
      rows: const [
        ScheduleRow(
          staffMemberId: 'page',
          displayName: 'Page Nurse',
          sectionId: 'days',
        ),
      ],
      cells: [
        ScheduleCell(
          staffMemberId: 'page',
          sectionId: 'days',
          date: DateTime(2026, 10, 1),
          shiftCode: code,
        ),
      ],
      started: true,
      awaitingConfirmation: !confirmed,
    );
  }

  @override
  Future<void> saveCell({
    required String staffMemberId,
    required DateTime date,
    required String shiftCode,
  }) async {
    savedCode = shiftCode;
    savedDate = date;
    code = shiftCode;
  }

  @override
  Future<void> confirmMonth(DateTime month) async {
    confirmedMonth = month;
    confirmed = true;
  }
}
