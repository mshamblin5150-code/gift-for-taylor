import 'package:schedule_rules/schedule_rules.dart';

import 'auth/auth_gateway.dart';
import 'auth/sign_in_failure_log.dart';
import 'calendar/calendar_feed_page.dart';
import 'calendar/undelivered_invitation_log.dart';
import 'maintainer/repair_controller.dart';
import 'notifications/notice_gateway.dart';
import 'schedule/book_page_printing.dart';
import 'schedule/messages_composer.dart';
import 'schedule/print_wording_gateway.dart';
import 'settings/settings_history.dart';
import 'staff/invite_composer.dart';
import 'staff/staff_gateway.dart';

/// The adapters wired into one running Schedule app.
final class AppDependencies {
  AppDependencies({
    required this.authGateway,
    required this.signInFailureLog,
    required this.scheduleStore,
    required this.swapStore,
    required this.giveawayStore,
    required this.openShiftStore,
    required this.staffGateway,
    required this.inviteComposer,
    required this.messagesComposer,
    required this.noticeGateway,
    required this.bookPagePresenter,
    required this.printWordingGateway,
    required this.calendarFeedGateway,
    required this.undeliveredInvitationLog,
    required this.settingsHistory,
    required this.repairController,
  }) : rules = ScheduleRules(scheduleStore);

  final AuthGateway authGateway;
  final SignInFailureLog signInFailureLog;
  final ScheduleStore scheduleStore;
  final SwapStore swapStore;
  final GiveawayStore giveawayStore;
  final OpenShiftStore openShiftStore;
  final StaffGateway staffGateway;
  final InviteComposer inviteComposer;
  final MessagesComposer messagesComposer;
  final NoticeGateway noticeGateway;
  final BookPagePresenter bookPagePresenter;
  final PrintWordingGateway printWordingGateway;
  final CalendarFeedGateway calendarFeedGateway;
  final UndeliveredInvitationLog undeliveredInvitationLog;
  final SettingsHistory settingsHistory;
  final RepairController repairController;
  final ScheduleRules rules;
}
