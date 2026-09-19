import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  Uri? _newLink;
  bool _busy = false;
  String? _error;

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
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Subscribe to your working shifts in your phone calendar. '
                  'The calendar refreshes when your Schedule changes.',
                ),
                const SizedBox(height: 16),
                if (_newLink != null) ...[
                  const Text(
                    'Keep this link private. It works without signing in.',
                  ),
                  const SizedBox(height: 8),
                  SelectableText(_newLink.toString()),
                  const SizedBox(height: 8),
                  FilledButton.icon(
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
                    'Resetting stops the old link. Copy the new link after resetting.',
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
