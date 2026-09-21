import 'package:flutter/material.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../notifications/notice_gateway.dart';
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

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.scheduleRules,
    this.openShiftStore,
    this.noticeGateway,
    this.printWordingGateway,
    this.onCalendarFeed,
    this.onManageStaff,
    required this.access,
    this.auditClient,
    this.staffGateway,
    this.onManagerTransferred,
  });

  final ScheduleRules scheduleRules;
  final OpenShiftStore? openShiftStore;
  final NoticeGateway? noticeGateway;
  final PrintWordingGateway? printWordingGateway;
  final VoidCallback? onCalendarFeed;
  final Future<void> Function()? onManageStaff;
  final Access access;
  final SupabaseClient? auditClient;
  final StaffGateway? staffGateway;
  final VoidCallback? onManagerTransferred;

  @override
  Widget build(BuildContext context) {
    void open(Widget page) {
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
    }

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
            onTap: () => open(AppSetupPage(helpRoles: helpRolesFor(access))),
          ),
          if (access.canUseOwnSettings && onCalendarFeed != null)
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('My calendar'),
              subtitle: const Text('Choose calendar invitations or a feed'),
              onTap: onCalendarFeed,
            ),
          if (access.canUseOwnSettings && noticeGateway != null)
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Notifications'),
              subtitle: const Text('Allow notices on this device'),
              onTap: () => open(NoticesPage(gateway: noticeGateway!)),
            ),
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
            if (auditClient != null)
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Unit audit history'),
                onTap: () => open(_UnitAuditPage(client: auditClient!)),
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

class _UnitAuditPage extends StatelessWidget {
  const _UnitAuditPage({required this.client});
  final SupabaseClient client;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Unit audit history')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: client
          .from('unit_setting_audit')
          .select(
            'kind, actor_name, changed_at, repair_reason, before_value, after_value',
          )
          .order('changed_at', ascending: false)
          .limit(200),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load audit history.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          children: [
            for (final entry in snapshot.data!)
              ListTile(
                title: Text(entry['kind'] as String),
                subtitle: Text(
                  '${entry['actor_name']} · ${entry['changed_at']}'
                  '${entry['repair_reason'] == null ? '' : '\nRepair reason: ${entry['repair_reason']}'}'
                  '\nBefore: ${entry['before_value']}\nAfter: ${entry['after_value']}',
                ),
                isThreeLine: true,
              ),
          ],
        );
      },
    ),
  );
}
