import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'app_dependencies.dart';
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
import 'schedule/supabase_open_shift_store.dart';

import 'staff/invite_composer.dart';
import 'staff/staff_gateway.dart';
import 'settings/appearance.dart';
import 'settings/settings_history.dart';

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
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );

  final client = Supabase.instance.client;
  final repairController = RepairController(SupabaseRepairGateway(client));
  runApp(
    ScheduleApp(
      dependencies: AppDependencies(
        authGateway: SupabaseAuthGateway(
          client,
          onSignedOut: () => repairController.synchronize(null),
        ),
        signInFailureLog: SupabaseSignInFailureLog(client),
        scheduleStore: SupabaseScheduleStore(client),
        swapStore: SupabaseSwapStore(client),
        openShiftStore: SupabaseOpenShiftStore(client),
        staffGateway: SupabaseStaffGateway(client),
        inviteComposer: SmsInviteComposer(Uri.base),
        messagesComposer: const SmsMessagesComposer(),
        noticeGateway: SupabaseNoticeGateway(
          client,
          const String.fromEnvironment('VAPID_PUBLIC_KEY'),
        ),
        bookPagePresenter: const BrowserBookPagePresenter(),
        printWordingGateway: SupabasePrintWordingGateway(client),
        calendarFeedGateway: SupabaseCalendarFeedGateway(client, supabaseUrl),
        undeliveredInvitationLog: SupabaseUndeliveredInvitationLog(client),
        settingsHistory: SupabaseSettingsHistory(client),
        repairController: repairController,
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
