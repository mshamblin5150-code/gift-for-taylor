import 'package:flutter/material.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_dependencies.dart';
import 'auth/auth_gateway.dart';
import 'auth/sign_in_failure_log.dart';
import 'auth/sign_in_page.dart';
import 'auth/sign_in_session.dart';
import 'calendar/calendar_feed_page.dart';
import 'maintainer/maintainer_repair.dart';
import 'notifications/notice_gateway.dart';
import 'schedule/month_grid_page.dart';
import 'staff/staff_gateway.dart';
import 'staff/refusal_wording.dart';
import 'staff/staff_list_page.dart';
import 'staff/staff_details_page.dart';
import 'schedule_theme.dart';
import 'settings/appearance.dart';
import 'setup/app_setup_page.dart';

const notificationSetupShownPreferenceKey = 'notification_setup_shown';

void _openSetup(
  BuildContext context,
  NoticeGateway noticeGateway, {
  bool awaitingConfirmation = false,
  bool canAllowNotifications = false,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AppSetupPage(
        noticeGateway: noticeGateway,
        awaitingConfirmation: awaitingConfirmation,
        canAllowNotifications: canAllowNotifications,
      ),
    ),
  );
}

class ScheduleApp extends StatelessWidget {
  const ScheduleApp({
    super.key,
    required this.dependencies,
    this.inviteToken,
    this.navigatorKey,
  });

  final AppDependencies dependencies;
  final String? inviteToken;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appearanceMode,
      builder: (context, mode, _) => MaterialApp(
        navigatorKey: navigatorKey,
        title: 'ER Schedule',
        theme: ScheduleTheme.light,
        darkTheme: ScheduleTheme.dark,
        themeMode: mode,
        builder: (context, child) => Stack(
          fit: StackFit.expand,
          children: [
            child ?? const SizedBox.shrink(),
            Align(
              alignment: Alignment.bottomCenter,
              child: RepairBanner(
                controller: dependencies.repairController,
                onClosed: () => navigatorKey?.currentState?.popUntil(
                  (route) => route.isFirst,
                ),
              ),
            ),
          ],
        ),
        home: _AuthGate(dependencies: dependencies, inviteToken: inviteToken),
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate({required this.dependencies, required this.inviteToken});

  final AppDependencies dependencies;
  final String? inviteToken;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  late final Future<void> _prepareInviteSignIn = _prepareInvite();
  String? _inviteCellNumber;

  Future<void> _prepareInvite() async {
    if (widget.inviteToken != null &&
        widget.dependencies.authGateway.isSignedIn) {
      await widget.dependencies.authGateway.signOut();
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
          stream: widget.dependencies.authGateway.signedInChanges,
          initialData: widget.dependencies.authGateway.isSignedIn,
          builder: (context, snapshot) {
            if (snapshot.data != true) {
              if (widget.inviteToken != null && _inviteCellNumber == null) {
                return _InviteCellEntry(
                  onContinue: (number) =>
                      setState(() => _inviteCellNumber = number),
                  noticeGateway: widget.dependencies.noticeGateway,
                );
              }
              return _SignInPageHost(
                authGateway: widget.dependencies.authGateway,
                failureLog: widget.dependencies.signInFailureLog,
                noticeGateway: widget.dependencies.noticeGateway,
                awaitingConfirmation: widget.inviteToken != null,
              );
            }
            if (widget.inviteToken != null) {
              return _InviteAcceptance(
                dependencies: widget.dependencies,
                inviteToken: widget.inviteToken!,
                cellNumber: _inviteCellNumber!,
              );
            }
            return _ScheduleAccess(dependencies: widget.dependencies);
          },
        );
      },
    );
  }
}

class _SignInPageHost extends StatefulWidget {
  const _SignInPageHost({
    required this.authGateway,
    required this.failureLog,
    required this.noticeGateway,
    required this.awaitingConfirmation,
  });

  final AuthGateway authGateway;
  final SignInFailureLog failureLog;
  final NoticeGateway noticeGateway;
  final bool awaitingConfirmation;

  @override
  State<_SignInPageHost> createState() => _SignInPageHostState();
}

