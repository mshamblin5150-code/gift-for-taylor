import 'package:schedule_rules_testing/schedule_rules_testing.dart';
import 'package:er_schedule/schedule/month_grid_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'support/app_dependencies.dart';

/// The retry button remains a rendering and gesture check; read rules live in
/// month_session_test.dart.
void main() {
  const days = ScheduleSection(id: 'days', name: 'State dayshift RN');
  const dayNurse = ScheduleRow(
    staffMemberId: 'rn-1',
    displayName: 'Day RN',
    sectionId: 'days',
  );
  final september = DateTime(2026, 9);

  late InMemoryScheduleDatabase database;

  setUp(() {
    database = InMemoryScheduleDatabase(
      sections: const [days],
      rows: const [dayNurse],
      grants: {'manager': Grants(manager: true)},
      releasedMonths: {september},
    );
  });

  Future<void> pumpGrid(WidgetTester tester) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MonthGridPage(
          noticeGateway: const NoopNoticeGateway(),
          access: database.accessFor('manager'),
          rules: scheduleRulesInMemory(database, actingAs: 'manager'),
          month: september,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a failed month read shows the reason and can be retried', (
    tester,
  ) async {
    database.failNext(
      InMemoryStoreCall.sections,
      StateError('Could not read Schedule sections'),
    );
    await pumpGrid(tester);

    expect(find.text("The Schedule couldn't be loaded."), findsOneWidget);
    expect(
      find.textContaining('Could not read Schedule sections'),
      findsOneWidget,
    );
    expect(find.text('Day RN'), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text("The Schedule couldn't be loaded."), findsNothing);
    expect(find.text('Day RN'), findsOneWidget);
    expect(find.text('State dayshift RN'), findsOneWidget);
  });
}
