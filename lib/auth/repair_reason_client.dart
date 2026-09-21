import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Prompts for a reason on each Maintainer Unit write. The database enforces it.
final class RepairReasonClient extends http.BaseClient {
  RepairReasonClient(this.navigatorKey, {http.Client? inner})
    : _inner = inner ?? http.Client();

  final GlobalKey<NavigatorState> navigatorKey;
  final http.Client _inner;
  bool isMaintainer = false;

  static const _withoutUnitWrite = {
    'current_access_role',
    'current_staff_member_id',
    'can_manage_staff',
    'can_manage_sections',
    'can_edit_schedule',
    'editable_section_ids',
    'visible_open_shifts',
    'open_shift_approval_default',
    'section_staffing_for_month',
    'schedule_rows',
    'staff_member_details',
    'my_invite_acceptance_pending',
    'my_calendar_channel',
    'list_calendar_subscriptions',
    'list_disconnected_calendar_subscriptions',
    'create_calendar_subscription',
    'revoke_calendar_subscription',
    'use_calendar_invitations',
    'register_push_subscription',
    'remove_push_subscription',
    'mark_staff_notice_read',
    'acknowledge_request_off_notices',
    'confirm_request_off_email',
  };

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final segments = request.url.pathSegments;
    if (isMaintainer &&
        request.method == 'POST' &&
        segments.length >= 4 &&
        segments[segments.length - 2] == 'rpc' &&
        !_withoutUnitWrite.contains(segments.last)) {
      final reason = await _askReason();
      if (reason == null) throw StateError('Repair cancelled');
      request.headers['x-repair-reason'] = reason;
    }
    return _inner.send(request);
  }

  Future<String?> _askReason() async {
    final context = navigatorKey.currentContext;
    if (context == null) throw StateError('Repair reason entry unavailable');
    var enteredReason = '';
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Maintainer repair reason'),
        content: TextField(
          onChanged: (value) => enteredReason = value,
          autofocus: true,
          maxLength: 240,
          decoration: const InputDecoration(
            labelText: 'Reason for this Unit change',
            hintText: 'Describe the repair',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final reason = enteredReason.trim();
              if (reason.length >= 3) Navigator.pop(context, reason);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  @override
  void close() => _inner.close();
}
