import 'package:flutter/material.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'auth/auth_gateway.dart';
import 'auth/sign_in_page.dart';
import 'calendar/calendar_feed_page.dart';
import 'schedule/messages_composer.dart';
import 'schedule/month_grid_page.dart';
import 'staff/staff_gateway.dart';
import 'staff/staff_list_page.dart';

class ScheduleApp extends StatelessWidget {
  const ScheduleApp({
    super.key,
    required this.authGateway,
    required this.scheduleStore,
    this.staffGateway,
    this.inviteComposer,
    this.messagesComposer,
    this.inviteToken,
    this.printBookPage,
    this.calendarFeedGateway,
  });

  final AuthGateway authGateway;
  final ScheduleStore scheduleStore;
  final StaffGateway? staffGateway;
  final InviteComposer? inviteComposer;
  final MessagesComposer? messagesComposer;
  final String? inviteToken;
  final ValueChanged<String>? printBookPage;
  final CalendarFeedGateway? calendarFeedGateway;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ER Schedule',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff24535c)),
        useMaterial3: true,
      ),
      home: _AuthGate(
        authGateway: authGateway,
        scheduleStore: scheduleStore,
        staffGateway: staffGateway,
        inviteComposer: inviteComposer,
        messagesComposer: messagesComposer,
        inviteToken: inviteToken,
        printBookPage: printBookPage,
        calendarFeedGateway: calendarFeedGateway,
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate({
    required this.authGateway,
    required this.scheduleStore,
    required this.staffGateway,
    required this.inviteComposer,
    required this.messagesComposer,
    required this.inviteToken,
    required this.printBookPage,
    required this.calendarFeedGateway,
  });

  final AuthGateway authGateway;
  final ScheduleStore scheduleStore;
  final StaffGateway? staffGateway;
  final InviteComposer? inviteComposer;
  final MessagesComposer? messagesComposer;
  final String? inviteToken;
  final ValueChanged<String>? printBookPage;
  final CalendarFeedGateway? calendarFeedGateway;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  late final Future<void> _prepareInviteSignIn = _prepareInvite();

  Future<void> _prepareInvite() async {
    if (widget.inviteToken != null && widget.authGateway.isSignedIn) {
      await widget.authGateway.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _prepareInviteSignIn,
      builder: (context, preparation) {
        if (preparation.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (preparation.hasError) {
          return const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Sign out of the current account, then open this Invite again.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return StreamBuilder<bool>(
          stream: widget.authGateway.signedInChanges,
          initialData: widget.authGateway.isSignedIn,
          builder: (context, snapshot) {
            if (snapshot.data != true) {
              return SignInPage(authGateway: widget.authGateway);
            }
            if (widget.inviteToken != null && widget.staffGateway != null) {
              return _InviteAcceptance(
                authGateway: widget.authGateway,
                scheduleStore: widget.scheduleStore,
                staffGateway: widget.staffGateway!,
                inviteComposer: widget.inviteComposer,
                messagesComposer: widget.messagesComposer,
                inviteToken: widget.inviteToken!,
                printBookPage: widget.printBookPage,
                calendarFeedGateway: widget.calendarFeedGateway,
              );
            }
            return _ScheduleAccess(
              authGateway: widget.authGateway,
              scheduleStore: widget.scheduleStore,
              staffGateway: widget.staffGateway,
              inviteComposer: widget.inviteComposer,
              messagesComposer: widget.messagesComposer,
              printBookPage: widget.printBookPage,
              calendarFeedGateway: widget.calendarFeedGateway,
            );
          },
        );
      },
    );
  }
}

class _InviteAcceptance extends StatefulWidget {
  const _InviteAcceptance({
    required this.authGateway,
    required this.scheduleStore,
    required this.staffGateway,
    required this.inviteComposer,
    required this.messagesComposer,
    required this.inviteToken,
    required this.printBookPage,
    required this.calendarFeedGateway,
  });

  final AuthGateway authGateway;
  final ScheduleStore scheduleStore;
  final StaffGateway staffGateway;
  final InviteComposer? inviteComposer;
  final MessagesComposer? messagesComposer;
  final String inviteToken;
  final ValueChanged<String>? printBookPage;
  final CalendarFeedGateway? calendarFeedGateway;

  @override
  State<_InviteAcceptance> createState() => _InviteAcceptanceState();
}

class _InviteAcceptanceState extends State<_InviteAcceptance> {
  late final Future<void> _acceptance = widget.staffGateway.acceptInvite(
    widget.inviteToken,
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _acceptance,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(
              actions: [
                IconButton(
                  tooltip: 'Sign out',
                  onPressed: widget.authGateway.signOut,
                  icon: const Icon(Icons.logout),
                ),
              ],
            ),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This Invite is invalid, expired, or has already been used. '
                  'Ask your Manager to resend it.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return _ScheduleAccess(
          authGateway: widget.authGateway,
          scheduleStore: widget.scheduleStore,
          staffGateway: widget.staffGateway,
          inviteComposer: widget.inviteComposer,
          messagesComposer: widget.messagesComposer,
          printBookPage: widget.printBookPage,
          calendarFeedGateway: widget.calendarFeedGateway,
        );
      },
    );
  }
}

