import 'dart:async';

import 'package:flutter/material.dart';
import 'package:schedule_rules/schedule_rules.dart';

import '../app_dependencies.dart';
import '../auth/sign_in_failures_page.dart';
import '../calendar/calendar_feed_page.dart';
import '../calendar/undelivered_invitations_page.dart';
import '../help/help_page.dart';
import '../maintainer/maintainer_repair.dart';
import '../notifications/notices_page.dart';
import '../settings/manager_handover_page.dart';
import '../settings/settings_page.dart';
import '../setup/app_setup_page.dart';
import '../staff/staff_details_page.dart';
import '../staff/staff_list_page.dart';
import '../tickets/ticket_context.dart';
import '../tickets/ticket_gateway.dart';
import '../tickets/ticket_pages.dart';
import 'approval_queue_page.dart';
import 'change_log_page.dart';
import 'coverage_settings_page.dart';
import 'giveaways_page.dart';
import 'open_shifts_page.dart';
import 'pending_work.dart';
import 'requests_off_page.dart';
import 'shift_codes_page.dart';
import 'swaps_page.dart';

enum DestinationMenu { none, immediate, secondary }

enum DestinationSettings { personal, transfer, unit }

enum DestinationGroup { browseRequests }

typedef DestinationPageBuilder = Widget Function(
  BuildContext context,
  DateTime month,
);

typedef DestinationReturned = FutureOr<void> Function(
  BuildContext context,
  Object? result,
);

final class ScheduleDestination {
  const ScheduleDestination({
    required this.id,
    required this.label,
    required this.icon,
    required this.pageBuilder,
    this.menu = DestinationMenu.none,
    this.menuOrder = 0,
    this.settings,
    this.settingsOrder = 0,
    this.subtitle,
    this.badgeCount = 0,
    this.reloadMonth = false,
    this.group,
    this.onReturned,
  });

  final String id;
  final String label;
  final IconData icon;
  final DestinationPageBuilder pageBuilder;
  final DestinationMenu menu;
  final int menuOrder;
  final DestinationSettings? settings;
  final int settingsOrder;
  final String? subtitle;
  final int badgeCount;
  final bool reloadMonth;
  final DestinationGroup? group;
  final DestinationReturned? onReturned;

  String get menuLabel => badgeCount > 0 ? '$label ($badgeCount)' : label;
}

final class ScheduleDestinationCallbacks {
  const ScheduleDestinationCallbacks({
    this.onAccessRejected,
    this.onManagerTransferred,
    this.ticketContext,
    this.onManageStaff,
    this.onOpenStaffDetails,
  });

  final VoidCallback? onAccessRejected;
  final VoidCallback? onManagerTransferred;
  final TicketContext Function(DateTime month)? ticketContext;
  final Future<void> Function()? onManageStaff;
  final Future<void> Function(String staffMemberId)? onOpenStaffDetails;
}

