import 'package:er_schedule/schedule/shift_codes_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_rules/schedule_rules.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('Manager picks and edits 24-hour Shift code times at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rules = ScheduleRules.inMemory(
        InMemoryScheduleDatabase(
          sections: const [],
          editors: const {'manager'},
        ),
        actingAs: 'manager',
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
            child: child!,
          ),
          home: ShiftCodesPage(rules: rules),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add code'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Code'), 'NIGHT');

      Future<void> pick(String field, String hour, String minute) async {
        final button = find.byTooltip('Pick $field time');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        final dialog = find.byType(TimePickerDialog);
        expect(dialog, findsOneWidget);
        expect(
          MediaQuery.of(tester.element(dialog)).alwaysUse24HourFormat,
          isTrue,
        );
        await tester.tap(
          find.descendant(
            of: dialog,
            matching: find.byIcon(Icons.keyboard_outlined),
          ),
        );
        await tester.pumpAndSettle();
        final inputs = find.descendant(
          of: dialog,
          matching: find.byType(TextFormField),
        );
        expect(inputs, findsNWidgets(2));
        await tester.enterText(inputs.at(0), hour);
        await tester.enterText(inputs.at(1), minute);
        await tester.tap(
          find.descendant(of: dialog, matching: find.text('OK')),
        );
        await tester.pumpAndSettle();
      }

      await pick('Starts', '19', '00');
      await pick('Ends', '07', '00');
      expect(
        find.widgetWithText(TextField, 'Starts (HH:mm, optional)'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextField, 'Ends (HH:mm, optional)'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Starts (HH:mm, optional)'),
            )
            .controller!
            .text,
        '19:00',
      );
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Ends (HH:mm, optional)'),
            )
            .controller!
            .text,
        '07:00',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final saved = (await rules.shiftCodes()).singleWhere(
        (code) => code.code == 'NIGHT',
      );
      expect(saved.startTime, '19:00');
      expect(saved.endTime, '07:00');

      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('NIGHT'), 250);
      await tester.tap(find.text('NIGHT'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Pick Starts time'));
      await tester.pumpAndSettle();
      final dialog = find.byType(TimePickerDialog);
      expect(
        tester.widget<TimePickerDialog>(dialog).initialTime,
        const TimeOfDay(hour: 19, minute: 0),
      );
      await tester.tap(
        find.descendant(of: dialog, matching: find.text('Cancel')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Starts (HH:mm, optional)'),
            )
            .controller!
            .text,
        '19:00',
      );
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Ends (HH:mm, optional)'),
            )
            .controller!
            .text,
        '07:00',
      );
      await tester.tap(find.byTooltip('Pick Ends time'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TimePickerDialog>(find.byType(TimePickerDialog))
            .initialTime,
        const TimeOfDay(hour: 7, minute: 0),
      );
      await tester.tap(
        find.descendant(
          of: find.byType(TimePickerDialog),
          matching: find.text('Cancel'),
        ),
      );
      await tester.pumpAndSettle();
      await pick('Starts', '20', '15');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final edited = (await rules.shiftCodes()).singleWhere(
        (code) => code.code == 'NIGHT',
      );
      expect(edited.startTime, '20:15');
      expect(edited.endTime, '07:00');
    });
  }

  testWidgets('Manager can type Shift code times and must enter both', (
    tester,
  ) async {
    final rules = ScheduleRules.inMemory(
      InMemoryScheduleDatabase(sections: const [], editors: const {'manager'}),
      actingAs: 'manager',
    );
    await tester.pumpWidget(MaterialApp(home: ShiftCodesPage(rules: rules)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Code'), 'LATE');
    await tester.enterText(
      find.widgetWithText(TextField, 'Starts (HH:mm, optional)'),
      '19:30',
    );
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Add Shift code'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Ends (HH:mm, optional)'),
      '07:00',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final saved = (await rules.shiftCodes()).singleWhere(
      (code) => code.code == 'LATE',
    );
    expect(saved.startTime, '19:30');
    expect(saved.endTime, '07:00');
  });

  testWidgets('pasted overlong code and meaning are refused on save', (
    tester,
  ) async {
    final rules = ScheduleRules.inMemory(
      InMemoryScheduleDatabase(sections: const [], editors: const {'manager'}),
      actingAs: 'manager',
    );
    await tester.pumpWidget(MaterialApp(home: ShiftCodesPage(rules: rules)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add code'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Code'), 'C' * 9);
    await tester.enterText(
      find.widgetWithText(TextField, 'Meaning (optional)'),
      'M' * 41,
    );
    expect(find.text('C' * 9), findsOneWidget);
    expect(find.text('M' * 41), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.textContaining('Use at most 5 characters'), findsOneWidget);
    expect(find.text('Add Shift code'), findsOneWidget);
  });

  testWidgets('Manager sees working Shift codes whose times are missing', (
    tester,
  ) async {
    final database = InMemoryScheduleDatabase(
      sections: const [],
      editors: const {'manager'},
    );
    final rules = ScheduleRules.inMemory(database, actingAs: 'manager');
    await rules.saveShiftCode(const LegendCode('CUSTOM', isWorking: true));

    await tester.pumpWidget(MaterialApp(home: ShiftCodesPage(rules: rules)));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('without times appear as all-day'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(find.text('CUSTOM'), 250);
    expect(
      find.text('Time not set · No Coverage window · Worked shift'),
      findsWidgets,
    );
  });
}
