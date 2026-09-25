import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'messages_composer.dart';

final class SwapProposalChoice {
  const SwapProposalChoice({
    required this.colleague,
    required this.requesterDates,
    required this.colleagueDates,
  });

  final ScheduleRow colleague;
  final List<DateTime> requesterDates;
  final List<DateTime> colleagueDates;
}

Future<SwapProposalChoice?> showSwapProposalDialog(
  BuildContext context, {
  required ScheduleRules rules,
  required MonthGrid initialGrid,
  required String requesterId,
  required DateTime Function() now,
  ScheduleRow? fixedColleague,
  DateTime? fixedColleagueDate,
  DateTime? fixedRequesterDate,
}) async {
  final codes = await rules.store.shiftCodes();
  if (!context.mounted) return null;
  final colleagues = fixedColleague == null
      ? initialGrid.rows
            .where(
              (row) =>
                  row.staffMemberId != requesterId && row.hasAcceptedInvite,
            )
            .toList(growable: false)
      : [fixedColleague];
  if (colleagues.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No colleagues who are in the app are on this Schedule.'),
      ),
    );
    return null;
  }
  return showDialog<SwapProposalChoice>(
    context: context,
    builder: (context) => _SwapProposalDialog(
      rules: rules,
      initialGrid: initialGrid,
      requesterId: requesterId,
      codes: codes,
      colleagues: colleagues,
      fixedColleague: fixedColleague,
      fixedColleagueDate: fixedColleagueDate,
      fixedRequesterDate: fixedRequesterDate,
      now: now,
    ),
  );
}

Future<void> textSwapColleague(
  BuildContext context, {
  required Swap swap,
  required ScheduleRow colleague,
  required SwapStore swapStore,
  required MessagesComposer? messagesComposer,
}) async {
  if (messagesComposer == null) return;
  try {
    final number =
        colleague.cellNumber ??
        await swapStore.colleagueCellNumberForSwap(swap.id);
    if (number == null) return;
    await messagesComposer.open([
      number,
    ], swapTextMessage(swap, colleague.displayName));
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Swap proposed. Messages could not open; try the text button again.',
          ),
        ),
      );
    }
  }
}

String swapSummary(Swap swap, {int maxLength = 96}) {
  return swapSummaryFor(swap, maxLength: maxLength);
}

enum SwapSummaryPerspective { requester, colleague, neutral }

String swapSummaryFor(
  Swap swap, {
  SwapSummaryPerspective perspective = SwapSummaryPerspective.requester,
  String? requesterName,
  String? colleagueName,
  int maxLength = 96,
}) {
  final (leftLabel, left, rightLabel, right) = switch (perspective) {
    SwapSummaryPerspective.requester => (
      'my',
      swap.requesterShifts,
      'your',
      swap.colleagueShifts,
    ),
    SwapSummaryPerspective.colleague => (
      'my',
      swap.colleagueShifts,
      'your',
      swap.requesterShifts,
    ),
    SwapSummaryPerspective.neutral => (
      '${requesterName ?? 'Requester'}’s',
      swap.requesterShifts,
      '${colleagueName ?? 'Colleague'}’s',
      swap.colleagueShifts,
    ),
  };
  final detailed =
      '$leftLabel ${_sideSummary(left)} for $rightLabel ${_sideSummary(right)}';
  if (detailed.length <= maxLength) return detailed;
  return '$leftLabel ${left.length} shifts for $rightLabel '
      '${right.length} shifts in ER Schedule';
}

String swapTextMessage(Swap swap, String colleagueName) {
  final prefix = 'Hi $colleagueName, can we Swap ';
  const suffix = '? Please answer in the ER Schedule app.';
  final detailed = swapSummaryFor(swap, maxLength: 1000);
  final summary = prefix.length + detailed.length + suffix.length <= 160
      ? detailed
      : swapSummaryFor(swap, maxLength: 0);
  return '$prefix$summary$suffix';
}

