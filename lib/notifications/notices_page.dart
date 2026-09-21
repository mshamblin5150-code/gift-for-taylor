import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'notice_gateway.dart';

class NoticesPage extends StatefulWidget {
  const NoticesPage({super.key, required this.gateway});

  final NoticeGateway gateway;

  @override
  State<NoticesPage> createState() => _NoticesPageState();
}

class _NoticesPageState extends State<NoticesPage> {
  late Future<List<StaffNotice>> _notices = widget.gateway.notices();
  PushState? _pushState;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _refreshPushState();
  }

  Future<void> _refreshPushState() async {
    try {
      final state = await widget.gateway.pushState();
      if (mounted) setState(() => _pushState = state);
    } catch (_) {
      if (mounted) setState(() => _pushState = PushState.unsupported);
    }
  }

  Future<void> _act(Future<void> Function() action, String success) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _message = success;
        _notices = widget.gateway.notices();
      });
      await _refreshPushState();
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openBatch(StaffNotice notice) async {
    try {
      if (!notice.isRead) await widget.gateway.markRead(notice.id);
      final details = await widget.gateway.ruleBatchDetails(
        notice.ruleBatchId!,
      );
      if (!mounted) return;
      setState(() => _notices = widget.gateway.notices());
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Open shift batch'),
          content: SizedBox(
            width: 420,
            height: 420,
            child: ListView(
              children: [
                for (final row in details.plan)
                  ListTile(
                    title: Text(
                      '${row['work_date']} · ${row['pool']} '
                      '· ${row['window']}',
                    ),
                    subtitle: Text(
                      'Posted ${(row['post_floor'] as int) + (row['post_ordinary'] as int)}, withdrew '
                      '${(row['withdraw_floor'] as int) + (row['withdraw_ordinary'] as int)}',
                    ),
                  ),
                if (details.shifts.isNotEmpty) const Divider(),
                for (final shift in details.shifts)
                  ListTile(
                    title: Text(
                      '${shift['shift_code']} · '
                      '${shift['work_date']}',
                    ),
                    subtitle: Text(
                      '${shift['job_role']} · '
                      '${shift['filled_at'] == null ? 'Open' : 'Filled'} · '
                      '${shift['requires_approval'] == true ? 'Approval required' : 'Immediate pickup'}',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notices')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Allow notifications to hear about Schedule changes, Requests off, Swaps, and Open shifts.',
                ),
                if (_pushState == PushState.unsupported)
                  const Text(
                    'Install this app to your Home Screen on iPhone (iOS 16.4 or later), then open it there to allow notifications.',
                  ),
                if (_pushState == PushState.denied)
                  const Text(
                    'Notifications are blocked in this device’s settings.',
                  ),
                if (_pushState == PushState.available)
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _act(
                            widget.gateway.allowPush,
                            'Notifications allowed.',
                          ),
                    child: const Text('Allow notifications'),
                  ),
                if (_pushState == PushState.enabled) ...[
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _act(
                            widget.gateway.disablePush,
                            'Notifications turned off on this device.',
                          ),
                    child: const Text('Turn off on this device'),
                  ),
                ],
                if (_message != null) Text(_message!),
              ],
            ),
          ),
          const Divider(),
          FutureBuilder<List<StaffNotice>>(
            future: _notices,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const ListTile(
                  title: Text('Notices could not be loaded.'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data!.isEmpty) {
                return const ListTile(title: Text('No notices yet.'));
              }
              return Column(
                children: [
                  for (final notice in snapshot.data!)
                    ListTile(
                      title: Text(
                        notice.title,
                        style: TextStyle(
                          fontWeight: notice.isRead ? null : FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        '${notice.body}\n${DateFormat.yMMMd().add_jm().format(notice.createdAt.toLocal())}',
                      ),
                      isThreeLine: true,
                      onTap: notice.ruleBatchId != null
                          ? () => _openBatch(notice)
                          : notice.isRead
                          ? null
                          : () => _act(
                              () => widget.gateway.markRead(notice.id),
                              'Marked read.',
                            ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
