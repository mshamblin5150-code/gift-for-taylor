import 'package:schedule_rules/schedule_rules.dart';

import '../staff/staff_gateway.dart';

class PendingApprovals {
  PendingApprovals({
    required List<RequestOff> requests,
    required List<Swap> swaps,
    required List<OpenShiftPickup> pickups,
    List<Giveaway> giveaways = const [],
    List<PendingInviteAcceptance> invites = const [],
  }) : requests = List.unmodifiable(requests),
       swaps = List.unmodifiable(swaps),
       pickups = List.unmodifiable(pickups),
       giveaways = List.unmodifiable(giveaways),
       invites = List.unmodifiable(invites);

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
  OpenShiftStore openShiftStore,
  GiveawayStore giveawayStore,
  StaffGateway staffGateway,
) async {
  final (requests, swaps, pickups, invites, giveaways) = await (
    rules.store.requestsOff(pendingOnly: true),
    swapStore.swaps(),
    openShiftStore.pickups(),
    staffGateway.pendingInviteAcceptances(),
    giveawayStore.giveaways(),
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