String swapProposalRefusalMessage(SwapProposalRefusal reason) =>
    switch (reason) {
      SwapProposalRefusal.differentStaffRequired =>
        'Choose another Staff member for this Swap.',
      SwapProposalRefusal.equalCountsRequired =>
        'Pick the same number of shifts for each Staff member.',
      SwapProposalRefusal.shiftLimitExceeded =>
        'A Swap can include at most 31 shifts for each Staff member.',
      SwapProposalRefusal.duplicateDate => 'Choose each shift only once.',
      SwapProposalRefusal.colleagueNotInvited =>
        'That colleague is not in the app yet.',
      SwapProposalRefusal.dayNotFuture => 'Swap shifts must be after today.',
      SwapProposalRefusal.sourceUnavailable =>
        'An offered shift changed or its Schedule is no longer released.',
      SwapProposalRefusal.destinationUnavailable =>
        'Someone is now working on a destination day. Choose another Swap.',
      SwapProposalRefusal.noChange =>
        'Choose shifts that would change the Schedule.',
    };

String _sideSummary(List<SwapShift> shifts) {
  final sorted = [...shifts]..sort((a, b) => a.date.compareTo(b.date));
  final dates = _dateRuns(sorted.map((shift) => shift.date).toList());
  final codes = sorted.map((shift) => shift.shiftCode).toSet();
  return codes.length == 1 ? '$dates ${codes.single}' : dates;
}

String _dateRuns(List<DateTime> dates) {
  final runs = <({DateTime start, DateTime end})>[];
  for (var start = 0; start < dates.length;) {
    var end = start;
    while (end + 1 < dates.length &&
        _day(dates[end]).add(const Duration(days: 1)) == _day(dates[end + 1])) {
      end++;
    }
    runs.add((start: dates[start], end: dates[end]));
    start = end + 1;
  }
  final sameMonth = dates.every(
    (date) => date.year == dates.first.year && date.month == dates.first.month,
  );
  final labels = <String>[
    for (final (index, run) in runs.indexed)
      if (sameMonth)
        '${index == 0 ? '${DateFormat.MMM().format(run.start)} ' : ''}'
            '${run.start.day}${run.start == run.end ? '' : '–${run.end.day}'}'
      else if (run.start == run.end)
        DateFormat.MMMd().format(run.start)
      else if (run.start.month == run.end.month)
        '${DateFormat.MMM().format(run.start)} ${run.start.day}–${run.end.day}'
      else
        '${DateFormat.MMMd().format(run.start)}–${DateFormat.MMMd().format(run.end)}',
  ];
  if (labels.length < 2) return labels.single;
  if (labels.length == 2) return '${labels.first} and ${labels.last}';
  return '${labels.sublist(0, labels.length - 1).join(', ')} and ${labels.last}';
}

class _SwapProposalDialog extends StatefulWidget {
  const _SwapProposalDialog({
    required this.rules,
    required this.initialGrid,
    required this.requesterId,
    required this.codes,
    required this.colleagues,
    required this.fixedColleague,
    required this.fixedColleagueDate,
    required this.fixedRequesterDate,
    required this.now,
  });

  final ScheduleRules rules;
  final MonthGrid initialGrid;
  final String requesterId;
  final List<LegendCode> codes;
  final List<ScheduleRow> colleagues;
  final ScheduleRow? fixedColleague;
  final DateTime? fixedColleagueDate;
  final DateTime? fixedRequesterDate;
  final DateTime Function() now;

  @override
  State<_SwapProposalDialog> createState() => _SwapProposalDialogState();
}

class _SwapProposalDialogState extends State<_SwapProposalDialog> {
  late ScheduleRow _colleague =
      widget.fixedColleague ?? widget.colleagues.first;
  late final Set<DateTime> _requesterDates = {
    if (widget.fixedRequesterDate case final date?) _day(date),
  };
  late final Set<DateTime> _colleagueDates = {
    if (widget.fixedColleagueDate case final date?) _day(date),
  };
  late final Map<DateTime, MonthGrid> _requesterGrids = {
    for (final date in _requesterDates) date: widget.initialGrid,
  };
  late final Map<DateTime, MonthGrid> _colleagueGrids = {
    for (final date in _colleagueDates) date: widget.initialGrid,
  };
  late MonthGrid _requesterPickerGrid = widget.initialGrid;
  late MonthGrid _colleaguePickerGrid = widget.initialGrid;

