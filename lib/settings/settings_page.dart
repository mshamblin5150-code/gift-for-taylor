import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../notifications/notice_gateway.dart';
import '../notifications/notices_page.dart';
import '../schedule/print_wording_dialog.dart';
import '../schedule/print_wording_gateway.dart';
import '../schedule/shift_codes_page.dart';
import 'appearance.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.scheduleRules,
    this.openShiftRules,
    this.noticeGateway,
    this.printWordingGateway,
    this.onCalendarFeed,
    this.onManageStaff,
    this.role = 'staff_member',
    this.auditClient,
  });

  final ScheduleRules scheduleRules;
  final OpenShiftRules? openShiftRules;
  final NoticeGateway? noticeGateway;
  final PrintWordingGateway? printWordingGateway;
  final VoidCallback? onCalendarFeed;
  final Future<void> Function()? onManageStaff;
  final String role;
  final SupabaseClient? auditClient;

  bool get _canManageUnit => role == 'manager' || role == 'administrator';

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
          if (onCalendarFeed != null)
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('My calendar'),
              subtitle: const Text('Choose calendar invitations or a feed'),
              onTap: onCalendarFeed,
            ),
          if (noticeGateway != null)
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Notifications'),
              subtitle: const Text('Allow notices on this device'),
              onTap: () => open(NoticesPage(gateway: noticeGateway!)),
            ),
          if (_canManageUnit) ...[
            const _SectionHeading('Unit'),
            if (openShiftRules != null) ...[
              ListTile(
                leading: const Icon(Icons.people_outline),
                title: const Text('Staffing minimums'),
                subtitle: const Text('Standing weekday minimums and RN floors'),
                onTap: () => open(WeekdayMinimumsPage(rules: openShiftRules!)),
              ),
              ListTile(
                leading: const Icon(Icons.fact_check_outlined),
                title: const Text('Open shift pickup approval'),
                subtitle: const Text('Default for newly posted shifts'),
                onTap: () => open(ApprovalDefaultPage(rules: openShiftRules!)),
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
  final OpenShiftRules rules;
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

class WeekdayMinimumsPage extends StatefulWidget {
  const WeekdayMinimumsPage({super.key, required this.rules});
  final OpenShiftRules rules;
  @override
  State<WeekdayMinimumsPage> createState() => _WeekdayMinimumsPageState();
}

class _WeekdayMinimumsPageState extends State<WeekdayMinimumsPage> {
  late Future<List<SectionStaffing>> _staffing = widget.rules.staffingForMonth(
    DateTime.now(),
  );

  Future<void> _edit(SectionStaffing item) async {
    final minimum = TextEditingController(
      text: item.weekdayMinimum?.toString() ?? '',
    );
    final floor = TextEditingController(text: (item.rnFloor ?? 0).toString());
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '${item.pool.label} · ${item.coverageWindow.label} · ${DateFormat.EEEE().format(item.date)}',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: minimum,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Minimum people'),
            ),
            if (item.pool == RolePool.nurses)
              TextField(
                controller: floor,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'RN floor'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (save == true) {
      final count = int.tryParse(minimum.text);
      final rnFloor = item.pool == RolePool.nurses
          ? int.tryParse(floor.text)
          : 0;
      if (count == null ||
          count < 0 ||
          count > 100 ||
          rnFloor == null ||
          rnFloor < 0 ||
          rnFloor > count) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Enter a minimum from 0 to 100 and an RN floor no higher than it.',
              ),
            ),
          );
        }
      } else {
        try {
          await widget.rules.setWeekdayMinimum(
            item.pool,
            item.coverageWindow,
            item.date.weekday % 7,
            count,
            rnFloor,
          );
          if (mounted) {
            setState(
              () => _staffing = widget.rules.staffingForMonth(DateTime.now()),
            );
          }
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('The staffing minimum was not saved.'),
              ),
            );
          }
        }
      }
    }
    minimum.dispose();
    floor.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Standing staffing minimums')),
    body: FutureBuilder<List<SectionStaffing>>(
      future: _staffing,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load staffing minimums.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final byWeekday = <String, SectionStaffing>{};
        for (final item in snapshot.data!) {
          final key =
              '${item.pool.name}:${item.coverageWindow.name}:${item.date.weekday}';
          final previous = byWeekday[key];
          if (previous == null ||
              (previous.dateMinimum != null && item.dateMinimum == null)) {
            byWeekday[key] = item;
          }
        }
        final items = byWeekday.values.toList();
        return ListView(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('One-date overrides stay on the Day staffing sheet.'),
            ),
            for (final item in items)
              ListTile(
                title: Text(
                  '${item.pool.label} · ${item.coverageWindow.label} · ${DateFormat.EEEE().format(item.date)}',
                ),
                subtitle: Text(
                  'Minimum ${item.weekdayMinimum?.toString() ?? 'not set'}${item.pool == RolePool.nurses ? ' · RN floor ${item.rnFloor ?? 0}' : ''}',
                ),
                onTap: () => _edit(item),
              ),
          ],
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
          .select('kind, actor_name, changed_at, before_value, after_value')
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
                  '${entry['actor_name']} · ${entry['changed_at']}\nBefore: ${entry['before_value']}\nAfter: ${entry['after_value']}',
                ),
                isThreeLine: true,
              ),
          ],
        );
      },
    ),
  );
}
