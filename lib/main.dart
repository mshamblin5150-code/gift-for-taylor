import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'auth/auth_gateway.dart';
import 'calendar/calendar_feed_page.dart';
import 'schedule/book_page_printer.dart';
import 'schedule/messages_composer.dart';
import 'schedule/supabase_schedule_store.dart';
import 'staff/invite_composer.dart';
import 'staff/staff_gateway.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
    runApp(const _MissingConfigurationApp());
    return;
  }

  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );

  final client = Supabase.instance.client;
  runApp(
    ScheduleApp(
      authGateway: SupabaseAuthGateway(client),
      scheduleStore: SupabaseScheduleStore(client),
      staffGateway: SupabaseStaffGateway(client),
      inviteComposer: SmsInviteComposer(Uri.base),
      messagesComposer: const SmsMessagesComposer(),
      inviteToken: Uri.base.queryParameters['invite'],
      printBookPage: printBookPage,
      calendarFeedGateway: SupabaseCalendarFeedGateway(client, supabaseUrl),
    ),
  );
}

class _MissingConfigurationApp extends StatelessWidget {
  const _MissingConfigurationApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'ER Schedule needs SUPABASE_URL and '
              'SUPABASE_PUBLISHABLE_KEY build settings.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
