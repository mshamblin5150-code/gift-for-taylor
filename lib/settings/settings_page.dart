import 'package:flutter/material.dart';
import 'package:schedule_rules/schedule_rules.dart';

import '../app_dependencies.dart';
import '../schedule/print_wording_dialog.dart';
import '../schedule/print_wording_gateway.dart';
import '../schedule/pending_work.dart';
import '../schedule/schedule_destinations.dart';
import 'appearance.dart';
import 'settings_history.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.dependencies,
    required this.access,
    this.month,
    this.pending = const PendingWorkState(),
    this.destinationCallbacks = const ScheduleDestinationCallbacks(),
  });

  final AppDependencies dependencies;
  final Access access;
  final DateTime? month;
  final PendingWorkState pending;
  final ScheduleDestinationCallbacks destinationCallbacks;

  @override
  Widget build(BuildContext context) {
    final shownMonth =
        month ?? DateTime(DateTime.now().year, DateTime.now().month);
    final destinations = scheduleDestinations(
      dependencies: dependencies,
      access: access,
      pending: pending,
      callbacks: destinationCallbacks,
    );
    final locked = lockedSettingsDestinations(
      dependencies: dependencies,
      access: access,
      pending: pending,
      callbacks: destinationCallbacks,
    );
    final repair = destinations
        .where((entry) => entry.id == ScheduleDestinationId.maintainerRepairs)
        .firstOrNull;

    Future<void> open(ScheduleDestination destination) async {
      final result = await Navigator.push<Object?>(
        context,
        MaterialPageRoute<Object?>(
          builder: (routeContext) =>
              destination.pageBuilder(routeContext, shownMonth),
        ),
      );
      if (!context.mounted) return;
      if (destination.reloadMonth) {
        await destinationCallbacks.onReloadMonth?.call();
      }
      if (result == true &&
          destination.resultAction ==
              DestinationResultAction.managerTransferred &&
          context.mounted) {
        Navigator.pop(context);
        destinationCallbacks.onManagerTransferred?.call();
      }
    }

    ListTile tile(ScheduleDestination destination) => ListTile(
      leading: Icon(destination.icon),
      title: Text(destination.label),
      subtitle: destination.subtitle == null
          ? null
          : Text(destination.subtitle!),
      onTap: () => open(destination),
    );

    ListTile repairRequired(ScheduleDestination destination) => ListTile(
      leading: Icon(destination.icon),
      title: Text(destination.label),
      subtitle: const Text('Requires a Repair — tap to break the glass'),
      trailing: const Icon(Icons.lock_outline),
      onTap: repair == null ? null : () => open(repair),
    );

    final personal =
        destinations
            .where((entry) => entry.settings == DestinationSettings.personal)
            .toList()
          ..sort(
            (first, second) =>
                first.settingsOrder.compareTo(second.settingsOrder),
          );
    final transfer = destinations.where(
      (entry) => entry.settings == DestinationSettings.transfer,
    );
    final unit = destinations.where(
      (entry) => entry.settings == DestinationSettings.unit,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeading('Personal'),
          const AppearanceTile(),
          for (final destination in personal) tile(destination),
          if (locked.isNotEmpty) ...[
            const _SectionHeading('Manager controls'),
            for (final destination in locked) repairRequired(destination),
          ],
          for (final destination in transfer) tile(destination),
          if (unit.isNotEmpty) ...[
            const _SectionHeading('Unit'),
            for (final destination in unit) tile(destination),
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

class PrintWordingPage extends StatefulWidget {
  const PrintWordingPage({super.key, required this.gateway});
  final PrintWordingGateway gateway;
  @override
  State<PrintWordingPage> createState() => _PrintWordingPageState();
}

class _PrintWordingPageState extends State<PrintWordingPage> {
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

class SettingsHistoryPage extends StatefulWidget {
  const SettingsHistoryPage({super.key, required this.history});
  final SettingsHistory history;

  @override
  State<SettingsHistoryPage> createState() => _SettingsHistoryPageState();
}

class _SettingsHistoryPageState extends State<SettingsHistoryPage> {
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
