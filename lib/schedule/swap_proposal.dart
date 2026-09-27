import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'messages_composer.dart';
import 'proposal_disclosure.dart';

String swapStatusWording(SwapStatus status) => switch (status) {
  SwapStatus.proposed => 'Proposed',
  SwapStatus.accepted => 'Accepted',
  SwapStatus.declined => 'Declined',
  SwapStatus.approved => 'Approved',
  SwapStatus.withdrawn => 'Withdrawn by requester',
  SwapStatus.voided => 'Voided because the Schedule changed',
};

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
  required SwapStore swapStore,
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
      swapStore: swapStore,
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
      SwapProposalRefusal.pickupIneligible =>
        'A Staff member cannot work one of those shifts.',
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
    required this.swapStore,
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
  final SwapStore swapStore;
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
  Map<String, Set<DateTime>> _colleagueEligibility = const {};
  Set<DateTime> _requesterEligibility = const {};
  bool _loadingEligibility = true;
  bool _loadedEligibilityOnce = false;
  late bool _selectionEstablished = widget.fixedColleague != null;
  int _eligibilityRequest = 0;

  @override
  void initState() {
    super.initState();
    _refreshEligibility();
  }

  Future<void> _refreshEligibility() async {
    final request = ++_eligibilityRequest;
    if (mounted) setState(() => _loadingEligibility = true);
    final requesterCandidates = _requesterDates.isEmpty
        ? _workingDays(
            widget.initialGrid,
            widget.requesterId,
            widget.codes,
            widget.now(),
          )
        : _sorted(_requesterDates);
    final results = await Future.wait([
      for (final colleague in widget.colleagues)
        widget.swapStore.eligibleSwapDates(
          widget.requesterId,
          colleague.staffMemberId,
          requesterCandidates,
        ),
    ]);
    final requesterEligibility = await widget.swapStore.eligibleSwapDates(
      _colleague.staffMemberId,
      widget.requesterId,
      _sorted(_colleagueDates),
    );
    if (!mounted || request != _eligibilityRequest) return;
    final eligibility = {
      for (final (index, colleague) in widget.colleagues.indexed)
        colleague.staffMemberId: {
          for (final date in results[index].map(_day))
            if ((_requesterDates.isEmpty
                    ? widget.initialGrid
                    : _requesterGrids[date])
                case final grid?
                when _destinationCanBecomeAvailable(
                  grid,
                  colleague.staffMemberId,
                  date,
                  _colleagueDates,
                  widget.codes,
                ))
              date,
        },
    };
    final availableRequesterDates = {
      for (final date in requesterEligibility.map(_day))
        if (_colleagueGrids[date] case final grid?
            when _destinationCanBecomeAvailable(
              grid,
              widget.requesterId,
              date,
              _requesterDates,
              widget.codes,
            ))
          date,
    };
    final qualifying = widget.colleagues.where((colleague) {
      final eligible = eligibility[colleague.staffMemberId] ?? const {};
      return _coversRequestedDates(eligible, _requesterDates);
    }).toList();
    setState(() {
      _colleagueEligibility = eligibility;
      _requesterEligibility = availableRequesterDates;
      if (!_loadedEligibilityOnce &&
          widget.fixedColleague == null &&
          qualifying.isNotEmpty) {
        if (!qualifying.contains(_colleague)) _colleague = qualifying.first;
        _selectionEstablished = true;
      }
      _loadedEligibilityOnce = true;
      _loadingEligibility = false;
    });
  }

  Future<void> _pick({required bool requester}) async {
    final picked = await _pickWorkingDay(
      context,
      rules: widget.rules,
      initialGrid: requester ? _requesterPickerGrid : _colleaguePickerGrid,
      staffMemberId: requester ? widget.requesterId : _colleague.staffMemberId,
      codes: widget.codes,
      now: widget.now(),
      selectedDates: requester ? _requesterDates : _colleagueDates,
      swapStore: widget.swapStore,
      fromStaffMemberId: requester
          ? widget.requesterId
          : _colleague.staffMemberId,
      toStaffMemberId: requester
          ? _colleague.staffMemberId
          : widget.requesterId,
      toOfferedDates: requester ? _colleagueDates : _requesterDates,
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
    await _refreshEligibility();
  }

  String? get _unavailableReason {
    if (!_colleague.hasAcceptedInvite) {
      return '${_colleague.displayName} is not in the app yet.';
    }
    if (_loadingEligibility) return 'Checking who can work these shifts…';
    final colleagueEligible =
        _colleagueEligibility[_colleague.staffMemberId] ?? const {};
    for (final date in _sorted(_requesterDates)) {
      if (!colleagueEligible.contains(date)) {
        return "${_colleague.displayName} can't work your ${_dayLabel(_requesterGrids[date]!, widget.requesterId, date)}.";
      }
      final grid = _requesterGrids[date]!;
      if (!_destinationAvailable(
        grid,
        _colleague.staffMemberId,
        date,
        _colleagueDates,
      )) {
        return '${_colleague.displayName} must also offer '
            '${_dayLabel(grid, _colleague.staffMemberId, date)}.';
      }
    }
    for (final date in _sorted(_colleagueDates)) {
      if (!_requesterEligibility.contains(date)) {
        return "You can't work ${_colleague.displayName}'s ${_dayLabel(_colleagueGrids[date]!, _colleague.staffMemberId, date)}.";
      }
      final grid = _colleagueGrids[date]!;
      if (!_destinationAvailable(
        grid,
        widget.requesterId,
        date,
        _requesterDates,
      )) {
        return 'You must also offer '
            '${_dayLabel(grid, widget.requesterId, date)}.';
      }
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

  List<DateTime> get _uncoveredRequesterDates => [
    for (final date in _sorted(_requesterDates))
      if (!_colleagueEligibility.values.any((dates) => dates.contains(date)))
        date,
  ];

  bool get _noSingleColleagueCanTakeMine =>
      _requesterDates.isNotEmpty &&
      _uncoveredRequesterDates.isEmpty &&
      !widget.colleagues.any((colleague) {
        final eligible =
            _colleagueEligibility[colleague.staffMemberId] ?? const {};
        return _requesterDates.every(eligible.contains);
      });

  @override
  Widget build(BuildContext context) {
    final reason = _unavailableReason;
    final eligibleColleagues = widget.colleagues.where((colleague) {
      final eligible =
          _colleagueEligibility[colleague.staffMemberId] ?? const {};
      return _coversRequestedDates(eligible, _requesterDates);
    }).toList();
    final dropdownColleagues = <ScheduleRow>[
      if (_selectionEstablished && !eligibleColleagues.contains(_colleague))
        _colleague,
      ...eligibleColleagues,
    ];
    return AlertDialog(
      title: const Text('Propose a Swap'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.fixedColleague == null && dropdownColleagues.isNotEmpty)
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _colleague.staffMemberId,
                decoration: const InputDecoration(labelText: 'Colleague'),
                items: [
                  for (final row in dropdownColleagues)
                    DropdownMenuItem(
                      value: row.staffMemberId,
                      child: Text(
                        row.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) {
                  setState(() {
                    _colleague = widget.colleagues.firstWhere(
                      (row) => row.staffMemberId == id,
                    );
                    _selectionEstablished = true;
                    _colleagueDates.clear();
                    _colleagueGrids.clear();
                    _colleaguePickerGrid = widget.initialGrid;
                  });
                  _refreshEligibility();
                },
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
              onRemove: (date) {
                setState(() {
                  _requesterDates.remove(date);
                  _requesterGrids.remove(date);
                });
                _refreshEligibility();
              },
            ),
            _ShiftCart(
              title: "${_colleague.displayName}'s shifts",
              emptyLabel: "Choose ${_colleague.displayName}'s shift",
              dates: _colleagueDates,
              grids: _colleagueGrids,
              staffMemberId: _colleague.staffMemberId,
              onAdd: () => _pick(requester: false),
              onRemove: (date) {
                setState(() {
                  _colleagueDates.remove(date);
                  _colleagueGrids.remove(date);
                });
                _refreshEligibility();
              },
            ),
            if (_uncoveredRequesterDates.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                noColleagueCanWorkMessage([
                  for (final date in _uncoveredRequesterDates)
                    '${DateFormat.MMMd().format(date)} '
                            '${_requesterGrids[date]?.shiftCodeFor(widget.requesterId, date) ?? ''}'
                        .trim(),
                ]),
              ),
            ] else if (_noSingleColleagueCanTakeMine) ...[
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
  required SwapStore swapStore,
  required String fromStaffMemberId,
  required String toStaffMemberId,
  required Set<DateTime> toOfferedDates,
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
    swapStore: swapStore,
    fromStaffMemberId: fromStaffMemberId,
    toStaffMemberId: toStaffMemberId,
    toOfferedDates: {...toOfferedDates},
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
    required this.swapStore,
    required this.fromStaffMemberId,
    required this.toStaffMemberId,
    required this.toOfferedDates,
    required this.title,
  });

  final ScheduleRules rules;
  final MonthGrid initialGrid;
  final String staffMemberId;
  final List<LegendCode> codes;
  final DateTime now;
  final Set<DateTime> selectedDates;
  final SwapStore swapStore;
  final String fromStaffMemberId;
  final String toStaffMemberId;
  final Set<DateTime> toOfferedDates;
  final String title;

  @override
  State<_WorkingDayPicker> createState() => _WorkingDayPickerState();
}

class _WorkingDayPickerState extends State<_WorkingDayPicker> {
  late MonthGrid _grid = widget.initialGrid;
  bool _loading = true;
  Set<DateTime> _eligibleDates = const {};

  @override
  void initState() {
    super.initState();
    _refreshEligibility();
  }

  Future<void> _refreshEligibility() async {
    final candidates = _workingDays(
      _grid,
      widget.staffMemberId,
      widget.codes,
      widget.now,
    );
    final dates = await widget.swapStore.eligibleSwapDates(
      widget.fromStaffMemberId,
      widget.toStaffMemberId,
      candidates,
    );
    if (mounted) {
      setState(() {
        _eligibleDates = {
          for (final date in dates.map(_day))
            if (_destinationCanBecomeAvailable(
              _grid,
              widget.toStaffMemberId,
              date,
              widget.toOfferedDates,
              widget.codes,
            ))
              date,
        };
        _loading = false;
      });
    }
  }

  Future<void> _moveMonth(int offset) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final grid = await widget.rules.monthGrid(
        DateTime(_grid.month.year, _grid.month.month + offset),
      );
      if (mounted) setState(() => _grid = grid);
      await _refreshEligibility();
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
    ).where((date) => _eligibleDates.contains(_day(date))).toList();
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

bool _coversRequestedDates(Set<DateTime> eligible, Set<DateTime> requested) =>
    requested.isEmpty
    ? eligible.isNotEmpty
    : requested.every(eligible.contains);

bool _destinationAvailable(
  MonthGrid grid,
  String staffMemberId,
  DateTime date,
  Set<DateTime> offeredDates,
) {
  final code = grid.shiftCodeFor(staffMemberId, date)?.trim().toUpperCase();
  return code == null ||
      code.isEmpty ||
      code == 'X' ||
      offeredDates.contains(date);
}

bool _destinationCanBecomeAvailable(
  MonthGrid grid,
  String staffMemberId,
  DateTime date,
  Set<DateTime> offeredDates,
  List<LegendCode> codes,
) {
  if (_destinationAvailable(grid, staffMemberId, date, offeredDates)) {
    return true;
  }
  final destinationCode = grid.shiftCodeFor(staffMemberId, date);
  return codes.any(
    (code) =>
        code.isWorking &&
        code.code.trim().toUpperCase() == destinationCode?.trim().toUpperCase(),
  );
}
