import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class CalendarSubscription {
  const CalendarSubscription({
    required this.id,
    required this.name,
    required this.createdAt,
    this.lastFetchedAt,
    this.fetchingUserAgent,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime? lastFetchedAt;
  final String? fetchingUserAgent;

  factory CalendarSubscription.fromJson(Map<String, dynamic> json) =>
      CalendarSubscription(
        id: json['id'] as String,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        lastFetchedAt: json['last_fetched_at'] == null
            ? null
            : DateTime.parse(json['last_fetched_at'] as String),
        fetchingUserAgent: json['fetching_user_agent'] as String?,
      );
}

abstract interface class CalendarFeedGateway {
  Future<List<CalendarSubscription>> subscriptions();
  Future<Uri> createSubscription(String name);
  Future<void> revokeSubscription(String id);
}

final class SupabaseCalendarFeedGateway implements CalendarFeedGateway {
  SupabaseCalendarFeedGateway(this._client, this._supabaseUrl);

  final SupabaseClient _client;
  final String _supabaseUrl;

  @override
  Future<List<CalendarSubscription>> subscriptions() async {
    final rows = await _client.rpc<List<dynamic>>(
      'list_calendar_subscriptions',
    );
    return rows
        .map(
          (row) => CalendarSubscription.fromJson(row as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<Uri> createSubscription(String name) async {
    final result = await _client.rpc<Map<String, dynamic>>(
      'create_calendar_subscription',
      params: {'p_name': name},
    );
    final token = result['token'] as String;
    return Uri.parse(
      '${_supabaseUrl.replaceFirst(RegExp(r"/$"), "")}/functions/v1/calendar-feed/$token',
    ).replace(scheme: 'webcal');
  }

  @override
  Future<void> revokeSubscription(String id) async {
    await _client.rpc<void>(
      'revoke_calendar_subscription',
      params: {'p_id': id},
    );
  }
}

class CalendarFeedPage extends StatefulWidget {
  const CalendarFeedPage({super.key, required this.gateway});

  final CalendarFeedGateway gateway;

  @override
  State<CalendarFeedPage> createState() => _CalendarFeedPageState();
}

class _CalendarFeedPageState extends State<CalendarFeedPage> {
  late Future<List<CalendarSubscription>> _subscriptions = widget.gateway
      .subscriptions();
  Uri? _newLink;
  String? _newName;
  bool _busy = false;
  String? _error;

  void _reload() {
    setState(() => _subscriptions = widget.gateway.subscriptions());
  }

  Future<void> _create() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Calendar subscription'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'iPhone or Google',
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final link = await widget.gateway.createSubscription(name);
      if (!mounted) return;
      setState(() {
        _newLink = link;
        _newName = name;
      });
      _reload();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not create the subscription. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(CalendarSubscription subscription) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Revoke ${subscription.name}?'),
        content: const Text(
          'This subscription will stop updating. Your other Calendar subscriptions will keep working.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.gateway.revokeSubscription(subscription.id);
      if (!mounted) return;
      _reload();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not revoke the subscription. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Calendar feed')),
      body: FutureBuilder<List<CalendarSubscription>>(
        future: _subscriptions,
        builder: (context, snapshot) {
          if (!snapshot.hasData && !snapshot.hasError) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Give each place you subscribe to your Calendar feed its own link. '
                'Name it so you can see when it last checked in and revoke it separately.',
              ),
              const SizedBox(height: 16),
              if (_newLink != null) ...[
                Text('Link for $_newName'),
                const Text(
                  'Keep this link private. It works without signing in.',
                ),
                const SizedBox(height: 8),
                SelectableText(_newLink.toString()),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: _newLink.toString()),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Calendar feed link copied'),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy link'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (snapshot.hasError) ...[
                const Text('Could not load Calendar subscriptions.'),
                TextButton(onPressed: _reload, child: const Text('Retry')),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _create,
                  icon: const Icon(Icons.add),
                  label: const Text('Add subscription'),
                ),
              ),
              const SizedBox(height: 16),
              if (snapshot.hasData && snapshot.data!.isEmpty)
                const Text('No Calendar subscriptions yet.'),
              if (snapshot.hasData)
                for (final subscription in snapshot.data!)
                  Card(
                    child: ListTile(
                      title: Text(subscription.name),
                      subtitle: Text(
                        subscription.lastFetchedAt == null
                            ? 'Never checked in'
                            : 'Last checked in ${DateFormat.yMMMd().add_jm().format(subscription.lastFetchedAt!.toLocal())}'
                                  '${subscription.fetchingUserAgent == null ? '' : '\n${subscription.fetchingUserAgent}'}',
                      ),
                      isThreeLine: subscription.fetchingUserAgent != null,
                      trailing: TextButton(
                        onPressed: _busy ? null : () => _revoke(subscription),
                        child: const Text('Revoke'),
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
