import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'giveaways_session.dart';

class GiveawaysPage extends StatefulWidget {
  const GiveawaysPage({
    super.key,
    required this.rules,
    required this.giveawayStore,
    required this.month,
    required this.staffMemberId,
    this.onAccessRejected,
  });

  final ScheduleRules rules;
  final GiveawayStore giveawayStore;
  final DateTime month;
  final String? staffMemberId;
  final VoidCallback? onAccessRejected;

  @override
  State<GiveawaysPage> createState() => _GiveawaysPageState();
}

class _GiveawaysPageState extends State<GiveawaysPage> {
  late final GiveawaysSession _session;

  @override
  void initState() {
    super.initState();
    _session = GiveawaysSession(
      rules: widget.rules,
      giveawayStore: widget.giveawayStore,
      month: widget.month,
      onAccessRejected: widget.onAccessRejected,
    );
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  Future<void> _answer(Giveaway item, bool accept) => _write(
    _session.answer(item.id, accept: accept),
    "That Giveaway answer wasn't saved. Try again.",
  );

  Future<void> _withdraw(Giveaway item) => _write(
    _session.withdraw(item.id),
    "That Giveaway wasn't withdrawn. Try again.",
  );

  Future<void> _write(
    Future<GiveawaysWriteOutcome> command,
    String failureMessage,
  ) async {
    final outcome = await command;
    if (outcome is GiveawaysWriteFailed && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Giveaways'),
      actions: [
        IconButton(
          tooltip: 'Refresh Giveaways',
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
                ? const Text("Giveaways couldn't be loaded. Try again.")
                : const CircularProgressIndicator(),
          );
        }
        return ListView(
          children: [
            if (state.giveaways.isEmpty)
              const ListTile(title: Text('No Giveaways yet.')),
            for (final item in state.giveaways)
              Card(
                child: ListTile(
                  title: Text(
                    '${grid.displayNameOf(item.giverId)} → '
                    '${grid.displayNameOf(item.colleagueId)}',
                  ),
                  subtitle: Text(
                    '${item.shifts.map((shift) => '${DateFormat.MMMd().format(shift.date)} ${shift.shiftCode}').join(', ')}'
                    '\n${item.status.name}'
                    '${item.status == GiveawayStatus.voided && item.voidedDate != null ? ' — ${DateFormat.MMMd().format(item.voidedDate!)} changed' : ''}',
                  ),
                  isThreeLine: true,
                  trailing: state.busy ? null : _action(item),
                ),
              ),
          ],
        );
      },
    ),
  );

  Widget? _action(Giveaway item) {
    if (item.giverId == widget.staffMemberId &&
        (item.status == GiveawayStatus.proposed ||
            item.status == GiveawayStatus.accepted)) {
      return IconButton(
        tooltip: 'Withdraw Giveaway',
        onPressed: () => _withdraw(item),
        icon: const Icon(Icons.undo),
      );
    }
    if (item.colleagueId == widget.staffMemberId &&
        item.status == GiveawayStatus.proposed) {
      return PopupMenuButton<bool>(
        tooltip: 'Answer Giveaway',
        onSelected: (accept) => _answer(item, accept),
        itemBuilder: (_) => const [
          PopupMenuItem(value: true, child: Text('Accept')),
          PopupMenuItem(value: false, child: Text('Decline')),
        ],
      );
    }
    return null;
  }
}