  Future<void> _pick({required bool requester}) async {
    final picked = await _pickWorkingDay(
      context,
      rules: widget.rules,
      initialGrid: requester ? _requesterPickerGrid : _colleaguePickerGrid,
      staffMemberId: requester ? widget.requesterId : _colleague.staffMemberId,
      codes: widget.codes,
      now: widget.now(),
      selectedDates: requester ? _requesterDates : _colleagueDates,
      title: requester
          ? 'Choose my working shift'
          : "Choose ${_colleague.displayName}'s working shift",
    );
    if (picked == null || !mounted) return;
    final date = _day(picked.date);
    setState(() {
      if (requester) {
        _requesterDates.add(date);
        _requesterGrids[date] = picked.grid;
        _requesterPickerGrid = picked.grid;
      } else {
        _colleagueDates.add(date);
        _colleagueGrids[date] = picked.grid;
        _colleaguePickerGrid = picked.grid;
      }
    });
  }

  String? get _unavailableReason {
    if (!_colleague.hasAcceptedInvite) {
      return '${_colleague.displayName} is not in the app yet.';
    }
    if (_requesterDates.isEmpty) {
      return 'Choose at least one of your working shifts.';
    }
    if (_colleagueDates.isEmpty) {
      return "Choose ${_colleague.displayName}'s working shift.";
    }
    if (_requesterDates.length != _colleagueDates.length) {
      final count = (_requesterDates.length - _colleagueDates.length).abs();
      return _requesterDates.length > _colleagueDates.length
          ? "Pick $count more of ${_colleague.displayName}'s ${count == 1 ? 'shift' : 'shifts'}."
          : 'Pick $count more of your ${count == 1 ? 'shift' : 'shifts'}.';
    }
    if (_requesterDates.length > 31) {
      return 'A Swap can include at most 31 shifts for each Staff member.';
    }
    return null;
  }

  bool get _noSingleColleagueCanTakeMine =>
      widget.fixedRequesterDate != null &&
      _requesterDates.isNotEmpty &&
      !widget.colleagues.any(
        (colleague) => _requesterDates.every((date) {
          final grid = _requesterGrids[date];
          return grid != null &&
              _isFree(grid.shiftCodeFor(colleague.staffMemberId, date) ?? '');
        }),
      );

  @override
  Widget build(BuildContext context) {
    final reason = _unavailableReason;
    return AlertDialog(
      title: const Text('Propose a Swap'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.fixedColleague == null)
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _colleague.staffMemberId,
                decoration: const InputDecoration(labelText: 'Colleague'),
                items: [
                  for (final row in widget.colleagues)
                    DropdownMenuItem(
                      value: row.staffMemberId,
                      child: Text(
                        row.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) => setState(() {
                  _colleague = widget.colleagues.firstWhere(
                    (row) => row.staffMemberId == id,
                  );
                  _colleagueDates.clear();
                  _colleagueGrids.clear();
                  _colleaguePickerGrid = widget.initialGrid;
                }),
              )
            else
              Text(
                _colleague.displayName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            _ShiftCart(
              title: 'My shifts',
              emptyLabel: 'Choose my shift',
              dates: _requesterDates,
              grids: _requesterGrids,
              staffMemberId: widget.requesterId,
              onAdd: () => _pick(requester: true),
              onRemove: (date) => setState(() {
                _requesterDates.remove(date);
                _requesterGrids.remove(date);
              }),
            ),
            _ShiftCart(
              title: "${_colleague.displayName}'s shifts",
              emptyLabel: "Choose ${_colleague.displayName}'s shift",
              dates: _colleagueDates,
              grids: _colleagueGrids,
              staffMemberId: _colleague.staffMemberId,
              onAdd: () => _pick(requester: false),
              onRemove: (date) => setState(() {
                _colleagueDates.remove(date);
                _colleagueGrids.remove(date);
              }),
            ),
            if (_noSingleColleagueCanTakeMine) ...[
              const SizedBox(height: 8),
              const Text(
                'No one colleague can take all these days. This would need two separate Swaps, and either can be declined on its own.',
              ),
            ],
            if (reason != null) ...[const SizedBox(height: 8), Text(reason)],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: reason == null
              ? () => Navigator.pop(
                  context,
                  SwapProposalChoice(
                    colleague: _colleague,
                    requesterDates: _sorted(_requesterDates),
                    colleagueDates: _sorted(_colleagueDates),
                  ),
                )
              : null,
          child: const Text('Propose'),
        ),
      ],
    );
  }
}

class _ShiftCart extends StatelessWidget {
  const _ShiftCart({
    required this.title,
    required this.emptyLabel,
    required this.dates,
    required this.grids,
    required this.staffMemberId,
    required this.onAdd,
    required this.onRemove,
  });

