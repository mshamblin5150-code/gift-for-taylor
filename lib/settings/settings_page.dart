import 'package:flutter/material.dart';
import 'package:schedule_rules/schedule_rules.dart';

import '../auth/sign_in_failure_log.dart';
import '../auth/sign_in_failures_page.dart';
import '../calendar/undelivered_invitation_log.dart';
import '../calendar/undelivered_invitations_page.dart';
import '../notifications/notice_gateway.dart';
import '../maintainer/maintainer_repair.dart';
import '../maintainer/repair_controller.dart';
import '../notifications/notices_page.dart';
import '../help/help_page.dart';
import '../schedule/print_wording_dialog.dart';
import '../schedule/print_wording_gateway.dart';
import '../schedule/shift_codes_page.dart';
import '../schedule/coverage_settings_page.dart';
import 'appearance.dart';
import '../setup/app_setup_page.dart';
import '../staff/staff_gateway.dart';
import 'manager_handover_page.dart';
import 'settings_history.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.scheduleRules,
    required this.noticeGateway,
    this.openShiftStore,
    this.printWordingGateway,
    this.onCalendarFeed,
    this.onManageStaff,
    this.onOpenStaffDetails,
    required this.access,
    this.settingsHistory,
    this.signInFailureLog,
    required this.undeliveredInvitationLog,
    this.staffGateway,
    this.onManagerTransferred,
    this.onAccessRejected,
    required this.maintainerRepairController,
  });

  final ScheduleRules scheduleRules;
  final OpenShiftStore? openShiftStore;
  final NoticeGateway noticeGateway;
  final PrintWordingGateway? printWordingGateway;
  final VoidCallback? onCalendarFeed;
  final Future<void> Function()? onManageStaff;
  final Future<void> Function(String staffMemberId)? onOpenStaffDetails;
  final Access access;
  final SettingsHistory? settingsHistory;
  final SignInFailureLog? signInFailureLog;
  final UndeliveredInvitationLog undeliveredInvitationLog;
  final StaffGateway? staffGateway;
  final VoidCallback? onManagerTransferred;
  final VoidCallback? onAccessRejected;
  final RepairController maintainerRepairController;

  @override
  Widget build(BuildContext context) {
    void open(Widget page) {
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
    }

    void openRepair() =>
        open(MaintainerRepairPage(controller: maintainerRepairController));

    ListTile repairRequired(String title, IconData icon) => ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: const Text('Requires a Repair — tap to break the glass'),
      trailing: const Icon(Icons.lock_outline),
      onTap: openRepair,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeading('Personal'),
          const AppearanceTile(),
          ListTile(
            leading: const Icon(Icons.install_mobile_outlined),
            title: const Text('Add ER Schedule'),
            subtitle: const Text('Install on a phone or computer'),
            onTap: () => open(
              AppSetupPage(
                noticeGateway: noticeGateway,
                canAllowNotifications: access.ownStaffMemberId != null,
                helpRoles: helpRolesFor(access),
              ),
            ),
          ),
          if (access.canUseOwnSettings && onCalendarFeed != null)
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('My calendar'),
              subtitle: const Text('Choose calendar invitations or a feed'),
              onTap: onCalendarFeed,
            ),
          if (access.canUseOwnSettings)
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Notifications'),
              subtitle: const Text('Allow notices in this place'),
              onTap: () => open(NoticesPage(gateway: noticeGateway)),
            ),
          if (access.maintainer)
            ListTile(
              leading: const Icon(Icons.build_outlined),
              title: const Text('Maintainer repairs'),
              subtitle: Text(
                access.isRepairAccess
                    ? 'A Repair is open'
                    : 'Break the glass for marked Manager controls',
              ),
              onTap: access.isRepairAccess ? null : openRepair,
            ),
          if (access.maintainer &&
              access.isRepairAccess &&
              signInFailureLog != null)
            ListTile(
              leading: const Icon(Icons.mark_email_unread_outlined),
              title: const Text('Sign-in failures'),
              subtitle: const Text('Code emails the provider could not send'),
              onTap: () => open(SignInFailuresPage(log: signInFailureLog!)),
            ),
          if (access.maintainer && access.isRepairAccess)
            ListTile(
              leading: const Icon(Icons.event_busy_outlined),
              title: const Text('Undelivered invitations'),
              subtitle: const Text(
                'Calendar emails the provider could not send',
              ),
              onTap: () => open(
                UndeliveredInvitationsPage(log: undeliveredInvitationLog),
              ),
            ),
          if (access.maintainer && !access.isRepairAccess) ...[
            const _SectionHeading('Manager controls'),
            if (staffGateway != null)
              repairRequired(
                'Transfer Manager',
                Icons.manage_accounts_outlined,
              ),
            if (openShiftStore != null) ...[
              repairRequired('Staffing minimums', Icons.people_outline),
              repairRequired(
                'Open shift pickup approval',
                Icons.fact_check_outlined,
              ),
            ],
            if (printWordingGateway != null)
              repairRequired('Print wording', Icons.text_fields_outlined),
            repairRequired('Shift codes', Icons.schedule_outlined),
            if (onManageStaff != null) ...[
              repairRequired('Sections', Icons.view_list_outlined),
              repairRequired(
                'Permission assignments',
                Icons.admin_panel_settings_outlined,
              ),
            ],
          ],
          if (access.canTransferManager && staffGateway != null)
            ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: const Text('Transfer Manager'),
              subtitle: Text(
                access.isRepairAccess
                    ? 'Choose a new Manager for repair'
                    : 'Choose the next Manager and your access after handover',
              ),
              onTap: () async {
                final transferred = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ManagerHandoverPage(
                      gateway: staffGateway!,
                      isMaintainer: access.isRepairAccess,
                      onManageStaff: onManageStaff,
                      onOpenStaffDetails: onOpenStaffDetails,
                      onAccessRejected: onAccessRejected,
                    ),
                  ),
                );
                if (transferred == true && context.mounted) {
                  Navigator.pop(context);
                  onManagerTransferred?.call();
                }
              },
            ),
          if (access.canManageUnit) ...[
            const _SectionHeading('Unit'),
            if (openShiftStore != null) ...[
              ListTile(
                leading: const Icon(Icons.people_outline),
                title: const Text('Staffing minimums'),
                subtitle: const Text(
                  'Coverage pools and standing weekday rules',
                ),
                onTap: () => open(
                  CoverageSettingsPage(
                    rules: openShiftStore!,
                    scheduleRules: scheduleRules,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.fact_check_outlined),
                title: const Text('Open shift pickup approval'),
                subtitle: const Text('Default for newly posted shifts'),
                onTap: () => open(ApprovalDefaultPage(rules: openShiftStore!)),
              ),
            ],
            if (printWordingGateway != null)
              ListTile(
                leading: const Icon(Icons.text_fields_outlined),
                title: const Text('Print wording'),
                subtitle: const Text('Default for draft and future months'),
                onTap: () =>
                    open(_PrintWordingPage(gateway: printWordingGateway!)),
              ),
            ListTile(
              leading: const Icon(Icons.schedule_outlined),
              title: const Text('Shift codes'),
              onTap: () => open(ShiftCodesPage(rules: scheduleRules)),
            ),
            if (onManageStaff != null) ...[
              ListTile(
                leading: const Icon(Icons.view_list_outlined),
                title: const Text('Sections'),
                subtitle: const Text('Edit on the Staff list'),
                onTap: onManageStaff,
              ),
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Permission assignments'),
                subtitle: const Text('Open a person on the Staff list'),
                onTap: onManageStaff,
              ),
            ],
            if (settingsHistory != null)
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Settings history'),
                onTap: () =>
                    open(_SettingsHistoryPage(history: settingsHistory!)),
              ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );
}

