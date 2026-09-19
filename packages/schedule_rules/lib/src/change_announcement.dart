part of '../schedule_rules.dart';

/// The unannounced changes in one month, as the tray shows them: each
/// affected Staff member with their own message, and one group message when
/// more than one person is affected.
final class ChangeAnnouncement {
  ChangeAnnouncement._(
    this._changeIds, {
    required this.month,
    required this.people,
  });

  /// Covers only rows in [editable], so a Night scheduler tells the people
  /// in their own Sections.
  factory ChangeAnnouncement._from(
    MonthGrid grid,
    Iterable<ScheduleChange> unannounced,
    EditableSections editable,
  ) {
    final sectionOf = {
      for (final row in grid.rows) row.staffMemberId: row.sectionId,
    };
    final people = <AffectedPerson>[];
    for (final row in grid.rows.where(
      (row) => editable.contains(row.sectionId),
    )) {
      final changedDays = [
        for (final day in grid.days)
          if (grid.isUnannounced(row.staffMemberId, day))
            ChangedDay(
              date: day,
              oldShiftCode: grid.publishedCodeFor(row.staffMemberId, day),
              newShiftCode: grid.shiftCodeFor(row.staffMemberId, day) ?? '',
            ),
      ];
      if (changedDays.isNotEmpty) {
        people.add(AffectedPerson._(row: row, changedDays: changedDays));
      }
    }
    return ChangeAnnouncement._(
      {
        for (final change in unannounced)
          if (editable.contains(sectionOf[change.staffMemberId] ?? ''))
            change.id,
      },
      month: grid.month,
      people: List.unmodifiable(people),
    );
  }

  final DateTime month;

  /// Only the people whose own shifts changed, in Section and row order.
  final List<AffectedPerson> people;

  /// Every unannounced change log entry read for this tray, including edits
  /// that were changed back, so marking it announced settles them all.
  final Set<String> _changeIds;

  bool get isEmpty => people.isEmpty;

  /// The number of changed days across everyone affected.
  int get changeCount =>
      people.fold(0, (count, person) => count + person.changedDays.length);

  /// The cell numbers for the group text; people with none are left out.
  List<String> get groupRecipients => groupMessage == null
      ? const []
      : [for (final person in people) ?person.cellNumber];

  /// One message covering everyone, when more than one person is affected.
  String? get groupMessage => people.length < 2
      ? null
      : [
          'ER Schedule changes:',
          for (final person in people) ...[
            '${person.row.displayName}:',
            ...person._dayLines,
          ],
        ].join('\n');
}

/// A Staff member whose own shifts changed.
final class AffectedPerson {
  AffectedPerson._({required this.row, required List<ChangedDay> changedDays})
    : changedDays = List.unmodifiable(changedDays);

  final ScheduleRow row;

  /// Each changed day, earliest first.
  final List<ChangedDay> changedDays;

  String? get cellNumber => row.cellNumber;

  String get message =>
      ['Hi ${row.displayName}, ER Schedule change:', ..._dayLines].join('\n');

  Iterable<String> get _dayLines => changedDays.map(
    (day) =>
        '${_shortDate(day.date)}: ${_spoken(day.newShiftCode)} '
        '(was ${_spoken(day.oldShiftCode)})',
  );
}

/// One day's change: the code last announced and the code now.
final class ChangedDay {
  const ChangedDay({
    required this.date,
    required this.oldShiftCode,
    required this.newShiftCode,
  });

  final DateTime date;
  final String oldShiftCode;
  final String newShiftCode;
}

String _spoken(String shiftCode) => switch (shiftCode) {
  '' => 'blank',
  'X' => 'off',
  _ => shiftCode,
};

String _shortDate(DateTime date) {
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${weekdays[date.weekday - 1]} ${date.month}/${date.day}';
}
