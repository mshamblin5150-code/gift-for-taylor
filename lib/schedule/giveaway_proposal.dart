import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'messages_composer.dart';

final class GiveawayProposalChoice {
  const GiveawayProposalChoice({required this.colleague, required this.dates});
  final GiveawayColleague colleague;
  final List<DateTime> dates;
}

Future<GiveawayProposalChoice?> showGiveawayProposalDialog(
  BuildContext context, {
  required ScheduleRules rules,
  required GiveawayStore giveawayStore,
  required MonthGrid initialGrid,
  required String giverId,
  required DateTime Function() now,
  DateTime? initialDate,
}) => showDialog<GiveawayProposalChoice>(
  context: context,
  builder: (context) => _GiveawayProposalDialog(
    rules: rules,
    giveawayStore: giveawayStore,
    initialGrid: initialGrid,
    giverId: giverId,
    now: now,
    initialDate: initialDate,
  ),
);

Future<void> textGiveawayColleague(
  BuildContext context, {
  required Giveaway giveaway,
  required GiveawayColleague colleague,
  required GiveawayStore giveawayStore,
  required MessagesComposer? messagesComposer,
}) async {
  if (messagesComposer == null) return;
  try {
    final number = await giveawayStore.colleagueCellNumberForGiveaway(
      giveaway.id,
    );
    if (number == null) return;
    final dates = giveaway.shifts
        .map(
          (shift) =>
              '${DateFormat.MMMd().format(shift.date)} ${shift.shiftCode}',
        )
        .join(', ');
    await messagesComposer.open(
      [number],
      'Hi ${colleague.displayName}, can I give you $dates? Please answer in the ER Schedule app.',
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Giveaway proposed. Messages could not open.'),
        ),
      );
    }
  }
}

String giveawayProposalRefusalMessage(GiveawayProposalRefusal reason) =>
    switch (reason) {
      GiveawayProposalRefusal.differentStaffRequired =>
        'Choose another Staff member for this Giveaway.',
      GiveawayProposalRefusal.shiftsRequired => 'Choose at least one shift.',
      GiveawayProposalRefusal.shiftLimitExceeded =>
        'A Giveaway can include at most 31 shifts.',
      GiveawayProposalRefusal.duplicateDate => 'Choose each shift only once.',
      GiveawayProposalRefusal.colleagueNotInvited =>
        'That colleague is not in the app yet.',
      GiveawayProposalRefusal.dayNotFuture =>
        'Giveaway shifts must be after today.',
      GiveawayProposalRefusal.sourceUnavailable =>
        'A selected shift changed or its Schedule is no longer released.',
      GiveawayProposalRefusal.colleagueIneligible =>
        'That colleague can no longer take every selected shift.',
    };

class _GiveawayProposalDialog extends StatefulWidget {
  const _GiveawayProposalDialog({
    required this.rules,
    required this.giveawayStore,
    required this.initialGrid,
    required this.giverId,
    required this.now,
    required this.initialDate,
  });
  final ScheduleRules rules;
  final GiveawayStore giveawayStore;
  final MonthGrid initialGrid;
  final String giverId;
  final DateTime Function() now;
  final DateTime? initialDate;

  @override
  State<_GiveawayProposalDialog> createState() =>
      _GiveawayProposalDialogState();
}