List<ScheduleDestination> scheduleDestinations({
  required AppDependencies dependencies,
  required Access access,
  required PendingWorkState pending,
  ScheduleDestinationCallbacks callbacks = const ScheduleDestinationCallbacks(),
}) {
  final ownStaffMemberId = access.ownStaffMemberId;

  Future<void> openStaffList(BuildContext context) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StaffListPage(
            gateway: dependencies.staffGateway,
            rules: dependencies.rules,
            inviteComposer: dependencies.inviteComposer,
            onAccessRejected: callbacks.onAccessRejected,
          ),
        ),
      );

  Future<void> openStaffDetails(BuildContext context, String staffMemberId) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StaffDetailsPage(
            staffMemberId: staffMemberId,
            gateway: dependencies.staffGateway,
            rules: dependencies.rules,
            inviteComposer: dependencies.inviteComposer,
            onAccessRejected: callbacks.onAccessRejected,
          ),
        ),
      );

  Widget repairPage() => MaintainerRepairPage(
    controller: dependencies.repairController,
    ticketGateway: dependencies.ticketGateway,
  );

  return [
    ScheduleDestination(
      id: 'settings',
      label: 'Settings',
      icon: Icons.settings_outlined,
      menu: DestinationMenu.secondary,
      menuOrder: 10,
      pageBuilder: (context, month) => SettingsPage(
        dependencies: dependencies,
        access: access,
        month: month,
        pending: pending,
        destinationCallbacks: callbacks,
      ),
    ),
    ScheduleDestination(
      id: 'help',
      label: 'Help',
      icon: Icons.help_outline,
      menu: DestinationMenu.secondary,
      menuOrder: 50,
      pageBuilder: (_, _) => HelpPage(roles: helpRolesFor(access)),
    ),
    if (ownStaffMemberId != null)
      ScheduleDestination(
        id: 'putInTicket',
        label: 'Put in a ticket',
        icon: Icons.support_agent_outlined,
        menu: DestinationMenu.secondary,
        menuOrder: 20,
        pageBuilder: (_, month) => PutInTicketPage(
          gateway: dependencies.ticketGateway,
          onAccessRejected: callbacks.onAccessRejected,
          attachedContext:
              callbacks.ticketContext?.call(month) ??
              captureTicketContext(screen: 'Schedule', month: month),
        ),
      ),
    if (ownStaffMemberId != null)
      ScheduleDestination(
        id: 'myTickets',
        label: 'My tickets',
        icon: Icons.inbox_outlined,
        menu: DestinationMenu.secondary,
        menuOrder: 30,
        pageBuilder: (_, _) => TicketsPage(
          gateway: dependencies.ticketGateway,
          maintainer: false,
          ownStaffMemberId: ownStaffMemberId,
          onAccessRejected: callbacks.onAccessRejected,
        ),
      ),
    if (access.maintainer)
      ScheduleDestination(
        id: 'tickets',
        label: 'Tickets',
        icon: Icons.inbox_outlined,
        settings: DestinationSettings.personal,
        settingsOrder: 50,
        subtitle: 'Private messages from Staff',
        pageBuilder: (_, _) => TicketsPage(
          gateway: dependencies.ticketGateway,
          maintainer: true,
          onAccessRejected: callbacks.onAccessRejected,
        ),
      ),
    if (access.maintainer && !access.isRepairAccess)
      ScheduleDestination(
        id: 'maintainerRepairs',
        label: 'Maintainer repairs',
        icon: Icons.build_outlined,
        menu: DestinationMenu.secondary,
        menuOrder: 40,
        settings: DestinationSettings.personal,
        settingsOrder: 40,
        subtitle: 'Break the glass for marked Manager controls',
        pageBuilder: (_, _) => repairPage(),
      ),
    if (access.maintainer && access.isRepairAccess)
      ScheduleDestination(
        id: 'signInFailures',
        label: 'Sign-in failures',
        icon: Icons.mark_email_unread_outlined,
        settings: DestinationSettings.personal,
        settingsOrder: 60,
        subtitle: 'Code emails the provider could not send',
        pageBuilder: (_, _) =>
            SignInFailuresPage(log: dependencies.signInFailureLog),
      ),
    if (access.maintainer && access.isRepairAccess)
      ScheduleDestination(
        id: 'undeliveredInvitations',
        label: 'Undelivered invitations',
        icon: Icons.event_busy_outlined,
        settings: DestinationSettings.personal,
        settingsOrder: 70,
        subtitle: 'Calendar emails the provider could not send',
        pageBuilder: (_, _) => UndeliveredInvitationsPage(
          log: dependencies.undeliveredInvitationLog,
        ),
      ),
    if (access.canRunSchedule)
      ScheduleDestination(
        id: 'approvalQueue',
        label: 'Approval queue',
        icon: Icons.fact_check_outlined,
        menu: DestinationMenu.immediate,
        menuOrder: 60,
        badgeCount: pending.pendingApprovals,
        pageBuilder: (_, _) => ApprovalQueuePage(
          rules: dependencies.rules,
          swapStore: dependencies.swapStore,
          giveawayStore: dependencies.giveawayStore,
          openShiftStore: dependencies.openShiftStore,
          staffGateway: dependencies.staffGateway,
          onAccessRejected: callbacks.onAccessRejected,
        ),
      ),
    if (access.canAskAsStaffMember)
      ScheduleDestination(
        id: 'openShiftsStaff',
        label: 'Open shifts',
        icon: Icons.add_circle_outline,
        menu: DestinationMenu.immediate,
        menuOrder: 70,
        pageBuilder: (_, month) => OpenShiftsPage(
          rules: dependencies.openShiftStore,
          scheduleRules: dependencies.rules,
          month: month,
          staffMemberId: ownStaffMemberId,
          isManager: false,
        ),
      ),
    if (access.canAskAsStaffMember)
      ScheduleDestination(
        id: 'swapsStaff',
        label: 'Swaps',
        icon: Icons.swap_horiz,
        menu: DestinationMenu.immediate,
        menuOrder: 80,
        badgeCount: pending.pendingSwaps,
        pageBuilder: (_, month) => SwapsPage(
          rules: dependencies.rules,
          swapStore: dependencies.swapStore,
          month: month,
          staffMemberId: ownStaffMemberId,
          isManager: false,
          messagesComposer: dependencies.messagesComposer,
          onAccessRejected: callbacks.onAccessRejected,
        ),
      ),
    if (access.canAskAsStaffMember)
      ScheduleDestination(
        id: 'giveawaysStaff',
        label: 'Giveaways',
        icon: Icons.card_giftcard,
        menu: DestinationMenu.immediate,
        menuOrder: 90,
        pageBuilder: (_, month) => GiveawaysPage(
          rules: dependencies.rules,
          giveawayStore: dependencies.giveawayStore,
          month: month,
          staffMemberId: ownStaffMemberId,
          onAccessRejected: callbacks.onAccessRejected,
        ),
      ),
    if (access.canAskAsStaffMember)
      ScheduleDestination(
        id: 'myRequestsOff',
        label: 'My Requests off',
        icon: Icons.event_busy_outlined,
        menu: DestinationMenu.immediate,
        menuOrder: 120,
        badgeCount: pending.unreadRequestsOff,
        pageBuilder: (_, _) =>
            RequestsOffPage(rules: dependencies.rules, isManager: false),
      ),
    if (access.canRunSchedule)
      ScheduleDestination(
        id: 'requestsOffManager',
        label: 'Requests off',
        icon: Icons.event_busy_outlined,
        menu: DestinationMenu.immediate,
        menuOrder: 130,
        group: DestinationGroup.browseRequests,
        pageBuilder: (_, _) =>
            RequestsOffPage(rules: dependencies.rules, isManager: true),
      ),
    if (access.canRunSchedule)
      ScheduleDestination(
        id: 'swapsManager',
        label: 'Swaps',
        icon: Icons.swap_horiz,
        menu: DestinationMenu.immediate,
        menuOrder: 130,
        group: DestinationGroup.browseRequests,
        pageBuilder: (_, month) => SwapsPage(
          rules: dependencies.rules,
          swapStore: dependencies.swapStore,
          month: month,
          staffMemberId: ownStaffMemberId,
          isManager: true,
          messagesComposer: dependencies.messagesComposer,
          onAccessRejected: callbacks.onAccessRejected,
        ),
      ),
    if (access.canRunSchedule)
      ScheduleDestination(
        id: 'giveawaysManager',
        label: 'Giveaways',
        icon: Icons.card_giftcard,
        menu: DestinationMenu.immediate,
        menuOrder: 130,
        group: DestinationGroup.browseRequests,
        pageBuilder: (_, month) => GiveawaysPage(
          rules: dependencies.rules,
          giveawayStore: dependencies.giveawayStore,
          month: month,
          staffMemberId: ownStaffMemberId,
          onAccessRejected: callbacks.onAccessRejected,
        ),
      ),
    if (access.canRunSchedule)
      ScheduleDestination(
        id: 'openShiftsManager',
        label: 'Open shifts',
        icon: Icons.add_circle_outline,
        menu: DestinationMenu.immediate,
        menuOrder: 130,
        group: DestinationGroup.browseRequests,
        pageBuilder: (context, month) => OpenShiftsPage(
          rules: dependencies.openShiftStore,
          scheduleRules: dependencies.rules,
          month: month,
          staffMemberId: ownStaffMemberId,
          isManager: true,
          onApprovalSettings: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ApprovalDefaultPage(rules: dependencies.openShiftStore),
            ),
          ),
        ),
      ),
    if (ownStaffMemberId != null)
      ScheduleDestination(
        id: 'notices',
        label: 'Notices',
        icon: Icons.notifications_outlined,
        menu: DestinationMenu.secondary,
        menuOrder: 100,
        settings: DestinationSettings.personal,
        settingsOrder: 30,
        subtitle: 'Allow notices in this place',
        pageBuilder: (_, _) => NoticesPage(gateway: dependencies.noticeGateway),
      ),
    if (ownStaffMemberId != null)
      ScheduleDestination(
        id: 'myCalendar',
        label: 'My calendar',
        icon: Icons.calendar_month_outlined,
        menu: DestinationMenu.secondary,
        menuOrder: 110,
        settings: DestinationSettings.personal,
        settingsOrder: 20,
        subtitle: 'Choose calendar invitations or a feed',
        pageBuilder: (_, _) =>
            CalendarFeedPage(gateway: dependencies.calendarFeedGateway),
      ),
    ScheduleDestination(
      id: 'addErSchedule',
      label: 'Add ER Schedule',
      icon: Icons.install_mobile_outlined,
      settings: DestinationSettings.personal,
      settingsOrder: 10,
      subtitle: 'Install on a phone or computer',
      pageBuilder: (_, _) => AppSetupPage(
        noticeGateway: dependencies.noticeGateway,
        canAllowNotifications: ownStaffMemberId != null,
        helpRoles: helpRolesFor(access),
      ),
    ),
    if (access.canManageUnit)
      ScheduleDestination(
        id: 'staffingMinimums',
        label: 'Staffing minimums',
        icon: Icons.people_outline,
        menu: DestinationMenu.immediate,
        menuOrder: 140,
        settings: DestinationSettings.unit,
        settingsOrder: 10,
        subtitle: 'Coverage pools and standing weekday rules',
        reloadMonth: true,
        pageBuilder: (_, _) => CoverageSettingsPage(
          rules: dependencies.openShiftStore,
          scheduleRules: dependencies.rules,
        ),
      ),
    if (access.canManageUnit)
      ScheduleDestination(
        id: 'openShiftPickupApproval',
        label: 'Open shift pickup approval',
        icon: Icons.fact_check_outlined,
        settings: DestinationSettings.unit,
        settingsOrder: 20,
        subtitle: 'Default for newly posted shifts',
        pageBuilder: (_, _) =>
            ApprovalDefaultPage(rules: dependencies.openShiftStore),
      ),
    if (access.canManageUnit)
      ScheduleDestination(
        id: 'printWording',
        label: 'Print wording',
        icon: Icons.text_fields_outlined,
        settings: DestinationSettings.unit,
        settingsOrder: 30,
        subtitle: 'Default for draft and future months',
        pageBuilder: (_, _) =>
            PrintWordingPage(gateway: dependencies.printWordingGateway),
      ),
    if (access.canManageUnit)
      ScheduleDestination(
        id: 'shiftCodes',
        label: 'Shift codes',
        icon: Icons.schedule_outlined,
        menu: DestinationMenu.secondary,
        menuOrder: 150,
        settings: DestinationSettings.unit,
        settingsOrder: 40,
        reloadMonth: true,
        pageBuilder: (_, _) => ShiftCodesPage(
          rules: dependencies.rules,
          onAccessRejected: callbacks.onAccessRejected,
        ),
      ),
    if (access.canReadChangeLog)
      ScheduleDestination(
        id: 'changeLog',
        label: 'Change log',
        icon: Icons.history,
        menu: DestinationMenu.secondary,
        menuOrder: 160,
        pageBuilder: (_, month) =>
            ChangeLogPage(rules: dependencies.rules, month: month),
      ),
    if (access.canManageStaff)
      ScheduleDestination(
        id: 'staffList',
        label: 'Staff list',
        icon: Icons.people_outline,
        menu: DestinationMenu.secondary,
        menuOrder: 170,
        reloadMonth: true,
        pageBuilder: (_, _) => StaffListPage(
          gateway: dependencies.staffGateway,
          rules: dependencies.rules,
          inviteComposer: dependencies.inviteComposer,
          onAccessRejected: callbacks.onAccessRejected,
        ),
      ),
    if (access.canManageUnit)
      ScheduleDestination(
        id: 'sections',
        label: 'Sections',
        icon: Icons.view_list_outlined,
        settings: DestinationSettings.unit,
        settingsOrder: 50,
        subtitle: 'Edit on the Staff list',
        pageBuilder: (_, _) => StaffListPage(
          gateway: dependencies.staffGateway,
          rules: dependencies.rules,
          inviteComposer: dependencies.inviteComposer,
          onAccessRejected: callbacks.onAccessRejected,
        ),
      ),
    if (access.canManageUnit)
      ScheduleDestination(
        id: 'permissionAssignments',
        label: 'Permission assignments',
        icon: Icons.admin_panel_settings_outlined,
        settings: DestinationSettings.unit,
        settingsOrder: 60,
        subtitle: 'Open a person on the Staff list',
        pageBuilder: (_, _) => StaffListPage(
          gateway: dependencies.staffGateway,
          rules: dependencies.rules,
          inviteComposer: dependencies.inviteComposer,
          onAccessRejected: callbacks.onAccessRejected,
        ),
      ),
    if (access.canTransferManager)
      ScheduleDestination(
        id: 'transferManager',
        label: 'Transfer Manager',
        icon: Icons.manage_accounts_outlined,
        settings: DestinationSettings.transfer,
        subtitle: access.isRepairAccess
            ? 'Choose a new Manager for repair'
            : 'Choose the next Manager and your access after handover',
        pageBuilder: (context, _) => ManagerHandoverPage(
          gateway: dependencies.staffGateway,
          isMaintainer: access.isRepairAccess,
          onManageStaff:
              callbacks.onManageStaff ?? () => openStaffList(context),
          onOpenStaffDetails:
              callbacks.onOpenStaffDetails ??
              (id) => openStaffDetails(context, id),
          onAccessRejected: callbacks.onAccessRejected,
        ),
        onReturned: (context, result) {
          if (result == true) {
            Navigator.maybePop(context);
            callbacks.onManagerTransferred?.call();
          }
        },
      ),
    if (access.canManageUnit)
      ScheduleDestination(
        id: 'settingsHistory',
        label: 'Settings history',
        icon: Icons.history,
        settings: DestinationSettings.unit,
        settingsOrder: 70,
        pageBuilder: (_, _) =>
            SettingsHistoryPage(history: dependencies.settingsHistory),
      ),
  ];
}

