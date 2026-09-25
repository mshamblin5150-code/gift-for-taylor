import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'messages_composer.dart';
import 'swap_proposal.dart';
import 'swaps_session.dart';

class SwapsPage extends StatefulWidget {
  const SwapsPage({
    super.key,
    required this.rules,
    required this.swapStore,
    required this.month,
    required this.staffMemberId,
    required this.isManager,
    this.messagesComposer,
    this.onAccessRejected,
    this.now = DateTime.now,
  });

  final ScheduleRules rules;
  final SwapStore swapStore;
  final DateTime month;
  final String? staffMemberId;
  final bool isManager;
  final MessagesComposer? messagesComposer;
  final VoidCallback? onAccessRejected;
  final DateTime Function() now;

  @override
  State<SwapsPage> createState() => _SwapsPageState();
}

class _SwapsPageState extends State<SwapsPage> {
  late final SwapsSession _session;

  @override
  void initState() {
    super.initState();
    _session = SwapsSession(
      rules: widget.rules,
      swapStore: widget.swapStore,
      month: widget.month,
      onAccessRejected: widget.onAccessRejected,
    );
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
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
    final outcome = await _session.propose(
      choice.colleague.staffMemberId,
      choice.requesterDates,
      choice.colleagueDates,
    );
    if (!mounted) return;
    switch (outcome) {
      case SwapsProposed(:final swap):
        await textSwapColleague(
          context,
          swap: swap,
          colleague: choice.colleague,
          swapStore: widget.swapStore,
          messagesComposer: widget.messagesComposer,
        );
      case SwapsProposalRejected(:final reason):
        _message(swapProposalRefusalMessage(reason));
      case SwapsProposeFailed():
        _message("That Swap wasn't proposed. Try again.");
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
    final outcome = await _session.answer(
      swap.id,
      accept: accept,
      reason: reason.trim(),
    );
    if (outcome is SwapsWriteFailed && mounted) {
      _message("That Swap answer wasn't saved. Try again.");
    }
  }

  void _message(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _approve(Swap swap) async {
    final outcome = await _session.approve(swap.id);
    if (outcome is SwapsWriteFailed && mounted) {
      _message("That Swap wasn't approved. Try again.");
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Swaps'),
      actions: [
        IconButton(
          tooltip: 'Refresh Swaps',
          onPressed: _session.refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        final state = _session.state;
        final grid = state.grid;
        if (grid == null) {
          return Center(
            child: state.loadError != null
                ? const Text("Swaps couldn't be loaded. Try again.")
                : const CircularProgressIndicator(),
          );
        }
        final swaps = state.swaps;
        return ListView(
          children: [
            if (widget.staffMemberId != null &&
                grid.status == MonthStatus.released &&
                !state.busy)
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
                    '${_summary(grid, swap)}\n${swap.status.name}'
                    '${swap.status == SwapStatus.voided && swap.voidedDate != null ? ' — ${grid.displayNameOf(swap.voidedStaffMemberId!)} on ${DateFormat.MMMd().format(swap.voidedDate!)} changed' : ''}'
                    '${swap.reason == null ? '' : ' — ${swap.reason}'}',
                  ),
                  isThreeLine: true,
                  trailing: state.busy
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
                          onPressed: () => _approve(swap),
                          child: const Text('Approve'),
                        )
                      : swap.status == SwapStatus.proposed &&
                            swap.requesterId == widget.staffMemberId &&
                            grid.rows.any(
                              (row) => row.staffMemberId == swap.colleagueId,
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
                            swapStore: widget.swapStore,
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

  String _summary(MonthGrid grid, Swap swap) {
    if (widget.staffMemberId == swap.requesterId) return swapSummary(swap);
    if (widget.staffMemberId == swap.colleagueId) {
      return swapSummaryFor(
        swap,
        perspective: SwapSummaryPerspective.colleague,
      );
    }
    return swapSummaryFor(
      swap,
      perspective: SwapSummaryPerspective.neutral,
      requesterName: grid.displayNameOf(swap.requesterId),
      colleagueName: grid.displayNameOf(swap.colleagueId),
    );
  }
}
