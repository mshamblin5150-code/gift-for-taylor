import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'app_dependencies.dart';
import 'database.dart';
import 'auth/auth_gateway.dart';
import 'auth/sign_in_failure_log.dart';
import 'calendar/calendar_feed_page.dart';
import 'calendar/undelivered_invitation_log.dart';
import 'maintainer/repair_controller.dart';
import 'maintainer/supabase_repair_gateway.dart';
import 'notifications/notice_gateway.dart';
import 'schedule/book_page_printing.dart';
import 'schedule/print_wording_gateway.dart';
import 'schedule/messages_composer.dart';
import 'schedule/supabase_schedule_store.dart';
import 'schedule/supabase_swap_store.dart';
import 'schedule/supabase_giveaway_store.dart';
import 'schedule/supabase_open_shift_store.dart';

import 'staff/invite_composer.dart';
import 'staff/staff_gateway.dart';
import 'settings/appearance.dart';
import 'settings/settings_history.dart';
import 'tickets/ticket_gateway.dart';
import 'tickets/ticket_activity.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadAppearance();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
    runApp(const _MissingConfigurationApp());
    return;
  }

  final navigatorKey = GlobalKey<NavigatorState>();
  final ticketActivity = TicketActivityLog();
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
    httpClient: TicketActivityHttpClient(http.Client(), ticketActivity),
  );

  final client = Supabase.instance.client;
  final database = Database(client);
  final repairController = RepairController(SupabaseRepairGateway(database));
  runApp(
    ScheduleApp(
      dependencies: AppDependencies(
        authGateway: SupabaseAuthGateway(
          database,
          onSignedOut: () {
            ticketActivity.clear();
            repairController.synchronize(null);
          },
        ),
        signInFailureLog: SupabaseSignInFailureLog(database),
        scheduleStore: SupabaseScheduleStore(database),
        swapStore: SupabaseSwapStore(database),
        giveawayStore: SupabaseGiveawayStore(database),
        openShiftStore: SupabaseOpenShiftStore(database),
        staffGateway: SupabaseStaffGateway(database),
        inviteComposer: SmsInviteComposer(Uri.base),
        messagesComposer: const SmsMessagesComposer(),
        noticeGateway: SupabaseNoticeGateway(
          database,
          const String.fromEnvironment('VAPID_PUBLIC_KEY'),
        ),
        bookPagePresenter: const BrowserBookPagePresenter(),
        printWordingGateway: SupabasePrintWordingGateway(database),
        calendarFeedGateway: SupabaseCalendarFeedGateway(database, supabaseUrl),
        undeliveredInvitationLog: SupabaseUndeliveredInvitationLog(database),
        settingsHistory: SupabaseSettingsHistory(database),
        repairController: repairController,
        ticketGateway: SupabaseTicketGateway(database),
        ticketActivity: ticketActivity,
      ),
      navigatorKey: navigatorKey,
      inviteToken: Uri.base.queryParameters['invite'],
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