List<ScheduleDestination> lockedSettingsDestinations({
  required AppDependencies dependencies,
  required Access access,
  required PendingWorkState pending,
  ScheduleDestinationCallbacks callbacks = const ScheduleDestinationCallbacks(),
}) {
  if (!access.maintainer || access.isRepairAccess) return const [];
  final currentIds = scheduleDestinations(
    dependencies: dependencies,
    access: access,
    pending: pending,
    callbacks: callbacks,
  ).where((entry) => entry.settings != null).map((entry) => entry.id).toSet();
  final repair = MaintainerRepair(
    id: 'derived-settings-preview',
    category: RepairReasonCategory.investigation,
    openedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    expiresAt: DateTime.fromMillisecondsSinceEpoch(1, isUtc: true),
  );
  final repairingAccess = Access(
    grants: access.grants,
    maintainer: true,
    ownStaffMemberId: access.ownStaffMemberId,
    activeRepair: repair,
  );
  final locked =
      scheduleDestinations(
            dependencies: dependencies,
            access: repairingAccess,
            pending: pending,
            callbacks: callbacks,
          )
          .where(
            (entry) => entry.settings != null && !currentIds.contains(entry.id),
          )
          .toList();
  int order(ScheduleDestination entry) => switch (entry.settings!) {
    DestinationSettings.transfer => 0,
    DestinationSettings.personal => 10 + entry.settingsOrder,
    DestinationSettings.unit => 100 + entry.settingsOrder,
  };
  locked.sort((first, second) => order(first).compareTo(order(second)));
  return List.unmodifiable(locked);
}
