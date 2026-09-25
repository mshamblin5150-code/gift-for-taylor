import 'dart:async';

import 'package:schedule_rules/schedule_rules.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'access_rejected_write.dart';

final class SupabaseSwapStore implements SwapStore {
  const SupabaseSwapStore(this.client);

  final SupabaseClient client;

  @override
  Future<List<Swap>> swaps() async {
    final rows = await client
        .from('swaps')
        .select(
          'id, requester_id, colleague_id, status, reason, '
          'voided_staff_member_id, voided_work_date, '
          'swap_shifts(side, work_date, shift_code, target_code)',
        )
        .order('created_at', ascending: false);
    return [for (final row in rows) _swap(row)];
  }

  @override
  Stream<void> updates() {
    late final StreamController<void> controller;
    RealtimeChannel? channel;
    controller = StreamController<void>(
      onListen: () {
        channel = client
            .channel('swaps-inbox-${DateTime.now().microsecondsSinceEpoch}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'swaps',
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
  Future<String?> colleagueCellNumberForSwap(String swapId) =>
      client.rpc<String?>(
        'swap_colleague_cell_number',
        params: {'p_swap_id': swapId},
      );

  @override
  Future<Swap> proposeSwap(
    String colleagueId,
    List<DateTime> requesterDates,
    List<DateTime> colleagueDates,
  ) async {
    final id = await mapSwapProposalRefusal(
      () => client.rpc<String>(
        'propose_swap',
        params: {
          'p_colleague_id': colleagueId,
          'p_requester_dates': requesterDates.map(_date).toList(),
          'p_colleague_dates': colleagueDates.map(_date).toList(),
        },
      ),
    );
    final row = await client
        .from('swaps')
        .select(
          'id, requester_id, colleague_id, status, reason, '
          'voided_staff_member_id, voided_work_date, '
          'swap_shifts(side, work_date, shift_code, target_code)',
        )
        .eq('id', id)
        .single();
    return _swap(row);
  }

  @override
  Future<void> answerSwap(
    String swapId, {
    required bool accept,
    String? reason,
  }) => mapAccessRejected(
    () => client.rpc<void>(
      'answer_swap',
      params: {'p_swap_id': swapId, 'p_accept': accept, 'p_reason': reason},
    ),
  );

  @override
  Future<void> approveSwap(String swapId) => mapAccessRejected(
    () => client.rpc<void>('approve_swap', params: {'p_swap_id': swapId}),
  );

  @override
  Future<void> declineSwap(String swapId, {String? reason}) =>
      mapAccessRejected(
        () => client.rpc<void>(
          'decline_swap',
          params: {'p_swap_id': swapId, 'p_reason': reason},
        ),
      );

  Swap _swap(Map<String, dynamic> row) {
    final shifts = (row['swap_shifts'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    List<SwapShift> side(String side) => [
      for (final shift in shifts.where((shift) => shift['side'] == side))
        SwapShift(
          date: DateTime.parse(shift['work_date'] as String),
          shiftCode: shift['shift_code'] as String,
          targetCode: shift['target_code'] as String,
        ),
    ]..sort((a, b) => a.date.compareTo(b.date));
    return Swap(
      id: row['id'] as String,
      requesterId: row['requester_id'] as String,
      colleagueId: row['colleague_id'] as String,
      requesterShifts: side('requester'),
      colleagueShifts: side('colleague'),
      status: SwapStatus.values.byName(row['status'] as String),
      reason: row['reason'] as String?,
      voidedStaffMemberId: row['voided_staff_member_id'] as String?,
      voidedDate: row['voided_work_date'] == null
          ? null
          : DateTime.parse(row['voided_work_date'] as String),
    );
  }
}

String _date(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
