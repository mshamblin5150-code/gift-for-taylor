import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'giveaway_proposal.dart';
import 'messages_composer.dart';

class GiveawaysPage extends StatefulWidget {
  const GiveawaysPage({
    super.key,
    required this.rules,
    required this.giveawayStore,
    required this.month,
    required this.staffMemberId,
    required this.isManager,
    this.messagesComposer,
    this.initialDate,
    this.now,
  });
  final ScheduleRules rules;
  final GiveawayStore giveawayStore;
  final DateTime month;
  final String? staffMemberId;
  final bool isManager;
  final MessagesComposer? messagesComposer;
  final DateTime? initialDate;
  final DateTime Function()? now;

  @override
  State<GiveawaysPage> createState() => _GiveawaysPageState();
}

class _GiveawaysPageState extends State<GiveawaysPage> {
  MonthGrid? _grid;
  List<Giveaway> _giveaways = const [];
  bool _loading = true;
  StreamSubscription<void>? _updates;

  @override
  void initState() {
    super.initState();
    _updates = widget.giveawayStore.updates().listen((_) => _load());
    _load().then((_) {
      if (widget.initialDate != null && mounted) _propose(widget.initialDate);
    });
  }

  @override
  void dispose() {
    _updates?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final values = await (
        widget.rules.monthGrid(widget.month),
        widget.giveawayStore.giveaways(),
      ).wait;
      if (mounted) {
        setState(() {
          _grid = values.$1;
          _giveaways = values.$2;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _propose([DateTime? initialDate]) async {
    final grid = _grid;
    final giverId = widget.staffMemberId;
    if (grid == null || giverId == null) return;
    final choice = await showGiveawayProposalDialog(
      context,
      rules: widget.rules,
      giveawayStore: widget.giveawayStore,
      initialGrid: grid,
      giverId: giverId,
      now: widget.now ?? DateTime.now,
      initialDate: initialDate,
    );
    if (choice == null || !mounted) return;
    try {
      final giveaway = await widget.giveawayStore.proposeGiveaway(
        choice.colleague.staffMemberId,
        choice.dates,
      );
      if (!mounted) return;
      await textGiveawayColleague(
        context,
        giveaway: giveaway,
        colleague: choice.colleague,
        giveawayStore: widget.giveawayStore,
        messagesComposer: widget.messagesComposer,
      );
      await _load();
    } on GiveawayProposalRefused catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(giveawayProposalRefusalMessage(error.reason))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("That Giveaway wasn't proposed. Try again."),
          ),
        );
      }
    }
  }

  Future<void> _answer(Giveaway item, bool accept) async {
    await widget.giveawayStore.answerGiveaway(item.id, accept: accept);
    await _load();
  }

  Future<void> _withdraw(Giveaway item) async {
    await widget.giveawayStore.withdrawGiveaway(item.id);
    await _load();
  }

  Future<void> _approve(Giveaway item) async {
    await widget.giveawayStore.approveGiveaway(item.id);
    await _load();
  }

  Future<void> _decline(Giveaway item) async {
    await widget.giveawayStore.declineGiveaway(item.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final grid = _grid;
    return Scaffold(
      appBar: AppBar(title: const Text('Giveaways')),
      floatingActionButton: !widget.isManager && grid != null
          ? FloatingActionButton.extended(
              onPressed: _propose,
              icon: const Icon(Icons.card_giftcard),
              label: const Text('Give shifts away'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : grid == null
          ? const Center(child: Text("Giveaways couldn't be loaded."))
          : ListView(
              children: [
                if (_giveaways.isEmpty)
                  const ListTile(title: Text('No Giveaways yet.')),
                for (final item in _giveaways)
                  Card(
                    child: ListTile(
                      title: Text(
                        '${grid.displayNameOf(item.giverId)} → '
                        '${grid.displayNameOf(item.colleagueId)}',
                      ),
                      subtitle: Text(
                        '${item.shifts.map((shift) => '${DateFormat.MMMd().format(shift.date)} ${shift.shiftCode}').join(', ')}'
                        '\n${item.status.name}'
                        '${item.status == GiveawayStatus.voided && item.voidedDate != null ? ' — ${DateFormat.MMMd().format(item.voidedDate!)} changed' : ''}'
                        '${item.createsShortfall ? '\nWarning: approval would create or deepen a Shortfall.' : ''}',
                      ),
                      isThreeLine: item.createsShortfall,
                      trailing: _action(item),
                    ),
                  ),
              ],
            ),
    );
  }

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
    if (widget.isManager && item.status == GiveawayStatus.accepted) {
      return PopupMenuButton<bool>(
        tooltip: 'Approve Giveaway',
        onSelected: (approve) => approve ? _approve(item) : _decline(item),
        itemBuilder: (_) => const [
          PopupMenuItem(value: true, child: Text('Approve')),
          PopupMenuItem(value: false, child: Text('Decline')),
        ],
      );
    }
    return null;
  }
}