  final String title;
  final String emptyLabel;
  final Set<DateTime> dates;
  final Map<DateTime, MonthGrid> grids;
  final String staffMemberId;
  final VoidCallback onAdd;
  final ValueChanged<DateTime> onRemove;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 8),
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      if (dates.isEmpty)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(emptyLabel),
          onTap: onAdd,
        )
      else
        for (final date in _sorted(dates))
          InputChip(
            label: Text(_dayLabel(grids[date]!, staffMemberId, date)),
            onDeleted: () => onRemove(date),
          ),
      TextButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add),
        label: const Text('Add another shift'),
      ),
    ],
  );
}

final class _WorkingDaySelection {
  const _WorkingDaySelection(this.grid, this.date);
  final MonthGrid grid;
  final DateTime date;
}

Future<_WorkingDaySelection?> _pickWorkingDay(
  BuildContext context, {
  required ScheduleRules rules,
  required MonthGrid initialGrid,
  required String staffMemberId,
  required List<LegendCode> codes,
  required DateTime now,
  required Set<DateTime> selectedDates,
  required String title,
}) => showDialog<_WorkingDaySelection>(
  context: context,
  builder: (context) => _WorkingDayPicker(
    rules: rules,
    initialGrid: initialGrid,
    staffMemberId: staffMemberId,
    codes: codes,
    now: now,
    selectedDates: selectedDates,
    title: title,
  ),
);

class _WorkingDayPicker extends StatefulWidget {
  const _WorkingDayPicker({
    required this.rules,
    required this.initialGrid,
    required this.staffMemberId,
    required this.codes,
    required this.now,
    required this.selectedDates,
    required this.title,
  });

  final ScheduleRules rules;
  final MonthGrid initialGrid;
  final String staffMemberId;
  final List<LegendCode> codes;
  final DateTime now;
  final Set<DateTime> selectedDates;
  final String title;

  @override
  State<_WorkingDayPicker> createState() => _WorkingDayPickerState();
}

class _WorkingDayPickerState extends State<_WorkingDayPicker> {
  late MonthGrid _grid = widget.initialGrid;
  bool _loading = false;

  Future<void> _moveMonth(int offset) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final grid = await widget.rules.monthGrid(
        DateTime(_grid.month.year, _grid.month.month + offset),
      );
      if (mounted) setState(() => _grid = grid);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This month could not be loaded. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = _workingDays(
      _grid,
      widget.staffMemberId,
      widget.codes,
      widget.now,
    );
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        height: 360,
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: _loading ? null : () => _moveMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    DateFormat.yMMMM().format(_grid.month),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: _loading ? null : () => _moveMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_grid.status != MonthStatus.released)
              const Expanded(
                child: Center(
                  child: Text('This Schedule month is not released.'),
                ),
              )
            else if (days.isEmpty)
              const Expanded(
                child: Center(
                  child: Text('No future working shifts this month.'),
                ),
              )
            else
              Expanded(
                child: ListView(
                  children: [
                    for (final day in days)
                      ListTile(
                        title: Text(
                          _dayLabel(_grid, widget.staffMemberId, day),
                        ),
                        subtitle: widget.selectedDates.contains(_day(day))
                            ? const Text('Already selected')
                            : null,
                        onTap: widget.selectedDates.contains(_day(day))
                            ? null
                            : () => Navigator.pop(
                                context,
                                _WorkingDaySelection(_grid, day),
                              ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

List<DateTime> _workingDays(
  MonthGrid grid,
  String staffMemberId,
  List<LegendCode> codes,
  DateTime now,
) => [
  for (final day in grid.days)
    if (isFutureSwapDay(day, now: now) &&
        isWorkingShift(
          grid.shiftCodeFor(staffMemberId, day) ?? '',
          codes: codes,
        ))
      day,
];

String _dayLabel(MonthGrid grid, String staffMemberId, DateTime date) =>
    '${DateFormat.MMMd().format(date)} — ${grid.shiftCodeFor(staffMemberId, date)}';

List<DateTime> _sorted(Iterable<DateTime> dates) =>
    [...dates]..sort((a, b) => a.compareTo(b));

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

bool _isFree(String code) {
  final normalized = code.trim().toUpperCase();
  return normalized.isEmpty || normalized == 'X';
}
