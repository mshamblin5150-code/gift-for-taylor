import 'package:schedule_rules/schedule_rules.dart';

import '../staff/staff_gateway.dart';

class PendingApprovals {
  const PendingApprovals({
    required this.requests,
    required this.swaps,
    required this.pickups,
    this.invites = const [],
  });

  final List<RequestOff> requests;
  final List<Swap> swaps;
  final List<OpenShiftPickup> pickups;
  final List<PendingInviteAcceptance> invites;

  int get count =>
      requests.length + swaps.length + pickups.length + invites.length;
}

Future<PendingApprovals> readPendingApprovals(
  ScheduleRules rules,
  SwapRules swapRules,
  OpenShiftRules openShiftRules, [
  StaffGateway? staffGateway,
]) async {
  final (requests, swaps, pickups, invites) = await (
    rules.approvalQueue(),
    swapRules.swaps(),
    openShiftRules.pickups(),
    staffGateway?.pendingInviteAcceptances() ??
        Future.value(const <PendingInviteAcceptance>[]),
  ).wait;
  return PendingApprovals(
    requests: requests,
    swaps: swaps.where((s) => s.status == SwapStatus.accepted).toList(),
    pickups: pickups.where((p) => p.status == PickupStatus.pending).toList(),
    invites: invites,
  );
}
