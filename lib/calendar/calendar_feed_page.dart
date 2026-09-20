import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'calendar_link_stub.dart'
    if (dart.library.html) 'calendar_link_web.dart'
    as calendar_link;
import 'calendar_platform.dart';

abstract interface class CalendarFeedGateway {
  Future<bool> hasFeed();
  Future<Uri> resetFeed();
}

final class SupabaseCalendarFeedGateway implements CalendarFeedGateway {
  SupabaseCalendarFeedGateway(this._client, this._supabaseUrl);

  final SupabaseClient _client;
  final String _supabaseUrl;

  @override
  Future<bool> hasFeed() async =>
      await _client.rpc('has_calendar_feed') as bool? ?? false;

  @override
  Future<Uri> resetFeed() async {
    final token = await _client.rpc<String>('reset_calendar_feed');
    return Uri.parse(
      '${_supabaseUrl.replaceFirst(RegExp(r"/$"), "")}/functions/v1/calendar-feed/$token',
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
  late Future<bool> _hasFeed = widget.gateway.hasFeed();
  late final CalendarPlatform _detectedPlatform = detectCalendarPlatform();
  late CalendarPlatform _platform = _detectedPlatform;
  Uri? _newLink;
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
          'your link there. In Google Calendar on that computer, choose Other '
          'calendars → + → From URL, paste the HTTPS URL, and add it. '
          'Then open calendar.google.com/calendar/u/0/syncselect and make sure '
          'your new calendar is selected for mobile sync. It may be off by default.',
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

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _newLink.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Calendar feed URL copied')));
  }

  Future<void> _subscribe() async {
    try {
      await calendar_link.openCalendarLink(_newLink!.replace(scheme: 'webcal'));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open Calendar. Copy the URL instead.'),
        ),
      );
    }
  }

  Future<void> _reset() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final link = await widget.gateway.resetFeed();
      if (!mounted) return;
      setState(() {
        _newLink = link;
        _hasFeed = Future.value(true);
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = 'Could not create the Calendar feed link. Try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Calendar feed')),
      body: FutureBuilder<bool>(
        future: _hasFeed,
        builder: (context, snapshot) {
          if (!snapshot.hasData && !snapshot.hasError) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'A Calendar feed mirrors your working shifts, but calendar '
                'apps check it on their own schedule. Open the app for the '
                'latest Schedule and Change announcements.',
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
              if (_platform != CalendarPlatform.android ||
                  _detectedPlatform != CalendarPlatform.android) ...[
                if (_newLink != null) ...[
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
                    SelectableText(
                      _newLink!.replace(scheme: 'webcal').toString(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const Text(
                    'For a subscribe-by-URL screen, paste this HTTPS URL:',
                  ),
                  SelectableText(_newLink.toString()),
                  OutlinedButton.icon(
                    onPressed: _copyLink,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy HTTPS URL'),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (snapshot.hasError)
                  const Text('Could not load feed status.'),
                OutlinedButton(
                  onPressed: _busy ? null : _reset,
                  child: Text(
                    snapshot.data == true ? 'Reset link' : 'Create link',
                  ),
                ),
                if (snapshot.data == true)
                  const Text(
                    'Resetting stops the old link. Other calendars using it will stop updating.',
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