class _SignInPageHostState extends State<_SignInPageHost> {
  late final SignInSession _session = SignInSession(
    widget.authGateway,
    widget.failureLog,
  );

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SignInPage(
    session: _session,
    noticeGateway: widget.noticeGateway,
    awaitingConfirmation: widget.awaitingConfirmation,
  );
}

class _InviteCellEntry extends StatefulWidget {
  const _InviteCellEntry({
    required this.onContinue,
    required this.noticeGateway,
  });

  final ValueChanged<String> onContinue;
  final NoticeGateway noticeGateway;

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
    appBar: AppBar(actions: const [AppearanceButton()]),
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
                const SizedBox(height: 8),
                const Text(
                  'You can add ER Schedule to this phone and to a computer now or after accepting your Invite.',
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
                TextButton(
                  onPressed: () => _openSetup(
                    context,
                    widget.noticeGateway,
                    awaitingConfirmation: true,
                  ),
                  child: const Text('Add ER Schedule'),
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
    required this.dependencies,
    required this.inviteToken,
    required this.cellNumber,
  });

  final AppDependencies dependencies;
  final String inviteToken;
  final String cellNumber;

  @override
  State<_InviteAcceptance> createState() => _InviteAcceptanceState();
}

class _InviteAcceptanceState extends State<_InviteAcceptance> {
  late Future<InviteAcceptanceResult> _acceptance = widget
      .dependencies
      .staffGateway
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
          final message = switch (snapshot.error) {
            StaffInviteAlreadyLinkedException() =>
              'This email is already signed in as another Staff member.',
            InvalidInviteException() =>
              'This Invite is invalid, expired, or has already been used. '
                  'Ask your Manager to resend it.',
            final error =>
              inviteAcceptanceRefusalWording(error) ??
                  'Could not check this Invite. Try again.',
          };
          return Scaffold(
            appBar: AppBar(
              actions: [
                const AppearanceButton(),
                IconButton(
                  tooltip: 'Sign out',
                  onPressed: widget.dependencies.authGateway.signOut,
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
            appBar: AppBar(actions: const [AppearanceButton()]),
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
                              _acceptance = widget.dependencies.staffGateway
                                  .acceptInvite(
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
        return _ScheduleAccess(dependencies: widget.dependencies);
      },
    );
  }
}

class _ScheduleAccess extends StatefulWidget {
  const _ScheduleAccess({required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<_ScheduleAccess> createState() => _ScheduleAccessState();
}

class _ScheduleAccessState extends State<_ScheduleAccess>
    with WidgetsBindingObserver {
  late Future<_ScheduleData> _data = _loadData();
  bool _setupScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.dependencies.repairController.accessRevision.addListener(
      _refreshAccess,
    );
  }

  @override
  void dispose() {
    widget.dependencies.repairController.accessRevision.removeListener(
      _refreshAccess,
    );
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshAccess();
  }

  void _refreshAccess() {
    if (mounted) {
      setState(() {
        _data = _loadData();
      });
    }
  }

  Future<void> _signOut() async {
    try {
      await widget.dependencies.noticeGateway.disablePush();
    } finally {
      await widget.dependencies.authGateway.signOut();
      widget.dependencies.repairController.synchronize(null);
    }
  }

  Future<_ScheduleData> _loadData() async {
    final sections = await widget.dependencies.scheduleStore.sections();
    final invitePending = sections.isEmpty
        ? await widget.dependencies.staffGateway.isInviteAcceptancePending()
        : false;
    final access = await widget.dependencies.staffGateway.currentAccess();
    final showNotificationSetup =
        sections.isNotEmpty &&
        access.ownStaffMemberId != null &&
        await _shouldShowNotificationSetup();
    widget.dependencies.repairController.synchronize(access.activeRepair);
    final monthToCheck =
        (await widget.dependencies.scheduleStore.monthsAwaitingConfirmation())
            .firstOrNull;
    return _ScheduleData(
      sections,
      invitePending,
      access,
      monthToCheck,
      !access.canRunSchedule &&
              access.editableSections.isEmpty &&
              !access.canManageStaff
          ? access.ownStaffMemberId
          : null,
      access.canRunSchedule ? null : access.ownStaffMemberId,
      showNotificationSetup,
    );
  }

  Future<bool> _shouldShowNotificationSetup() async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(notificationSetupShownPreferenceKey) == true) {
      return false;
    }
    try {
      return await widget.dependencies.noticeGateway.pushState() !=
          PushState.enabled;
    } catch (_) {
      return true;
    }
  }

  void _offerNotificationSetupIfNeeded(_ScheduleData data) {
    if (_setupScheduled || !data.showNotificationSetup) return;
    _setupScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(notificationSetupShownPreferenceKey, true);
      if (mounted) {
        _openSetup(
          context,
          widget.dependencies.noticeGateway,
          canAllowNotifications: true,
        );
      }
    });
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
                    onPressed: _refreshAccess,
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
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        data?.invitePending == true
                            ? 'Your Invite is waiting for the Manager to confirm it. Check again after they review it. You can add ER Schedule on this device and a computer while you wait.'
                            : "This email isn't on the ER staff list. Ask your Manager to add you.",
                        textAlign: TextAlign.center,
                      ),
                      if (data?.invitePending == true) ...[
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: () => _openSetup(
                            context,
                            widget.dependencies.noticeGateway,
                            awaitingConfirmation: true,
                          ),
                          child: const Text('Add ER Schedule'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        _offerNotificationSetupIfNeeded(data!);

        // A month loaded from the printed page opens first until it is checked.
        final now = DateTime.now();
        return MonthGridPage(
          key: ValueKey((
            data.access,
            data.staffMemberId,
            data.swapStaffMemberId,
          )),
          rules: widget.dependencies.rules,
          access: data.access,
          onAccessRejected: _refreshAccess,
          viewerId: widget.dependencies.authGateway.currentUserId,
          month:
              data.monthToCheck ??
              DateTime.tryParse(Uri.base.queryParameters['month'] ?? '') ??
              DateTime(now.year, now.month),
          staffMemberId: data.staffMemberId,
          swapStaffMemberId: data.swapStaffMemberId,
          swapStore: widget.dependencies.swapStore,
          giveawayStore: widget.dependencies.giveawayStore,
          openShiftStore: widget.dependencies.openShiftStore,
          onSignOut: _signOut,
          onManagerTransferred: _refreshAccess,
          messagesComposer: widget.dependencies.messagesComposer,
          noticeGateway: widget.dependencies.noticeGateway,
          staffGateway: widget.dependencies.staffGateway,
          bookPagePresenter: widget.dependencies.bookPagePresenter,
          printWordingGateway: widget.dependencies.printWordingGateway,
          settingsHistory: widget.dependencies.settingsHistory,
          signInFailureLog: widget.dependencies.signInFailureLog,
          undeliveredInvitationLog:
              widget.dependencies.undeliveredInvitationLog,
          repairController: widget.dependencies.repairController,
          onCalendarFeed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => CalendarFeedPage(
                gateway: widget.dependencies.calendarFeedGateway,
              ),
            ),
          ),
          onManageStaff: data.access.canManageStaff
              ? () async => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => StaffListPage(
                      gateway: widget.dependencies.staffGateway,
                      rules: widget.dependencies.rules,
                      inviteComposer: widget.dependencies.inviteComposer,
                      onAccessRejected: _refreshAccess,
                    ),
                  ),
                )
              : null,
          onOpenStaffDetails: data.access.canManageStaff
              ? (staffMemberId) async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => StaffDetailsPage(
                        staffMemberId: staffMemberId,
                        gateway: widget.dependencies.staffGateway,
                        rules: widget.dependencies.rules,
                        inviteComposer: widget.dependencies.inviteComposer,
                        onAccessRejected: _refreshAccess,
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
    this.access,
    this.monthToCheck,
    this.staffMemberId,
    this.swapStaffMemberId,
    this.showNotificationSetup,
  );

  final List<ScheduleSection> sections;
  final bool invitePending;
  final Access access;
  final DateTime? monthToCheck;
  final String? staffMemberId;
  final String? swapStaffMemberId;
  final bool showNotificationSetup;
}
