import 'dart:async';

import 'package:schedule_rules/schedule_rules.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class SupabaseSwapStore implements SwapStore {
  const SupabaseSwapStore(this.client);

  final SupabaseClient client;

  @override
  Future<List<Swap>> swaps() async {
    final rows = await client
        .from('swaps')
        .select(
          'id, requester_id, colleague_id, requester_date, colleague_date, '
          'requester_code, colleague_code, requester_target_code, '
          'colleague_target_code, status, reason',
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
  Future<Swap> proposeSwap(
    String colleagueId,
    DateTime requesterDate,
    DateTime colleagueDate,
  ) async {
    final row = await client.rpc<Map<String, dynamic>>(
      'propose_swap',
      params: {
        'p_colleague_id': colleagueId,
        'p_requester_date': _date(requesterDate),
        'p_colleague_date': _date(colleagueDate),
      },
    );
    return _swap(row);
  }

  @override
  Future<void> answerSwap(
    String swapId, {
    required bool accept,
    String? reason,
  }) => client.rpc<void>(
    'answer_swap',
    params: {'p_swap_id': swapId, 'p_accept': accept, 'p_reason': reason},
  );

  @override
  Future<void> approveSwap(String swapId) =>
      client.rpc<void>('approve_swap', params: {'p_swap_id': swapId});

  Swap _swap(Map<String, dynamic> row) => Swap(
    id: row['id'] as String,
    requesterId: row['requester_id'] as String,
    colleagueId: row['colleague_id'] as String,
    requesterDate: DateTime.parse(row['requester_date'] as String),
    colleagueDate: DateTime.parse(row['colleague_date'] as String),
    requesterCode: row['requester_code'] as String,
    colleagueCode: row['colleague_code'] as String,
    requesterTargetCode: row['requester_target_code'] as String,
    colleagueTargetCode: row['colleague_target_code'] as String,
    status: SwapStatus.values.byName(row['status'] as String),
    reason: row['reason'] as String?,
  );
}

String _date(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
