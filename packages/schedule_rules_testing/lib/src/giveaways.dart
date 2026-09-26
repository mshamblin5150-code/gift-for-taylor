part of '../schedule_rules_testing.dart';

/// Stateful Giveaway recorder for client tests. SQL owns eligibility rules.
final class InMemoryGiveawayDatabase {
  InMemoryGiveawayDatabase({
    required Map<(String, DateTime), String> shifts,
    Map<String, String> cellNumbers = const {},
    List<GiveawayColleague> eligibleColleagues = const [],
    List<Giveaway> giveaways = const [],
  }) : _shifts = Map.of(shifts),
       _cellNumbers = Map.of(cellNumbers),
       _eligibleColleagues = List.of(eligibleColleagues),
       _giveaways = List.of(giveaways);

  final Map<(String, DateTime), String> _shifts;
  final Map<String, String> _cellNumbers;
  final List<GiveawayColleague> _eligibleColleagues;
  final List<Giveaway> _giveaways;

  GiveawayStore storeFor(String staffMemberId) =>
      _InMemoryGiveawayStore(this, staffMemberId);
}

final class _InMemoryGiveawayStore implements GiveawayStore {
  _InMemoryGiveawayStore(this.database, this.actor);
  final InMemoryGiveawayDatabase database;
  final String actor;

  @override
  Future<List<Giveaway>> giveaways() async => List.of(database._giveaways);

  @override
  Stream<void> updates() => const Stream<void>.empty();

  @override
  Future<List<GiveawayColleague>> eligibleColleagues(
    List<DateTime> dates,
  ) async => List.of(database._eligibleColleagues);

  @override
  Future<String?> colleagueCellNumberForGiveaway(String giveawayId) async {
    final item = database._giveaways
        .where((g) => g.id == giveawayId)
        .firstOrNull;
    return item == null ? null : database._cellNumbers[item.colleagueId];
  }

  @override
  Future<Giveaway> proposeGiveaway(
    String colleagueId,
    List<DateTime> dates,
  ) async {
    final giveaway = Giveaway(
      id: '${database._giveaways.length + 1}',
      giverId: actor,
      colleagueId: colleagueId,
      shifts: [
        for (final date in dates.map(_day))
          GiveawayShift(
            date: date,
            shiftCode: database._shifts[(actor, date)] ?? '',
            targetCode: database._shifts[(colleagueId, date)] ?? '',
          ),
      ],
      status: GiveawayStatus.proposed,
    );
    database._giveaways.add(giveaway);
    return giveaway;
  }

  @override
  Future<void> answerGiveaway(
    String giveawayId, {
    required bool accept,
    String? reason,
  }) async => _replace(
    giveawayId,
    accept ? GiveawayStatus.accepted : GiveawayStatus.declined,
    reason,
  );

  @override
  Future<void> withdrawGiveaway(String giveawayId) async =>
      _replace(giveawayId, GiveawayStatus.withdrawn, null);

  @override
  Future<void> declineGiveaway(String giveawayId, {String? reason}) async =>
      _replace(giveawayId, GiveawayStatus.declined, reason);

  @override
  Future<void> approveGiveaway(String giveawayId) async =>
      _replace(giveawayId, GiveawayStatus.approved, null);

  void _replace(String id, GiveawayStatus status, String? reason) {
    final index = database._giveaways.indexWhere((g) => g.id == id);
    final item = database._giveaways[index];
    database._giveaways[index] = Giveaway(
      id: item.id,
      giverId: item.giverId,
      colleagueId: item.colleagueId,
      shifts: item.shifts,
      status: status,
      reason: reason,
      voidedStaffMemberId: item.voidedStaffMemberId,
      voidedDate: item.voidedDate,
      createsShortfall: item.createsShortfall,
    );
  }
}
