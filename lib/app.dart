import 'package:flutter/material.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'auth/auth_gateway.dart';
import 'auth/sign_in_page.dart';
import 'calendar/calendar_feed_page.dart';
import 'notifications/notice_gateway.dart';
import 'schedule/messages_composer.dart';
import 'schedule/month_grid_page.dart';
import 'schedule/print_wording_gateway.dart';
import 'staff/staff_gateway.dart';
import 'staff/staff_list_page.dart';
import 'staff/staff_details_page.dart';
import 'schedule_theme.dart';

class ScheduleApp extends StatelessWidget {
  const ScheduleApp({
    super.key,
    required this.authGateway,
    required this.scheduleStore,
    this.staffGateway,
    this.inviteComposer,
    this.messagesComposer,
    this.swapRules,
    this.openShiftRules,
    this.noticeGateway,
    this.inviteToken,
    this.printBookPage,
    this.printWordingGateway,
    this.calendarFeedGateway,
  });

  final AuthGateway authGateway;
  final ScheduleStore scheduleStore;
  final StaffGateway? staffGateway;
  final InviteComposer? inviteComposer;
  final MessagesComposer? messagesComposer;
  final SwapRules? swapRules;
  final OpenShiftRules? openShiftRules;
  final NoticeGateway? noticeGateway;
  final String? inviteToken;
  final ValueChanged<String>? printBookPage;
  final PrintWordingGateway? printWordingGateway;
  final CalendarFeedGateway? calendarFeedGateway;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ER Schedule',
      theme: ScheduleTheme.light,
      darkTheme: ScheduleTheme.dark,
      themeMode: ThemeMode.system,
      home: _AuthGate(
        authGateway: authGateway,
        scheduleStore: scheduleStore,
        staffGateway: staffGateway,
        inviteComposer: inviteComposer,
        messagesComposer: messagesComposer,
        swapRules: swapRules,
        openShiftRules: openShiftRules,
        noticeGateway: noticeGateway,
        inviteToken: inviteToken,
        printBookPage: printBookPage,
        printWordingGateway: printWordingGateway,
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
    required this.swapRules,
    required this.openShiftRules,
    required this.noticeGateway,
    required this.inviteToken,
    required this.printBookPage,
    required this.printWordingGateway,
    required this.calendarFeedGateway,
  });

  final AuthGateway authGateway;
  final ScheduleStore scheduleStore;
  final StaffGateway? staffGateway;
  final InviteComposer? inviteComposer;
  final MessagesComposer? messagesComposer;
  final SwapRules? swapRules;
  final OpenShiftRules? openShiftRules;
  final NoticeGateway? noticeGateway;
  final String? inviteToken;
  final ValueChanged<String>? printBookPage;
  final PrintWordingGateway? printWordingGateway;
  final CalendarFeedGateway? calendarFeedGateway;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  late final Future<void> _prepareInviteSignIn = _prepareInvite();
  String? _inviteCellNumber;

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
              if (widget.inviteToken != null && _inviteCellNumber == null) {
                return _InviteCellEntry(
                  onContinue: (number) =>
                      setState(() => _inviteCellNumber = number),
                );
              }
              return SignInPage(authGateway: widget.authGateway);
            }
            if (widget.inviteToken != null && widget.staffGateway != null) {
              return _InviteAcceptance(
                authGateway: widget.authGateway,
                scheduleStore: widget.scheduleStore,
                staffGateway: widget.staffGateway!,
                inviteComposer: widget.inviteComposer,
                messagesComposer: widget.messagesComposer,
                swapRules: widget.swapRules,
                openShiftRules: widget.openShiftRules,
                noticeGateway: widget.noticeGateway,
                inviteToken: widget.inviteToken!,
                cellNumber: _inviteCellNumber!,
                printBookPage: widget.printBookPage,
                printWordingGateway: widget.printWordingGateway,
                calendarFeedGateway: widget.calendarFeedGateway,
              );
            }
            return _ScheduleAccess(
              authGateway: widget.authGateway,
              scheduleStore: widget.scheduleStore,
              staffGateway: widget.staffGateway,
              inviteComposer: widget.inviteComposer,
              messagesComposer: widget.messagesComposer,
              swapRules: widget.swapRules,
              openShiftRules: widget.openShiftRules,
              noticeGateway: widget.noticeGateway,
              printBookPage: widget.printBookPage,
              printWordingGateway: widget.printWordingGateway,
              calendarFeedGateway: widget.calendarFeedGateway,
            );
          },
        );
      },
    );
  }
}

