import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'calendar_link_stub.dart'
    if (dart.library.html) 'calendar_link_web.dart'
    as calendar_link;
import 'calendar_platform.dart';

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
  late final CalendarPlatform _detectedPlatform = detectCalendarPlatform();
  late CalendarPlatform _platform = _detectedPlatform;
  Uri? _newLink;
  String? _newName;
  bool _busy = false;
  bool _chooseDevice = false;
  String? _error;

  String get _deviceName => switch (_platform) {
    CalendarPlatform.android => 'Android',
    CalendarPlatform.ios => 'iPhone or iPad',
    CalendarPlatform.macos => 'Mac',
    CalendarPlatform.windows => 'Windows',
    CalendarPlatform.other => 'another device',
  };

  String get _setupInstructions => switch (_platform) {
    CalendarPlatform.android =>
      'Google Calendar cannot add a Calendar feed in its phone app. '
          'On a computer, sign in to this app, open My Calendar feed and create '
          'a Calendar subscription named Google. In Google Calendar on that '
          'computer, choose Other calendars → + → From URL, paste the HTTPS URL, '
          'and add it. Then open calendar.google.com/calendar/u/0/syncselect and '
          'make sure your new calendar is selected for mobile sync. It may be off by default.',
    CalendarPlatform.ios =>
      'Tap Subscribe in Calendar below. Confirm that Calendar adds a '
          'subscription, not an imported copy. To check for changes later, '
          'open Calendar, tap Calendars, and swipe down on the list. '
          'iPhone has no refresh setting for just this subscription; its '
          'automatic fetch depends on the phone’s global schedule and may '
          'wait until it is charging on Wi-Fi.',
    CalendarPlatform.macos =>
      'Open the link in Calendar, or choose File → New Calendar Subscription '
          'and paste the webcal URL. In Calendar, control-click the subscribed '
          'calendar, choose Get Info, and set Auto-refresh (as often as every '
          '5 minutes). Press ⌘R to refresh now.',
    CalendarPlatform.windows =>
      'In classic Outlook, use Subscribe in Calendar below to add an '
          'Internet Calendar, not a downloaded copy. In new Outlook, choose '
          'Calendar → Add calendar → Subscribe from web and paste the HTTPS URL. '
          'New Outlook does not handle webcal links.',
    CalendarPlatform.other =>
      'Use Subscribe in Calendar to open your calendar app’s subscription '
          'flow. If your app asks for a URL, copy the HTTPS URL and paste it '
          'into its subscribe-by-URL screen. Do not import a downloaded ICS file.',
  };

  Future<void> _copyHttpsUrl() async {
    await Clipboard.setData(
      ClipboardData(text: _newLink!.replace(scheme: 'https').toString()),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Calendar feed URL copied')));
  }

  Future<void> _subscribe() async {
    try {
      await calendar_link.openCalendarLink(_newLink!);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open Calendar. Copy the URL instead.'),
        ),
      );
    }
  }

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
                'A Calendar feed mirrors your working shifts, but calendar apps '
                'check it on their own schedule. Open the app for the latest '
                'Schedule and Change announcements. Give each Calendar subscription '
                'its own link so you can see when it last checked in and revoke it separately.',
              ),
              const SizedBox(height: 16),
              Text('Setting up $_deviceName'),
              TextButton(
                onPressed: () => setState(() => _chooseDevice = !_chooseDevice),
                child: const Text("I'm setting up a different device"),
              ),
              if (_chooseDevice)
                DropdownButton<CalendarPlatform>(
                  value: _platform,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                      value: CalendarPlatform.android,
                      child: Text('Android'),
                    ),
                    DropdownMenuItem(
                      value: CalendarPlatform.ios,
                      child: Text('iPhone or iPad'),
                    ),
                    DropdownMenuItem(
                      value: CalendarPlatform.macos,
                      child: Text('Mac'),
                    ),
                    DropdownMenuItem(
                      value: CalendarPlatform.windows,
                      child: Text('Windows'),
                    ),
                    DropdownMenuItem(
                      value: CalendarPlatform.other,
                      child: Text('Another device'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _platform = value);
                  },
                ),
              const SizedBox(height: 12),
              Text(_setupInstructions),
              const SizedBox(height: 20),
              if (_newLink != null &&
                  (_platform != CalendarPlatform.android ||
                      _detectedPlatform != CalendarPlatform.android)) ...[
                Text('Link for $_newName'),
                const Text(
                  'Keep this link private. It works without signing in.',
                ),
                const SizedBox(height: 8),
                if (_platform != CalendarPlatform.android) ...[
                  FilledButton.icon(
                    onPressed: _subscribe,
                    icon: const Icon(Icons.calendar_month),
                    label: const Text('Subscribe in Calendar'),
                  ),
                  SelectableText(_newLink.toString()),
                  const SizedBox(height: 16),
                ],
                const Text(
                  'For a subscribe-by-URL screen, paste this HTTPS URL:',
                ),
                SelectableText(_newLink!.replace(scheme: 'https').toString()),
                OutlinedButton.icon(
                  onPressed: _copyHttpsUrl,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy HTTPS URL'),
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
              if (_platform != CalendarPlatform.android ||
                  _detectedPlatform != CalendarPlatform.android)
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
