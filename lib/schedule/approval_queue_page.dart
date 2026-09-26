import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

import '../staff/staff_gateway.dart';
import 'pending_approvals.dart';
import 'swap_proposal.dart';

/// The Manager's pending decisions across the whole Schedule, including other months.
class ApprovalQueuePage extends StatefulWidget {
  const ApprovalQueuePage({
    super.key,
    required this.rules,
    required this.swapStore,
    required this.openShiftStore,
    this.giveawayStore,
    this.staffGateway,
  });

  final ScheduleRules rules;
  final SwapStore swapStore;
  final OpenShiftStore openShiftStore;
  final GiveawayStore? giveawayStore;
  final StaffGateway? staffGateway;

  @override
  State<ApprovalQueuePage> createState() => _ApprovalQueuePageState();
}

class _ApprovalQueuePageState extends State<ApprovalQueuePage> {
  late Future<List<_Decision>> _decisions = _load();
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<List<_Decision>> _load() async {
    final (pending, shifts) = await (
      readPendingApprovals(
        widget.rules,
        widget.swapStore,
        widget.openShiftStore,
        widget.staffGateway,
        widget.giveawayStore,
      ),
      widget.openShiftStore.openShifts(),
    ).wait;
    final shiftById = {for (final shift in shifts) shift.id: shift};
    final dates = <DateTime>{
      for (final swap in pending.swaps)
        for (final shift in swap.requesterShifts)
          DateTime(shift.date.year, shift.date.month),
      for (final swap in pending.swaps)
        for (final shift in swap.colleagueShifts)
          DateTime(shift.date.year, shift.date.month),
      for (final pickup in pending.pickups)
        if (shiftById[pickup.openShiftId] case final shift?)
          DateTime(shift.date.year, shift.date.month),
      for (final giveaway in pending.giveaways)
        for (final shift in giveaway.shifts)
          DateTime(shift.date.year, shift.date.month),
    };
    final grids = <DateTime, MonthGrid>{};
    await Future.wait(
      dates.map((month) async {
        grids[month] = await widget.rules.monthGrid(month);
      }),
    );
    String name(String id, DateTime date) =>
        grids[DateTime(date.year, date.month)]?.displayNameOf(id) ?? id;
    final decisions = <_Decision>[
      for (final invite in pending.invites)
        _Decision(
          date: invite.acceptedAt,
          title: 'Invite — ${invite.staffMemberName}',
          detail:
              '${invite.staffMemberName} accepted as ${invite.personalEmail}. '
              'Confirm this is the right person before granting access.',
          approve: () =>
              widget.staffGateway!.confirmInviteAcceptance(invite.inviteId),
          decline: () =>
              widget.staffGateway!.rejectInviteAcceptance(invite.inviteId),
          approveLabel: 'Confirm',
          declineLabel: 'Reject',
          declineReasonSupported: false,
          confirmationDetail: invite.personalEmail,
        ),
      for (final request in pending.requests)
        _Decision(
          date: request.dates.isEmpty
              ? request.submittedAt
              : request.dates.reduce((a, b) => a.isBefore(b) ? a : b),
          title: 'Request off — ${request.staffMemberName}',
          detail:
              '${request.dates.map((d) => DateFormat.yMMMd().format(d)).join(', ')}'
              '${request.reason?.isNotEmpty == true ? '\nReason: ${request.reason}' : ''}',
          approvalReasonSupported: true,
          approve: () => widget.rules.store.decideRequestOff(
            request.id,
            RequestOffDecision.approved,
            _reason?.trim(),
          ),
          decline: () => widget.rules.store.decideRequestOff(
            request.id,
            RequestOffDecision.declined,
            _reason?.trim(),
          ),
        ),
      for (final swap in pending.swaps)
        _Decision(
          date: swap.firstDate,
          title:
              'Swap — ${name(swap.requesterId, swap.firstDate)} ↔ '
              '${name(swap.colleagueId, swap.firstDate)}',
          detail: swapSummaryFor(
            swap,
            perspective: SwapSummaryPerspective.neutral,
            requesterName: name(swap.requesterId, swap.firstDate),
            colleagueName: name(swap.colleagueId, swap.firstDate),
          ),
          approve: () => widget.swapStore.approveSwap(swap.id),
          decline: () =>
              widget.swapStore.declineSwap(swap.id, reason: _reason?.trim()),
        ),
      for (final giveaway in pending.giveaways)
        _Decision(
          date: giveaway.firstDate,
          title:
              'Giveaway — ${name(giveaway.giverId, giveaway.firstDate)} → '
              '${name(giveaway.colleagueId, giveaway.firstDate)}',
          detail:
              '${giveaway.shifts.map((shift) => '${DateFormat.yMMMd().format(shift.date)} ${shift.shiftCode}').join(', ')}'
              '${giveaway.createsShortfall ? '\nWarning: approval would create or deepen a Shortfall.' : ''}',
          approve: () => widget.giveawayStore!.approveGiveaway(giveaway.id),
          decline: () => widget.giveawayStore!.declineGiveaway(
            giveaway.id,
            reason: _reason?.trim(),
          ),
        ),
      for (final pickup in pending.pickups)
        if (shiftById[pickup.openShiftId] case final shift?)
          _Decision(
            date: shift.date,
            title:
                'Open shift pickup — ${name(pickup.staffMemberId, shift.date)}',
            detail:
                '${DateFormat.yMMMd().format(shift.date)} ${shift.shiftCode} • ${shift.jobRole.label}',
            approve: () => widget.openShiftStore.approvePickup(pickup.id),
            decline: () => widget.openShiftStore.declinePickup(
              pickup.id,
              reason: _reason?.trim(),
            ),
          )
        else
          _Decision(
            date: DateTime(9999),
            title: 'Open shift pickup — ${pickup.staffMemberId}',
            detail: 'The Open shift is no longer available.',
            approve: () => widget.openShiftStore.approvePickup(pickup.id),
            decline: () => widget.openShiftStore.declinePickup(
              pickup.id,
              reason: _reason?.trim(),
            ),
          ),
    ];
    decisions.sort((a, b) => a.date.compareTo(b.date));
    return decisions;
  }

