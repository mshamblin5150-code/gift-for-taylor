import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'messages_composer.dart';
import 'swap_proposal.dart';

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
    final choice = await showSwapProposalDialog(
      context,
      rules: widget.rules,
      initialGrid: grid,
      requesterId: me,
      now: widget.now,
    );
    if (choice == null) return;
    Swap? proposed;
    await _run(() async {
      proposed = await widget.swapStore.proposeSwap(
        choice.colleague.staffMemberId,
        choice.requesterDate,
        choice.colleagueDate,
      );
    });
    if (proposed != null && mounted) {
      await textSwapColleague(
        context,
        swap: proposed!,
        colleague: choice.colleague,
        messagesComposer: widget.messagesComposer,
      );
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
                          onPressed: () => textSwapColleague(
                            context,
                            swap: swap,
                            colleague: grid.rows.firstWhere(
                              (row) => row.staffMemberId == swap.colleagueId,
                            ),
                            messagesComposer: widget.messagesComposer,
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
