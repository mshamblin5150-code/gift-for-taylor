import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'messages_composer.dart';

class SwapsPage extends StatefulWidget {
  const SwapsPage({
    super.key,
    required this.rules,
    required this.swapStore,
    required this.month,
    required this.staffMemberId,
    required this.isManager,
    this.messagesComposer,
    this.now = DateTime.now,
  });

  final ScheduleRules rules;
  final SwapStore swapStore;
  final DateTime month;
  final String? staffMemberId;
  final bool isManager;
  final MessagesComposer? messagesComposer;
  final DateTime Function() now;

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
    _updates = widget.swapStore.updates().listen((_) => _refresh());
  }

  @override
  void dispose() {
    _updates?.cancel();
    super.dispose();
  }

  Future<(MonthGrid, List<Swap>)> _load() async => (
    await widget.rules.monthGrid(widget.month),
    await widget.swapStore.swaps(),
  );

  void _refresh() => setState(() => _data = _load());

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _propose(MonthGrid grid) async {
    final me = widget.staffMemberId;
    if (me == null) return;
    final codes = await widget.rules.store.shiftCodes();
    if (!mounted) return;
    final colleagues = grid.rows
        .where((row) => row.staffMemberId != me && row.cellNumber != null)
        .toList();
    final now = widget.now();
    final firstSwapDay = firstFutureSwapDay(now);
    final myDays = _workingDays(grid, me, codes, now);
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
    var mineGrid = grid;
    var theirs = _workingDays(
      grid,
      colleague.staffMemberId,
      codes,
      now,
    ).firstOrNull;
    var theirGrid = grid;
    final choice = await showDialog<(ScheduleRow, DateTime, DateTime)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Propose a Swap'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: colleague.staffMemberId,
                    decoration: const InputDecoration(labelText: 'Colleague'),
                    items: [
                      for (final row in colleagues)
                        DropdownMenuItem(
                          value: row.staffMemberId,
                          child: Text(
                            row.displayName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) => setDialogState(() {
                      colleague = colleagues.firstWhere(
                        (row) => row.staffMemberId == id,
                      );
                      theirs = _workingDays(
                        grid,
                        colleague.staffMemberId,
                        codes,
                        now,
                      ).firstOrNull;
                      theirGrid = grid;
                    }),
                  ),
                  ListTile(
                    title: const Text('My shift'),
                    subtitle: Text(_dayLabel(mineGrid, me, mine)),
                    onTap: () async {
                      final date = await _pickDate(context, mine, firstSwapDay);
                      if (date == null) return;
                      final loaded = await _gridOn(date);
                      if (loaded != null && context.mounted) {
                        setDialogState(() {
                          mine = date;
                          mineGrid = loaded;
                        });
                      }
                    },
                  ),
                  ListTile(
                    title: const Text('Colleague shift'),
                    subtitle: Text(
                      theirs == null
                          ? 'Choose a date'
                          : _dayLabel(
                              theirGrid,
                              colleague.staffMemberId,
                              theirs!,
                            ),
                    ),
                    onTap: () async {
                      final date = await _pickDate(
                        context,
                        theirs ?? mine,
                        firstSwapDay,
                      );
                      if (date == null) return;
                      final loaded = await _gridOn(date);
                      if (loaded != null && context.mounted) {
                        setDialogState(() {
                          theirs = date;
                          theirGrid = loaded;
                        });
                      }
                    },
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
                onPressed:
                    theirs == null ||
                        !isWorkingShift(
                          mineGrid.shiftCodeFor(me, mine) ?? '',
                          codes: codes,
                        ) ||
                        !isWorkingShift(
                          theirGrid.shiftCodeFor(
                                colleague.staffMemberId,
                                theirs!,
                              ) ??
                              '',
                          codes: codes,
                        )
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
    Swap? proposed;
    await _run(() async {
      final (row, myDate, theirDate) = choice;
      if (row.staffMemberId.isEmpty) {
        throw ArgumentError('Choose a colleague');
      }
      proposed = await widget.swapStore.proposeSwap(
        row.staffMemberId,
        myDate,
        theirDate,
      );
    });
    if (proposed != null) await _textColleague(proposed!, choice.$1);
  }

  Future<void> _textColleague(Swap swap, ScheduleRow colleague) async {
    final number = colleague.cellNumber;
    final composer = widget.messagesComposer;
    if (number == null || composer == null) return;
    try {
      await composer.open(
        [number],
        'Hi ${colleague.displayName}, can we Swap my ${DateFormat.MMMd().format(swap.requesterDate)} '
        '${swap.requesterCode} shift for your ${DateFormat.MMMd().format(swap.colleagueDate)} '
        '${swap.colleagueCode} shift? Please answer in the ER Schedule app.',
      );
    } catch (_) {
      if (mounted) {
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

  Future<MonthGrid?> _gridOn(DateTime date) async {
    try {
      return await widget.rules.monthGrid(date);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This month could not be loaded. Try again.'),
          ),
        );
      }
      return null;
    }
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
      () => widget.swapStore.answerSwap(
        swap.id,
        accept: accept,
        reason: reason.trim(),
      ),
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
        if (!snapshot.hasData) {
          return Center(
            child: snapshot.hasError
                ? Text(snapshot.error.toString())
                : const CircularProgressIndicator(),
          );
        }
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
                              _run(() => widget.swapStore.approveSwap(swap.id)),
                          child: const Text('Approve'),
                        )
                      : swap.status == SwapStatus.proposed &&
                            swap.requesterId == widget.staffMemberId &&
                            grid.rows.any(
                              (row) =>
                                  row.staffMemberId == swap.colleagueId &&
                                  row.cellNumber != null,
                            )
                      ? IconButton(
                          tooltip: 'Text colleague',
                          icon: const Icon(Icons.sms_outlined),
                          onPressed: () => _textColleague(
                            swap,
                            grid.rows.firstWhere(
                              (row) => row.staffMemberId == swap.colleagueId,
                            ),
                          ),
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

List<DateTime> _workingDays(
  MonthGrid grid,
  String id,
  List<LegendCode> codes,
  DateTime now,
) {
  final start = DateTime(grid.month.year, grid.month.month);
  final length = DateTime(grid.month.year, grid.month.month + 1, 0).day;
  return [
    for (var day = 1; day <= length; day++)
      if (isFutureSwapDay(DateTime(start.year, start.month, day), now: now) &&
          isWorkingShift(
            grid.shiftCodeFor(id, DateTime(start.year, start.month, day)) ?? '',
            codes: codes,
          ))
        DateTime(start.year, start.month, day),
  ];
}

String _dayLabel(MonthGrid grid, String id, DateTime date) =>
    '${DateFormat.MMMd().format(date)} — ${grid.shiftCodeFor(id, date)}';

Future<DateTime?> _pickDate(
  BuildContext context,
  DateTime initial,
  DateTime firstSwapDay,
) => showDatePicker(
  context: context,
  initialDate: initial,
  firstDate: firstSwapDay,
  lastDate: DateTime(2100),
);