class ApprovalDefaultPage extends StatefulWidget {
  const ApprovalDefaultPage({super.key, required this.rules});
  final OpenShiftStore rules;
  @override
  State<ApprovalDefaultPage> createState() => _ApprovalDefaultPageState();
}

class _ApprovalDefaultPageState extends State<ApprovalDefaultPage> {
  late Future<bool> _choice = widget.rules.approvalDefault();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Open shift pickup approval')),
    body: FutureBuilder<bool>(
      future: _choice,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load the default.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return SwitchListTile(
          title: const Text('Require approval'),
          subtitle: const Text(
            'Applies only to Open shifts posted after this change.',
          ),
          value: snapshot.data!,
          onChanged: (value) async {
            try {
              await widget.rules.setApprovalDefault(value);
              if (mounted) setState(() => _choice = Future.value(value));
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('The default was not saved.')),
                );
              }
            }
          },
        );
      },
    ),
  );
}

class _PrintWordingPage extends StatefulWidget {
  const _PrintWordingPage({required this.gateway});
  final PrintWordingGateway gateway;
  @override
  State<_PrintWordingPage> createState() => _PrintWordingPageState();
}

class _PrintWordingPageState extends State<_PrintWordingPage> {
  late Future<PrintWording> _wording = widget.gateway.read();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Print wording')),
    body: FutureBuilder<PrintWording>(
      future: _wording,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load print wording.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final wording = snapshot.data!;
        return ListTile(
          title: Text(wording.title),
          subtitle: const Text(
            'Draft prints and future month releases use this default.',
          ),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () async {
            final next = await showPrintWordingDialog(context, wording);
            if (next == null) return;
            try {
              await widget.gateway.save(next);
              if (mounted) setState(() => _wording = Future.value(next));
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('The print wording was not saved.'),
                  ),
                );
              }
            }
          },
        );
      },
    ),
  );
}

class _SettingsHistoryPage extends StatefulWidget {
  const _SettingsHistoryPage({required this.history});
  final SettingsHistory history;

  @override
  State<_SettingsHistoryPage> createState() => _SettingsHistoryPageState();
}

class _SettingsHistoryPageState extends State<_SettingsHistoryPage> {
  late final Future<List<SettingsHistoryEntry>> _entries = widget.history
      .read();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings history')),
    body: FutureBuilder<List<SettingsHistoryEntry>>(
      future: _entries,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load settings history.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(child: Text('No settings history yet.'));
        }
        return ListView(
          children: [
            for (final entry in snapshot.data!)
              ListTile(
                title: Text(entry.kind),
                subtitle: Text(
                  '${entry.actor} · ${entry.changedAt}'
                  '${entry.repairReason == null ? '' : '\nRepair reason: ${entry.repairReason}'}'
                  '\nBefore: ${entry.before}\nAfter: ${entry.after}',
                ),
                isThreeLine: true,
              ),
          ],
        );
      },
    ),
  );
}
