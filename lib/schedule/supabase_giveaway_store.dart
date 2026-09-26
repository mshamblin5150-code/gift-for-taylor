import 'dart:async';

import 'package:schedule_rules/schedule_rules.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'access_rejected_write.dart';

final class SupabaseGiveawayStore implements GiveawayStore {
  const SupabaseGiveawayStore(this.client);
  final SupabaseClient client;

  @override
  Future<List<Giveaway>> giveaways() async {
    final rows = await client
        .from('giveaways')
        .select(
          'id, giver_id, colleague_id, status, reason, '
          'voided_staff_member_id, voided_work_date, '
          'giveaway_shifts(work_date, shift_code, target_code)',
        )
        .order('created_at', ascending: false);
    return Future.wait([for (final row in rows) _giveaway(row)]);
  }

  @override
  Stream<void> updates() {
    late final StreamController<void> controller;
    RealtimeChannel? channel;
    controller = StreamController<void>(
      onListen: () {
        channel = client
            .channel('giveaways-inbox-${DateTime.now().microsecondsSinceEpoch}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'giveaways',
              callback: (_) => controller.add(null),
            )
            .subscribe();
      },
      onCancel: () async {
        final subscribed = channel;
        if (subscribed != null) await client.removeChannel(subscribed);
      },
    );
    return controller.stream;
  }

  @override
  Future<List<GiveawayColleague>> eligibleColleagues(
    List<DateTime> dates,
  ) async {
    final rows = await client.rpc<List<dynamic>>(
      'eligible_giveaway_colleagues',
      params: {'p_dates': dates.map(_date).toList()},
    );
    return [
      for (final row in rows.cast<Map<String, dynamic>>())
        GiveawayColleague(
          staffMemberId: row['staff_member_id'] as String,
          displayName: row['display_name'] as String,
        ),
    ];
  }

  @override
  Future<String?> colleagueCellNumberForGiveaway(String giveawayId) =>
      client.rpc<String?>(
        'giveaway_colleague_cell_number',
        params: {'p_giveaway_id': giveawayId},
      );

  @override
  Future<Giveaway> proposeGiveaway(
    String colleagueId,
    List<DateTime> dates,
  ) async {
    final id = await mapGiveawayProposalRefusal(
      () => client.rpc<String>(
        'propose_giveaway',
        params: {
          'p_colleague_id': colleagueId,
          'p_dates': dates.map(_date).toList(),
        },
      ),
    );
    final row = await client
        .from('giveaways')
        .select(
          'id, giver_id, colleague_id, status, reason, '
          'voided_staff_member_id, voided_work_date, '
          'giveaway_shifts(work_date, shift_code, target_code)',
        )
        .eq('id', id)
        .single();
    return _giveaway(row);
  }

  @override
  Future<void> answerGiveaway(
    String giveawayId, {
    required bool accept,
    String? reason,
  }) => mapAccessRejected(
    () => client.rpc<void>(
      'answer_giveaway',
      params: {
        'p_giveaway_id': giveawayId,
        'p_accept': accept,
        'p_reason': reason,
      },
    ),
  );

  @override
  Future<void> withdrawGiveaway(String giveawayId) => mapAccessRejected(
    () => client.rpc<void>(
      'withdraw_giveaway',
      params: {'p_giveaway_id': giveawayId},
    ),
  );

  @override
  Future<void> approveGiveaway(String giveawayId) => mapAccessRejected(
    () => client.rpc<void>(
      'approve_giveaway',
      params: {'p_giveaway_id': giveawayId},
    ),
  );

  @override
  Future<void> declineGiveaway(String giveawayId, {String? reason}) =>
      mapAccessRejected(
        () => client.rpc<void>(
          'decline_giveaway',
          params: {'p_giveaway_id': giveawayId, 'p_reason': reason},
        ),
      );

  Future<Giveaway> _giveaway(Map<String, dynamic> row) async {
    final shifts = [
      for (final shift
          in (row['giveaway_shifts'] as List<dynamic>)
              .cast<Map<String, dynamic>>())
        GiveawayShift(
          date: DateTime.parse(shift['work_date'] as String),
          shiftCode: shift['shift_code'] as String,
          targetCode: shift['target_code'] as String,
        ),
    ]..sort((a, b) => a.date.compareTo(b.date));
    final id = row['id'] as String;
    return Giveaway(
      id: id,
      giverId: row['giver_id'] as String,
      colleagueId: row['colleague_id'] as String,
      shifts: shifts,
      status: GiveawayStatus.values.byName(row['status'] as String),
      reason: row['reason'] as String?,
      voidedStaffMemberId: row['voided_staff_member_id'] as String?,
      voidedDate: row['voided_work_date'] == null
          ? null
          : DateTime.parse(row['voided_work_date'] as String),
      createsShortfall: await client.rpc<bool>(
        'giveaway_creates_shortfall',
        params: {'p_giveaway_id': id},
      ),
    );
  }
}

String _date(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
