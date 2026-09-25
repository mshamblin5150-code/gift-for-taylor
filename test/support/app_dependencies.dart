import 'dart:async';

import 'package:er_schedule/app_dependencies.dart';
import 'package:er_schedule/auth/auth_gateway.dart';
import 'package:er_schedule/calendar/calendar_feed_page.dart';
import 'package:er_schedule/notifications/notice_gateway.dart';
import 'package:er_schedule/maintainer/repair_controller.dart';
import 'package:er_schedule/schedule/book_page_printing.dart';
import 'package:er_schedule/schedule/messages_composer.dart';
import 'package:er_schedule/schedule/print_wording_gateway.dart';
import 'package:er_schedule/settings/settings_history.dart';
import 'package:er_schedule/staff/invite_composer.dart';
import 'package:er_schedule/staff/staff_gateway.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:schedule_rules_testing/schedule_rules_testing.dart';

import 'in_memory_settings_history.dart';
import 'in_memory_staff_gateway.dart';
import 'repair.dart';

AppDependencies appDependencies({
  AuthGateway? authGateway,
  ScheduleStore? scheduleStore,
  SwapStore? swapStore,
  OpenShiftStore? openShiftStore,
  StaffGateway? staffGateway,
  InviteComposer? inviteComposer,
  MessagesComposer? messagesComposer,
  NoticeGateway? noticeGateway,
  BookPagePresenter? bookPagePresenter,
  PrintWordingGateway? printWordingGateway,
  CalendarFeedGateway? calendarFeedGateway,
  SettingsHistory? settingsHistory,
  RepairController? repairController,
}) {
  final database = InMemoryScheduleDatabase(sections: const []);
  return AppDependencies(
    authGateway: authGateway ?? FakeAuthGateway(),
    scheduleStore: scheduleStore ?? database.storeFor('viewer'),
    swapStore: swapStore ?? InMemorySwapDatabase(shifts: {}).storeFor('viewer'),
    openShiftStore: openShiftStore ?? database.openShiftStoreFor('viewer'),
    staffGateway: staffGateway ?? InMemoryStaffGateway(),
    inviteComposer: inviteComposer ?? const NoopInviteComposer(),
    messagesComposer: messagesComposer ?? const NoopMessagesComposer(),
    noticeGateway: noticeGateway ?? const NoopNoticeGateway(),
    bookPagePresenter: bookPagePresenter ?? const NoopBookPagePresenter(),
    printWordingGateway: printWordingGateway ?? const NoopPrintWordingGateway(),
    calendarFeedGateway: calendarFeedGateway ?? const NoopCalendarFeedGateway(),
    settingsHistory: settingsHistory ?? InMemorySettingsHistory(),
    repairController: repairController ?? noopRepairController(),
  );
}

final class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway([this._signedIn = false, this.requestCodeError]);

  final _controller = StreamController<bool>.broadcast();
  bool _signedIn;
  final Object? requestCodeError;
  String? requestedEmail;
  String? verifiedEmail;
  String? verifiedCode;
  int signOutCount = 0;

  @override
  bool get isSignedIn => _signedIn;

  @override
  String? get currentUserId => _signedIn ? 'test-account' : null;

  @override
  Stream<bool> get signedInChanges => _controller.stream;

  @override
  Future<void> requestCode(String email) async {
    requestedEmail = email;
    if (requestCodeError case final error?) throw error;
  }

  @override
  Future<void> verifyCode({required String email, required String code}) async {
    verifiedEmail = email;
    verifiedCode = code;
    _signedIn = true;
    _controller.add(true);
  }

  @override
  Future<void> signOut() async {
    signOutCount += 1;
    _signedIn = false;
    _controller.add(false);
  }
}

final class NoopInviteComposer implements InviteComposer {
  const NoopInviteComposer();
  @override
  Future<void> open(StaffInvite invite) async {}
}

final class NoopMessagesComposer implements MessagesComposer {
  const NoopMessagesComposer();
  @override
  Future<void> open(List<String> cellNumbers, String body) async {}
}

final class NoopNoticeGateway implements NoticeGateway {
  const NoopNoticeGateway([this.state = PushState.unsupported]);

  final PushState state;

  @override
  Future<PushState> pushState() async => state;
  @override
  Future<void> allowPush() async {}
  @override
  Future<void> disablePush() async {}
  @override
  Future<List<StaffNotice>> notices() async => [];
  @override
  Future<void> markRead(String id) async {}
  @override
  Future<RuleBatchDetails> ruleBatchDetails(String id) async =>
      const RuleBatchDetails(plan: [], shifts: []);
}

final class NoopBookPagePresenter implements BookPagePresenter {
  const NoopBookPagePresenter();
  @override
  void present(PreparedBookPage page) {}
}

final class NoopPrintWordingGateway implements PrintWordingGateway {
  const NoopPrintWordingGateway();
  @override
  Future<PrintWording> read() async => const PrintWording();
  @override
  Future<void> save(PrintWording wording) async {}
  @override
  Future<PrintWording> readForMonth(DateTime month) => read();
  @override
  Future<void> correctMonth(DateTime month, PrintWording wording) async {}
}

final class NoopCalendarFeedGateway implements CalendarFeedGateway {
  const NoopCalendarFeedGateway();
  @override
  Future<String> channel() async => 'invitations';
  @override
  Future<List<CalendarSubscription>> subscriptions() async => [];
  @override
  Future<List<DisconnectedCalendarSubscription>>
  disconnectedSubscriptions() async => [];
  @override
  Future<Uri> createSubscription(String name) async =>
      Uri.parse('https://example.test/feed');
  @override
  Future<void> revokeSubscription(String id) async {}
  @override
  Future<void> useInvitations() async {}
}
