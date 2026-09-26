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
    final changes = unannounced.toList();
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
              swapId: changes
                  .where(
                    (change) =>
                        change.staffMemberId == row.staffMemberId &&
                        _sameDay(change.date, day),
                  )
                  .lastOrNull
                  ?.swapId,
              giveawayId: changes
                  .where(
                    (change) =>
                        change.staffMemberId == row.staffMemberId &&
                        _sameDay(change.date, day),
                  )
                  .lastOrNull
                  ?.giveawayId,
            ),
      ];
      if (changedDays.isNotEmpty) {
        people.add(AffectedPerson._(row: row, changedDays: changedDays));
      }
    }
    return ChangeAnnouncement._(
      {
        for (final change in changes)
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

  /// Every pending change log entry read for this tray, including edits
  /// that were changed back, so marking settles them all.
  final Set<String> _changeIds;

  bool get isEmpty => people.isEmpty;

  /// Includes pending edits that netted back to their announced baseline.
  bool get hasPendingChanges => _changeIds.isNotEmpty;

  /// The number of changed days across everyone affected.
  int get changeCount =>
      people.fold(0, (count, person) => count + person.changedDays.length);

  /// The cell numbers for the group text; people with none are left out.
  List<String> get groupRecipients => groupMessage == null
      ? const []
      : [for (final person in textFallbacks) ?person.cellNumber];

  /// People who need a text because a notification will not reach them.
  Iterable<AffectedPerson> get textFallbacks => people.where(
    (person) => !person.row.hasPushSubscription && person.cellNumber != null,
  );

  /// One message covering everyone, when more than one person is affected.
  String? get groupMessage => textFallbacks.length < 2
      ? null
      : [
          'ER Schedule changes:',
          for (final person in textFallbacks) ...[
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

  Iterable<String> get _dayLines sync* {
    final groups = <String, List<ChangedDay>>{};
    for (final (index, day) in changedDays.indexed) {
      final key = day.swapId != null
          ? 'swap:${day.swapId}'
          : day.giveawayId != null
          ? 'giveaway:${day.giveawayId}'
          : 'standalone:$index';
      groups.putIfAbsent(key, () => []).add(day);
    }
    for (final days in groups.values) {
      final isSwap = days.first.swapId != null;
      final isGiveaway = days.first.giveawayId != null;
      if (isSwap) yield 'Swap:';
      if (isGiveaway) yield 'Giveaway:';
      for (final day in days) {
        yield '${isSwap || isGiveaway ? '  ' : ''}${_shortDate(day.date)}: '
            '${_spoken(day.newShiftCode)} (was ${_spoken(day.oldShiftCode)})';
      }
    }
  }
}

/// One day's change: the code last announced and the code now.
final class ChangedDay {
  const ChangedDay({
    required this.date,
    required this.oldShiftCode,
    required this.newShiftCode,
    this.swapId,
    this.giveawayId,
  });

  final DateTime date;
  final String oldShiftCode;
  final String newShiftCode;
  final String? swapId;
  final String? giveawayId;
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