class _ScheduleAccess extends StatefulWidget {
  const _ScheduleAccess({
    required this.authGateway,
    required this.scheduleStore,
    required this.staffGateway,
    required this.inviteComposer,
    required this.messagesComposer,
    required this.printBookPage,
    required this.calendarFeedGateway,
  });

  final AuthGateway authGateway;
  final ScheduleStore scheduleStore;
  final StaffGateway? staffGateway;
  final InviteComposer? inviteComposer;
  final MessagesComposer? messagesComposer;
  final ValueChanged<String>? printBookPage;
  final CalendarFeedGateway? calendarFeedGateway;

  @override
  State<_ScheduleAccess> createState() => _ScheduleAccessState();
}

class _ScheduleAccessState extends State<_ScheduleAccess> {
  late final Future<_ScheduleData> _data = _loadData();

  Future<_ScheduleData> _loadData() async {
    final sections = await widget.scheduleStore.sections();
    final canManageStaff = await widget.staffGateway?.canManageStaff() ?? false;
    final staffMemberId = await widget.staffGateway?.currentStaffMemberId();
    final editable = await widget.scheduleStore.editableSections();
    final monthToCheck = await ScheduleRules(widget.scheduleStore)
        .monthAwaitingConfirmation();
    return _ScheduleData(
      sections,
      canManageStaff,
      monthToCheck,
      !canManageStaff && editable.isEmpty ? staffMemberId : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ScheduleData>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data;
        final sections = data?.sections ?? const <ScheduleSection>[];
        if (snapshot.hasError || sections.isEmpty) {
          return Scaffold(
            appBar: AppBar(
              actions: [
                IconButton(
                  tooltip: 'Sign out',
                  onPressed: widget.authGateway.signOut,
                  icon: const Icon(Icons.logout),
                ),
              ],
            ),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "This email isn't on the ER staff list. "
                  'Ask your manager to add you.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        // A month loaded from the printed page opens first until it is checked.
        final now = DateTime.now();
        return MonthGridPage(
          rules: ScheduleRules(widget.scheduleStore),
          month: data?.monthToCheck ?? DateTime(now.year, now.month),
          staffMemberId: data?.staffMemberId,
          onSignOut: widget.authGateway.signOut,
          messagesComposer: widget.messagesComposer,
          printBookPage: widget.printBookPage,
          onCalendarFeed: widget.calendarFeedGateway == null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) =>
                        CalendarFeedPage(gateway: widget.calendarFeedGateway!),
                  ),
                ),
          onManageStaff:
              data?.canManageStaff == true &&
                  widget.staffGateway != null &&
                  widget.inviteComposer != null
              ? () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => StaffListPage(
                      gateway: widget.staffGateway!,
                      rules: ScheduleRules(widget.scheduleStore),
                      inviteComposer: widget.inviteComposer!,
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }
}

final class _ScheduleData {
  const _ScheduleData(
    this.sections,
    this.canManageStaff,
    this.monthToCheck,
    this.staffMemberId,
  );

  final List<ScheduleSection> sections;
  final bool canManageStaff;
  final DateTime? monthToCheck;
  final String? staffMemberId;
}