class _GiveawayProposalDialogState extends State<_GiveawayProposalDialog> {
  late final Set<DateTime> _dates = {
    if (widget.initialDate case final date?) _day(date),
  };
  late MonthGrid _pickerGrid = widget.initialGrid;
  List<GiveawayColleague> _colleagues = const [];
  String? _colleagueId;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refreshColleagues();
  }

  Future<void> _refreshColleagues() async {
    if (_dates.isEmpty) {
      setState(() {
        _colleagues = const [];
        _colleagueId = null;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final colleagues = await widget.giveawayStore.eligibleColleagues(
        _sorted(_dates),
      );
      if (!mounted) return;
      setState(() {
        _colleagues = colleagues;
        if (!colleagues.any((c) => c.staffMemberId == _colleagueId)) {
          _colleagueId = colleagues.firstOrNull?.staffMemberId;
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick() async {
    final picked = await showDialog<({MonthGrid grid, DateTime date})>(
      context: context,
      builder: (context) => _GiveawayDayPicker(
        rules: widget.rules,
        initialGrid: _pickerGrid,
        giverId: widget.giverId,
        now: widget.now(),
        selected: _dates,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _dates.add(_day(picked.date));
      _pickerGrid = picked.grid;
    });
    await _refreshColleagues();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _colleagues
        .where((c) => c.staffMemberId == _colleagueId)
        .firstOrNull;
    return AlertDialog(
      title: const Text('Give these away'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final date in _sorted(_dates))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(DateFormat.yMMMd().format(date)),
                trailing: IconButton(
                  tooltip: 'Remove shift',
                  onPressed: () {
                    setState(() => _dates.remove(date));
                    _refreshColleagues();
                  },
                  icon: const Icon(Icons.close),
                ),
              ),
            OutlinedButton.icon(
              onPressed: _dates.length >= 31 ? null : _pick,
              icon: const Icon(Icons.add),
              label: const Text('Add my shift'),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_dates.isEmpty)
              const Text('Choose at least one of your future working shifts.')
            else if (_colleagues.isEmpty)
              const Text(
                'No one colleague can take all these days. Choose a smaller set of shifts.',
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _colleagueId,
                decoration: const InputDecoration(labelText: 'Colleague'),
                items: [
                  for (final colleague in _colleagues)
                    DropdownMenuItem(
                      value: colleague.staffMemberId,
                      child: Text(colleague.displayName),
                    ),
                ],
                onChanged: (value) => setState(() => _colleagueId = value),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: selected == null || _dates.isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  GiveawayProposalChoice(
                    colleague: selected,
                    dates: _sorted(_dates),
                  ),
                ),
          child: const Text('Propose'),
        ),
      ],
    );
  }
}

class _GiveawayDayPicker extends StatefulWidget {
  const _GiveawayDayPicker({
    required this.rules,
    required this.initialGrid,
    required this.giverId,
    required this.now,
    required this.selected,
  });
  final ScheduleRules rules;
  final MonthGrid initialGrid;
  final String giverId;
  final DateTime now;
  final Set<DateTime> selected;

  @override
  State<_GiveawayDayPicker> createState() => _GiveawayDayPickerState();
}

class _GiveawayDayPickerState extends State<_GiveawayDayPicker> {
  late MonthGrid _grid = widget.initialGrid;
  bool _loading = false;

  Future<void> _move(int offset) async {
    setState(() => _loading = true);
    try {
      final grid = await widget.rules.monthGrid(
        DateTime(_grid.month.year, _grid.month.month + offset),
      );
      if (mounted) setState(() => _grid = grid);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dates = [
      for (final date in _grid.days)
        if (isFutureSwapDay(date, now: widget.now) &&
            isWorkingShift(_grid.shiftCodeFor(widget.giverId, date) ?? ''))
          date,
    ];
    return AlertDialog(
      title: const Text('Choose my working shift'),
      content: SizedBox(
        width: 360,
        height: 360,
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: _loading ? null : () => _move(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    DateFormat.yMMMM().format(_grid.month),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  onPressed: _loading ? null : () => _move(1),
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
            else
              Expanded(
                child: ListView(
                  children: [
                    for (final date in dates)
                      ListTile(
                        title: Text(
                          '${DateFormat.MMMd().format(date)} — '
                          '${_grid.shiftCodeFor(widget.giverId, date)}',
                        ),
                        subtitle: widget.selected.contains(_day(date))
                            ? const Text('Already selected')
                            : null,
                        onTap: widget.selected.contains(_day(date))
                            ? null
                            : () => Navigator.pop(context, (
                                grid: _grid,
                                date: date,
                              )),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

List<DateTime> _sorted(Iterable<DateTime> dates) =>
    [...dates]..sort((a, b) => a.compareTo(b));
DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);
