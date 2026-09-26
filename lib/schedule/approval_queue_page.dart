import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

import '../staff/staff_gateway.dart';
import 'approval_queue_session.dart';
import 'swap_proposal.dart';

/// The Manager's pending decisions across the whole Schedule, including other months.
class ApprovalQueuePage extends StatefulWidget {
  const ApprovalQueuePage({
    super.key,
    required this.rules,
    required this.swapStore,
    required this.openShiftStore,
    required this.giveawayStore,
    this.staffGateway,
    this.onAccessRejected,
  });

  final ScheduleRules rules;
  final SwapStore swapStore;
  final OpenShiftStore openShiftStore;
  final GiveawayStore giveawayStore;
  final StaffGateway? staffGateway;
  final VoidCallback? onAccessRejected;

  @override
  State<ApprovalQueuePage> createState() => _ApprovalQueuePageState();
}

class _ApprovalQueuePageState extends State<ApprovalQueuePage> {
  late final ApprovalQueueSession _session;

  @override
  void initState() {
    super.initState();
    _session = ApprovalQueueSession(
      rules: widget.rules,
      swapStore: widget.swapStore,
      giveawayStore: widget.giveawayStore,
      openShiftStore: widget.openShiftStore,
      staffGateway: widget.staffGateway,
      onAccessRejected: widget.onAccessRejected,
    );
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  List<_Decision> _decisions(ApprovalQueueState state) {
    final pending = state.pending!;
    final shiftById = {for (final shift in state.openShifts) shift.id: shift};
    String name(String id, DateTime date) =>
        state.grids[DateTime(date.year, date.month)]?.displayNameOf(id) ?? id;
    final decisions = <_Decision>[
      for (final invite in pending.invites)
        _Decision(
          date: invite.acceptedAt,
          title: 'Invite — ${invite.staffMemberName}',
          detail:
              '${invite.staffMemberName} accepted as ${invite.personalEmail}. '
              'Confirm this is the right person before granting access.',
          approve: (_) => _session.decideInvite(invite.inviteId, confirm: true),
          decline: (_) =>
              _session.decideInvite(invite.inviteId, confirm: false),
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
          approve: (reason) => _session.decideRequestOff(
            request.id,
            RequestOffDecision.approved,
            reason,
          ),
          decline: (reason) => _session.decideRequestOff(
            request.id,
            RequestOffDecision.declined,
            reason,
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
          approve: (reason) =>
              _session.decideSwap(swap.id, approve: true, reason: reason),
          decline: (reason) =>
              _session.decideSwap(swap.id, approve: false, reason: reason),
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
          approve: (reason) => _session.decideGiveaway(
            giveaway.id,
            approve: true,
            reason: reason,
          ),
          decline: (reason) => _session.decideGiveaway(
            giveaway.id,
            approve: false,
            reason: reason,
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
            approve: (reason) =>
                _session.decidePickup(pickup.id, approve: true, reason: reason),
            decline: (reason) => _session.decidePickup(
              pickup.id,
              approve: false,
              reason: reason,
            ),
          )
        else
          _Decision(
            date: DateTime(9999),
            title: 'Open shift pickup — ${pickup.staffMemberId}',
            detail: 'The Open shift is no longer available.',
            approve: (reason) =>
                _session.decidePickup(pickup.id, approve: true, reason: reason),
            decline: (reason) => _session.decidePickup(
              pickup.id,
              approve: false,
              reason: reason,
            ),
          ),
    ];
    decisions.sort((a, b) => a.date.compareTo(b.date));
    return decisions;
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
    if (confirmed != true) return;
    final reason = explanation.trim();
    final outcome = await (approve
        ? item.approve(reason)
        : item.decline(reason));
    if (outcome is ApprovalDecisionFailed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That decision was not saved. Try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Approval queue'),
      actions: [
        IconButton(
          tooltip: 'Refresh approval queue',
          onPressed: _session.refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        final state = _session.state;
        if (state.pending == null) {
          return Center(
            child: state.loadError != null
                ? const Text('Approval queue could not be loaded.')
                : const CircularProgressIndicator(),
          );
        }
        final decisions = _decisions(state);
        if (decisions.isEmpty) {
          return const Center(child: Text('Nothing awaiting approval.'));
        }
        return ListView(
          children: [
            for (final item in decisions)
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
                            onPressed: state.busy
                                ? null
                                : () => _decide(item, false),
                            child: Text(item.declineLabel),
                          ),
                          FilledButton(
                            onPressed: state.busy
                                ? null
                                : () => _decide(item, true),
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

final class _Decision {
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
  final Future<ApprovalDecisionOutcome> Function(String? reason) approve;
  final Future<ApprovalDecisionOutcome> Function(String? reason) decline;
  final bool approvalReasonSupported;
  final bool declineReasonSupported;
  final String? confirmationDetail;
  final String approveLabel;
  final String declineLabel;
}
