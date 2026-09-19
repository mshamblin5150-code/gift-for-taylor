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
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;
}

enum PushState { unsupported, denied, available, enabled }

abstract interface class NoticeGateway {
  Future<PushState> pushState();
  Future<void> allowPush();
  Future<void> disablePush();
  Future<void> sendTestPush();
  Future<List<StaffNotice>> notices();
  Future<void> markRead(String id);
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
  Future<void> sendTestPush() async {
    await _client.rpc('send_test_push');
  }

  @override
  Future<List<StaffNotice>> notices() async {
    final rows = await _client
        .from('staff_notices')
        .select('id, title, body, created_at, read_at')
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
          ),
        )
        .toList();
  }

  @override
  Future<void> markRead(String id) async {
    await _client.rpc('mark_staff_notice_read', params: {'p_notice_id': id});
  }
}
