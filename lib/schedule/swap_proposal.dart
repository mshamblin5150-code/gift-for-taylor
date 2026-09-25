import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'messages_composer.dart';

final class SwapProposalChoice {
  const SwapProposalChoice({
    required this.colleague,
    required this.requesterDate,
    required this.colleagueDate,
  });

  final ScheduleRow colleague;
  final DateTime requesterDate;
  final DateTime colleagueDate;
}

Future<SwapProposalChoice?> showSwapProposalDialog(
  BuildContext context, {
  required ScheduleRules rules,
  required MonthGrid initialGrid,
  required String requesterId,
  required DateTime Function() now,
  ScheduleRow? fixedColleague,
  DateTime? fixedColleagueDate,
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
      now: now,
    ),
  );
}

Future<void> textSwapColleague(
  BuildContext context, {
  required Swap swap,
  required ScheduleRow colleague,
  required MessagesComposer? messagesComposer,
}) async {
  final number = colleague.cellNumber;
  if (number == null || messagesComposer == null) return;
  try {
    await messagesComposer.open(
      [number],
      'Hi ${colleague.displayName}, can we Swap my ${DateFormat.MMMd().format(swap.requesterDate)} '
      '${swap.requesterCode} shift for your ${DateFormat.MMMd().format(swap.colleagueDate)} '
      '${swap.colleagueCode} shift? Please answer in the ER Schedule app.',
    );
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

class _SwapProposalDialog extends StatefulWidget {
  const _SwapProposalDialog({
    required this.rules,
    required this.initialGrid,
    required this.requesterId,
    required this.codes,
    required this.colleagues,
    required this.fixedColleague,
    required this.fixedColleagueDate,
    required this.now,
  });

  final ScheduleRules rules;
  final MonthGrid initialGrid;
  final String requesterId;
  final List<LegendCode> codes;
  final List<ScheduleRow> colleagues;
  final ScheduleRow? fixedColleague;
  final DateTime? fixedColleagueDate;
  final DateTime Function() now;

  @override
  State<_SwapProposalDialog> createState() => _SwapProposalDialogState();
}

class _SwapProposalDialogState extends State<_SwapProposalDialog> {
  late ScheduleRow _colleague =
      widget.fixedColleague ?? widget.colleagues.first;
  DateTime? _requesterDate;
  late DateTime? _colleagueDate = widget.fixedColleagueDate;
  late MonthGrid _requesterGrid = widget.initialGrid;
  late MonthGrid _colleagueGrid = widget.initialGrid;

  Future<void> _pickRequesterDay() async {
    final picked = await _pickWorkingDay(
      context,
      rules: widget.rules,
      initialGrid: _requesterGrid,
      staffMemberId: widget.requesterId,
      codes: widget.codes,
      now: widget.now(),
      title: 'Choose my working shift',
    );
    if (picked != null && mounted) {
      setState(() {
        _requesterDate = picked.date;
        _requesterGrid = picked.grid;
      });
    }
  }

  Future<void> _pickColleagueDay() async {
    final picked = await _pickWorkingDay(
      context,
      rules: widget.rules,
      initialGrid: _colleagueGrid,
      staffMemberId: _colleague.staffMemberId,
      codes: widget.codes,
      now: widget.now(),
      title: "Choose ${_colleague.displayName}'s working shift",
    );
    if (picked != null && mounted) {
      setState(() {
        _colleagueDate = picked.date;
        _colleagueGrid = picked.grid;
      });
    }
  }

  String? get _unavailableReason {
    if (!_colleague.hasAcceptedInvite) {
      return '${_colleague.displayName} is not in the app yet.';
    }
    final requesterDate = _requesterDate;
    if (requesterDate == null) return 'Choose your working shift.';
    final colleagueDate = _colleagueDate;
    if (colleagueDate == null) {
      return "Choose ${_colleague.displayName}'s working shift.";
    }
    if (_requesterGrid.status != MonthStatus.released ||
        _colleagueGrid.status != MonthStatus.released) {
      return 'Both Schedule months must be released.';
    }
    if (!isFutureSwapDay(requesterDate, now: widget.now()) ||
        !isFutureSwapDay(colleagueDate, now: widget.now())) {
      return 'Swap shifts must be after today.';
    }
    final requesterCode =
        _requesterGrid.shiftCodeFor(widget.requesterId, requesterDate) ?? '';
    final colleagueCode =
        _colleagueGrid.shiftCodeFor(_colleague.staffMemberId, colleagueDate) ??
        '';
    if (!isWorkingShift(requesterCode, codes: widget.codes) ||
        !isWorkingShift(colleagueCode, codes: widget.codes)) {
      return 'Both days must still have working Shifts.';
    }
    if (_sameDay(requesterDate, colleagueDate)) {
      return requesterCode == colleagueCode
          ? 'Choose shifts that would change the Schedule.'
          : null;
    }
    final requesterTarget =
        _colleagueGrid.shiftCodeFor(widget.requesterId, colleagueDate) ?? '';
    final colleagueTarget =
        _requesterGrid.shiftCodeFor(_colleague.staffMemberId, requesterDate) ??
        '';
    if (!_isFree(requesterTarget) || !_isFree(colleagueTarget)) {
      return 'Both destination days must be off before this Swap can be proposed.';
    }
    return null;
  }

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
                  _colleagueDate = null;
                  _colleagueGrid = widget.initialGrid;
                }),
              )
            else
              Text(
                _colleague.displayName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('My shift'),
              subtitle: Text(
                _requesterDate == null
                    ? 'Choose my shift'
                    : _dayLabel(
                        _requesterGrid,
                        widget.requesterId,
                        _requesterDate!,
                      ),
              ),
              onTap: _pickRequesterDay,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Colleague shift'),
              subtitle: Text(
                _colleagueDate == null
                    ? "Choose ${_colleague.displayName}'s shift"
                    : _dayLabel(
                        _colleagueGrid,
                        _colleague.staffMemberId,
                        _colleagueDate!,
                      ),
              ),
              onTap: widget.fixedColleagueDate == null
                  ? _pickColleagueDay
                  : null,
            ),
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
                    requesterDate: _requesterDate!,
                    colleagueDate: _colleagueDate!,
                  ),
                )
              : null,
          child: const Text('Propose'),
        ),
      ],
    );
  }
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
  required String title,
}) => showDialog<_WorkingDaySelection>(
  context: context,
  builder: (context) => _WorkingDayPicker(
    rules: rules,
    initialGrid: initialGrid,
    staffMemberId: staffMemberId,
    codes: codes,
    now: now,
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
    required this.title,
  });

  final ScheduleRules rules;
  final MonthGrid initialGrid;
  final String staffMemberId;
  final List<LegendCode> codes;
  final DateTime now;
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
                        onTap: () => Navigator.pop(
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

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _isFree(String code) {
  final normalized = code.trim().toUpperCase();
  return normalized.isEmpty || normalized == 'X';
}
