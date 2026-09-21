import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'push_browser.dart' as browser;

final class StaffNotice {
  const StaffNotice({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
    this.ruleBatchId,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;
  final String? ruleBatchId;
}

final class RuleBatchDetails {
  const RuleBatchDetails({required this.plan, required this.shifts});
  final List<Map<String, dynamic>> plan;
  final List<Map<String, dynamic>> shifts;
}

enum PushState { unsupported, denied, available, enabled }

abstract interface class NoticeGateway {
  Future<PushState> pushState();
  Future<void> allowPush();
  Future<void> disablePush();
  Future<List<StaffNotice>> notices();
  Future<void> markRead(String id);
  Future<RuleBatchDetails> ruleBatchDetails(String id);
}

final class SupabaseNoticeGateway implements NoticeGateway {
  SupabaseNoticeGateway(this._client, this._vapidPublicKey);

  final SupabaseClient _client;
  final String _vapidPublicKey;

  @override
  Future<PushState> pushState() async => switch (await browser.pushState()) {
    'denied' => PushState.denied,
    'available' => PushState.available,
    'enabled' => PushState.enabled,
    _ => PushState.unsupported,
  };

  @override
  Future<void> allowPush() async {
    if (_vapidPublicKey.isEmpty) {
      throw StateError('Push has not been configured.');
    }
    final subscription = await browser.subscribe(_vapidPublicKey);
    try {
      await _client.rpc(
        'register_push_subscription',
        params: {'p_subscription': jsonDecode(subscription)},
      );
    } catch (_) {
      await browser.unsubscribe();
      rethrow;
    }
  }

  @override
  Future<void> disablePush() async {
    final endpoint = await browser.unsubscribe();
    if (endpoint.isNotEmpty) {
      await _client.rpc(
        'remove_push_subscription',
        params: {'p_endpoint': endpoint},
      );
    }
  }

  @override
  Future<List<StaffNotice>> notices() async {
    final rows = await _client
        .from('staff_notices')
        .select('id, title, body, created_at, read_at, rule_batch_id')
        .order('created_at', ascending: false)
        .limit(50);
    return rows
        .map(
          (row) => StaffNotice(
            id: row['id'] as String,
            title: row['title'] as String,
            body: row['body'] as String,
            createdAt: DateTime.parse(row['created_at'] as String),
            isRead: row['read_at'] != null,
            ruleBatchId: row['rule_batch_id'] as String?,
          ),
        )
        .toList();
  }

  @override
  Future<void> markRead(String id) async {
    await _client.rpc('mark_staff_notice_read', params: {'p_notice_id': id});
  }

  @override
  Future<RuleBatchDetails> ruleBatchDetails(String id) async {
    final batch = await _client
        .from('coverage_rule_batches')
        .select('plan')
        .eq('id', id)
        .single();
    final shifts = await _client
        .from('short_shifts')
        .select('work_date, shift_code, job_role, filled_at, requires_approval')
        .eq('rule_batch_id', id)
        .order('work_date');
    return RuleBatchDetails(
      plan: (batch['plan'] as List<dynamic>).cast<Map<String, dynamic>>(),
      shifts: shifts.cast<Map<String, dynamic>>(),
    );
  }
}
