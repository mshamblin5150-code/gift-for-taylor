import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'messages_composer.dart';

class SwapsPage extends StatefulWidget {
  const SwapsPage({
    super.key,
    required this.rules,
    required this.swapRules,
    required this.month,
    required this.staffMemberId,
    required this.isManager,
    this.messagesComposer,
  });

  final ScheduleRules rules;
  final SwapRules swapRules;
  final DateTime month;
  final String? staffMemberId;
  final bool isManager;
  final MessagesComposer? messagesComposer;

  @override
  State<SwapsPage> createState() => _SwapsPageState();
}

class _SwapsPageState extends State<SwapsPage> {
  late Future<(MonthGrid, List<Swap>)> _data = _load();
  StreamSubscription<void>? _updates;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _updates = widget.swapRules.updates().listen((_) => _refresh());
  }

  @override
  void dispose() {
    _updates?.cancel();
    super.dispose();
  }

  Future<(MonthGrid, List<Swap>)> _load() async => (
    await widget.rules.monthGrid(widget.month),
    await widget.swapRules.swaps(),
  );

  void _refresh() => setState(() => _data = _load());

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _refresh();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _propose(MonthGrid grid) async {
    final me = widget.staffMemberId;
    if (me == null) return;
    final colleagues = grid.rows
        .where((row) => row.staffMemberId != me && row.cellNumber != null)
        .toList();
    final myDays = _workingDays(grid, me);
    if (colleagues.isEmpty || myDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No eligible colleague or working shift this month.'),
        ),
      );
      return;
    }
    var colleague = colleagues.first;
    var mine = myDays.first;
    var theirs = _workingDays(grid, colleague.staffMemberId).firstOrNull;
    final choice = await showDialog<(ScheduleRow, DateTime, DateTime)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theirDays = _workingDays(grid, colleague.staffMemberId);
          return AlertDialog(
            title: const Text('Propose a Swap'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: colleague.staffMemberId,
                  decoration: const InputDecoration(labelText: 'Colleague'),
                  items: [
                    for (final row in colleagues)
                      DropdownMenuItem(
                        value: row.staffMemberId,
                        child: Text(row.displayName),
                      ),
                  ],
                  onChanged: (id) => setDialogState(() {
                    colleague = colleagues.firstWhere(
                      (row) => row.staffMemberId == id,
                    );
                    theirs = _workingDays(
                      grid,
                      colleague.staffMemberId,
                    ).firstOrNull;
                  }),
                ),
                DropdownButtonFormField<DateTime>(
                  key: ValueKey('mine-${mine.toIso8601String()}'),
                  initialValue: mine,
                  decoration: const InputDecoration(labelText: 'My shift'),
                  items: [
                    for (final date in myDays)
                      DropdownMenuItem(
                        value: date,
                        child: Text(_dayLabel(grid, me, date)),
                      ),
                  ],
                  onChanged: (date) => setDialogState(() => mine = date!),
                ),
                if (theirDays.isNotEmpty)
                  DropdownButtonFormField<DateTime>(
                    key: ValueKey(colleague.staffMemberId),
                    initialValue: theirs,
                    decoration: const InputDecoration(
                      labelText: 'Colleague shift',
                    ),
                    items: [
                      for (final date in theirDays)
                        DropdownMenuItem(
                          value: date,
                          child: Text(
                            _dayLabel(grid, colleague.staffMemberId, date),
                          ),
                        ),
                    ],
                    onChanged: (date) => setDialogState(() => theirs = date),
                  )
                else
                  const Text('This colleague has no working shift this month.'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: theirs == null
                    ? null
                    : () => Navigator.pop(context, (colleague, mine, theirs!)),
                child: const Text('Propose'),
              ),
            ],
          );
        },
      ),
    );
    if (choice == null) return;
    await _run(() async {
      final (row, myDate, theirDate) = choice;
      final swap = await widget.swapRules.propose(
        row.staffMemberId,
        myDate,
        theirDate,
      );
      final number = row.cellNumber;
      if (number != null && widget.messagesComposer != null) {
        await widget.messagesComposer!.open(
          [number],
          'Hi ${row.displayName}, can we Swap my ${DateFormat.MMMd().format(myDate)} '
          '${swap.requesterCode} shift for your ${DateFormat.MMMd().format(theirDate)} '
          '${swap.colleagueCode} shift? Please answer in the ER Schedule app.',
        );
      }
    });
  }

  Future<void> _answer(Swap swap, bool accept) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(accept ? 'Accept Swap' : 'Decline Swap'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Reason (optional)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(accept ? 'Accept' : 'Decline'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null) return;
    await _run(
      () => widget.swapRules.answer(swap.id, accept: accept, reason: reason),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Swaps'),
      actions: [
        IconButton(
          tooltip: 'Refresh Swaps',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<(MonthGrid, List<Swap>)>(
      future: _data,
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return Center(
            child: snapshot.hasError
                ? Text(snapshot.error.toString())
                : const CircularProgressIndicator(),
          );
        final (grid, swaps) = snapshot.data!;
        return ListView(
          children: [
            if (widget.staffMemberId != null &&
                grid.status == MonthStatus.released &&
                !_busy)
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: () => _propose(grid),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Propose a Swap'),
                ),
              ),
            if (swaps.isEmpty) const ListTile(title: Text('No Swaps yet.')),
            for (final swap in swaps)
              Card(
                child: ListTile(
                  title: Text(
                    '${grid.displayNameOf(swap.requesterId)} ↔ '
                    '${grid.displayNameOf(swap.colleagueId)}',
                  ),
                  subtitle: Text(
                    '${DateFormat.MMMd().format(swap.requesterDate)} '
                    '${swap.requesterCode} ↔ ${DateFormat.MMMd().format(swap.colleagueDate)} '
                    '${swap.colleagueCode}\n${swap.status.name}'
                    '${swap.reason == null ? '' : ' — ${swap.reason}'}',
                  ),
                  isThreeLine: true,
                  trailing: _busy
                      ? null
                      : swap.status == SwapStatus.proposed &&
                            swap.colleagueId == widget.staffMemberId
                      ? PopupMenuButton<bool>(
                          tooltip: 'Answer Swap',
                          onSelected: (accept) => _answer(swap, accept),
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: true, child: Text('Accept')),
                            PopupMenuItem(value: false, child: Text('Decline')),
                          ],
                        )
                      : swap.status == SwapStatus.accepted && widget.isManager
                      ? FilledButton(
                          onPressed: () =>
                              _run(() => widget.swapRules.approve(swap.id)),
                          child: const Text('Approve'),
                        )
                      : null,
                ),
              ),
          ],
        );
      },
    ),
  );
}

List<DateTime> _workingDays(MonthGrid grid, String id) {
  final start = DateTime(grid.month.year, grid.month.month);
  final length = DateTime(grid.month.year, grid.month.month + 1, 0).day;
  return [
    for (var day = 1; day <= length; day++)
      if (isWorkingShift(
        grid.shiftCodeFor(id, DateTime(start.year, start.month, day)) ?? '',
      ))
        DateTime(start.year, start.month, day),
  ];
}

String _dayLabel(MonthGrid grid, String id, DateTime date) =>
    '${DateFormat.MMMd().format(date)} — ${grid.shiftCodeFor(id, date)}';