class _InviteCellEntry extends StatefulWidget {
  const _InviteCellEntry({required this.onContinue});

  final ValueChanged<String> onContinue;

  @override
  State<_InviteCellEntry> createState() => _InviteCellEntryState();
}

class _InviteCellEntryState extends State<_InviteCellEntry> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Accept your Invite',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Enter the Cell number your Manager has on the Staff list.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Cell number'),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    if (_controller.text.trim().isNotEmpty) {
                      widget.onContinue(_controller.text.trim());
                    }
                  },
                  child: const Text('Continue to email'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _InviteAcceptance extends StatefulWidget {
  const _InviteAcceptance({
    required this.authGateway,
    required this.scheduleStore,
    required this.staffGateway,
    required this.inviteComposer,
    required this.messagesComposer,
    required this.swapRules,
    required this.openShiftRules,
    required this.noticeGateway,
    required this.inviteToken,
    required this.cellNumber,
    required this.printBookPage,
    required this.printWordingGateway,
    required this.calendarFeedGateway,
  });

  final AuthGateway authGateway;
  final ScheduleStore scheduleStore;
  final StaffGateway staffGateway;
  final InviteComposer? inviteComposer;
  final MessagesComposer? messagesComposer;
  final SwapRules? swapRules;
  final OpenShiftRules? openShiftRules;
  final NoticeGateway? noticeGateway;
  final String inviteToken;
  final String cellNumber;
  final ValueChanged<String>? printBookPage;
  final PrintWordingGateway? printWordingGateway;
  final CalendarFeedGateway? calendarFeedGateway;

  @override
  State<_InviteAcceptance> createState() => _InviteAcceptanceState();
}

class _InviteAcceptanceState extends State<_InviteAcceptance> {
  late Future<InviteAcceptanceResult> _acceptance = widget.staffGateway
      .acceptInvite(widget.inviteToken, widget.cellNumber);
  final _retryNumber = TextEditingController();

  @override
  void dispose() {
    _retryNumber.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<InviteAcceptanceResult>(
      future: _acceptance,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          final message = snapshot.error is StaffInviteAlreadyLinkedException
              ? 'This email is already signed in as another Staff member.'
              : 'This Invite is invalid, expired, or has already been used. '
                    'Ask your Manager to resend it.';
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
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(message, textAlign: TextAlign.center),
              ),
            ),
          );
        }
        if (snapshot.data != InviteAcceptanceResult.accepted) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        snapshot.data == InviteAcceptanceResult.throttled
                            ? 'Too many incorrect Cell numbers. Wait 10 minutes, then try again.'
                            : "That number doesn't match the one on file — check with your Manager.",
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _retryNumber,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Cell number',
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          if (_retryNumber.text.trim().isNotEmpty) {
                            setState(() {
                              _acceptance = widget.staffGateway.acceptInvite(
                                widget.inviteToken,
                                _retryNumber.text.trim(),
                              );
                            });
                          }
                        },
                        child: const Text('Try Cell number again'),
                      ),
                    ],
                  ),
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
          swapRules: widget.swapRules,
          openShiftRules: widget.openShiftRules,
          noticeGateway: widget.noticeGateway,
          printBookPage: widget.printBookPage,
          printWordingGateway: widget.printWordingGateway,
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
    required this.swapRules,
    required this.openShiftRules,
    required this.noticeGateway,
    required this.printBookPage,
    required this.printWordingGateway,
    required this.calendarFeedGateway,
  });

  final AuthGateway authGateway;
  final ScheduleStore scheduleStore;
  final StaffGateway? staffGateway;
  final InviteComposer? inviteComposer;
  final MessagesComposer? messagesComposer;
  final SwapRules? swapRules;
  final OpenShiftRules? openShiftRules;
  final NoticeGateway? noticeGateway;
  final ValueChanged<String>? printBookPage;
  final PrintWordingGateway? printWordingGateway;
  final CalendarFeedGateway? calendarFeedGateway;

  @override
  State<_ScheduleAccess> createState() => _ScheduleAccessState();
}

