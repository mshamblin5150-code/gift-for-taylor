import 'package:schedule_rules/schedule_rules.dart';

import '../staff/staff_gateway.dart';

class PendingApprovals {
  const PendingApprovals({
    required this.requests,
    required this.swaps,
    required this.pickups,
    this.giveaways = const [],
    this.invites = const [],
  });

  final List<RequestOff> requests;
  final List<Swap> swaps;
  final List<OpenShiftPickup> pickups;
  final List<Giveaway> giveaways;
  final List<PendingInviteAcceptance> invites;

  int get count =>
      requests.length +
      swaps.length +
      pickups.length +
      giveaways.length +
      invites.length;
}

Future<PendingApprovals> readPendingApprovals(
  ScheduleRules rules,
  SwapStore swapStore,
  OpenShiftStore openShiftStore, [
  StaffGateway? staffGateway,
  GiveawayStore? giveawayStore,
]) async {
  final (requests, swaps, pickups, invites, giveaways) = await (
    rules.store.requestsOff(pendingOnly: true),
    swapStore.swaps(),
    openShiftStore.pickups(),
    staffGateway?.pendingInviteAcceptances() ??
        Future.value(const <PendingInviteAcceptance>[]),
    giveawayStore?.giveaways() ?? Future.value(const <Giveaway>[]),
  ).wait;
  return PendingApprovals(
    requests: requests,
    swaps: swaps.where((s) => s.status == SwapStatus.accepted).toList(),
    pickups: pickups.where((p) => p.status == PickupStatus.pending).toList(),
    giveaways: giveaways
        .where((giveaway) => giveaway.status == GiveawayStatus.accepted)
        .toList(),
    invites: invites,
  );
}