  String? _reason;

  void _refresh() {
    if (mounted && !_busy) setState(() => _decisions = _load());
  }

  Future<void> _decide(_Decision item, bool approve) async {
    var explanation = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '${approve ? item.approveLabel : item.declineLabel} ${item.title}?',
        ),
        content:
            (approve && !item.approvalReasonSupported) ||
                (!approve && !item.declineReasonSupported)
            ? item.confirmationDetail == null
                  ? null
                  : Text('Accepted as ${item.confirmationDetail}')
            : TextField(
                onChanged: (value) => explanation = value,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    _reason = explanation;
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await (approve ? item.approve() : item.decline());
      if (mounted) setState(() => _decisions = _load());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Decision was not saved: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      _reason = null;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Approval queue'),
      actions: [
        IconButton(
          tooltip: 'Refresh approval queue',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<List<_Decision>>(
      future: _decisions,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('Approval queue could not be loaded.'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(child: Text('Nothing awaiting approval.'));
        }
        return ListView(
          children: [
            for (final item in snapshot.data!)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(item.detail),
                      Row(
                        children: [
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _decide(item, false),
                            child: Text(item.declineLabel),
                          ),
                          FilledButton(
                            onPressed: _busy ? null : () => _decide(item, true),
                            child: Text(item.approveLabel),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _Decision {
  const _Decision({
    required this.date,
    required this.title,
    required this.detail,
    required this.approve,
    required this.decline,
    this.approvalReasonSupported = false,
    this.declineReasonSupported = true,
    this.confirmationDetail,
    this.approveLabel = 'Approve',
    this.declineLabel = 'Decline',
  });
  final DateTime date;
  final String title;
  final String detail;
  final Future<void> Function() approve;
  final Future<void> Function() decline;
  final bool approvalReasonSupported;
  final bool declineReasonSupported;
  final String? confirmationDetail;
  final String approveLabel;
  final String declineLabel;
}