class _ScheduleAccessState extends State<_ScheduleAccess> {
  late Future<_ScheduleData> _data = _loadData();

  Future<void> _signOut() async {
    try {
      await widget.noticeGateway?.disablePush();
    } finally {
      await widget.authGateway.signOut();
    }
  }

  Future<_ScheduleData> _loadData() async {
    final sections = await widget.scheduleStore.sections();
    final invitePending = sections.isEmpty && widget.staffGateway != null
        ? await widget.staffGateway!.isInviteAcceptancePending()
        : false;
    final canManageStaff = await widget.staffGateway?.canManageStaff() ?? false;
    final staffMemberId = await widget.staffGateway?.currentStaffMemberId();
    final editable = await widget.scheduleStore.editableSections();
    final monthToCheck = await ScheduleRules(
      widget.scheduleStore,
    ).monthAwaitingConfirmation();
    return _ScheduleData(
      sections,
      invitePending,
      canManageStaff,
      monthToCheck,
      !canManageStaff && editable.isEmpty ? staffMemberId : null,
      canManageStaff ? null : staffMemberId,
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
                if (data?.invitePending == true)
                  IconButton(
                    tooltip: 'Check confirmation',
                    onPressed: () => setState(() => _data = _loadData()),
                    icon: const Icon(Icons.refresh),
                  ),
                IconButton(
                  tooltip: 'Sign out',
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout),
                ),
              ],
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  data?.invitePending == true
                      ? 'Your Invite is waiting for the Manager to confirm it. '
                            'Check again after they review it.'
                      : "This email isn't on the ER staff list. "
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
          month:
              data?.monthToCheck ??
              DateTime.tryParse(Uri.base.queryParameters['month'] ?? '') ??
              DateTime(now.year, now.month),
          staffMemberId: data?.staffMemberId,
          swapStaffMemberId: data?.swapStaffMemberId,
          swapRules: widget.swapRules,
          openShiftRules: widget.openShiftRules,
          onSignOut: _signOut,
          messagesComposer: widget.messagesComposer,
          noticeGateway: widget.noticeGateway,
          staffGateway: widget.staffGateway,
          printBookPage: widget.printBookPage,
          printWordingGateway: widget.printWordingGateway,
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
              ? () async => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => StaffListPage(
                      gateway: widget.staffGateway!,
                      rules: ScheduleRules(widget.scheduleStore),
                      inviteComposer: widget.inviteComposer!,
                    ),
                  ),
                )
              : null,
          onOpenStaffDetails:
              data?.canManageStaff == true &&
                  widget.staffGateway != null &&
                  widget.inviteComposer != null
              ? (staffMemberId) async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => StaffDetailsPage(
                        staffMemberId: staffMemberId,
                        gateway: widget.staffGateway!,
                        rules: ScheduleRules(widget.scheduleStore),
                        inviteComposer: widget.inviteComposer!,
                      ),
                    ),
                  );
                }
              : null,
        );
      },
    );
  }
}

final class _ScheduleData {
  const _ScheduleData(
    this.sections,
    this.invitePending,
    this.canManageStaff,
    this.monthToCheck,
    this.staffMemberId,
    this.swapStaffMemberId,
  );

  final List<ScheduleSection> sections;
  final bool invitePending;
  final bool canManageStaff;
  final DateTime? monthToCheck;
  final String? staffMemberId;
  final String? swapStaffMemberId;
}
