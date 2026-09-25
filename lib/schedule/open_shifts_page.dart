import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

typedef _OpenShiftsData = ({
  MonthGrid grid,
  List<OpenShift> shifts,
  List<OpenShiftPickup> pickups,
  int hiddenCount,
});

class OpenShiftsPage extends StatefulWidget {
  const OpenShiftsPage({
    super.key,
    required this.rules,
    required this.scheduleRules,
    required this.month,
    required this.staffMemberId,
    required this.isManager,
    this.onApprovalSettings,
  });
  final OpenShiftStore rules;
  final ScheduleRules scheduleRules;
  final DateTime month;
  final String? staffMemberId;
  final bool isManager;
  final VoidCallback? onApprovalSettings;

  @override
  State<OpenShiftsPage> createState() => _OpenShiftsPageState();
}

class _OpenShiftsPageState extends State<OpenShiftsPage> {
  late Future<_OpenShiftsData> _data = _load();
  StreamSubscription<void>? _updates;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _updates = widget.rules.updates().listen((_) => _refresh());
  }

  @override
  void dispose() {
    _updates?.cancel();
    super.dispose();
  }

  Future<_OpenShiftsData> _load() async => (
    grid: await widget.scheduleRules.monthGrid(widget.month),
    shifts: await widget.rules.openShifts(),
    pickups: await widget.rules.pickups(),
    hiddenCount: await widget.rules.hiddenOpenShiftCount(widget.month),
  );

  void _refresh() => setState(() => _data = _load());

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Open shifts'),
      actions: [
        if (widget.isManager && widget.onApprovalSettings != null)
          IconButton(
            tooltip: 'Open shift approval default',
            onPressed: widget.onApprovalSettings,
            icon: const Icon(Icons.tune),
          ),
        IconButton(
          tooltip: 'Refresh Open shifts',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<_OpenShiftsData>(
      future: _data,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(
            child: snapshot.hasError
                ? Text(snapshot.error.toString())
                : const CircularProgressIndicator(),
          );
        }
        final (:grid, :shifts, :pickups, :hiddenCount) = snapshot.data!;
        final monthShifts = shifts
            .where(
              (shift) =>
                  shift.date.year == widget.month.year &&
                  shift.date.month == widget.month.month,
            )
            .toList();
        return ListView(
          children: [
            if (monthShifts.isEmpty)
              const ListTile(title: Text('No Open shifts this month.')),
            if (!widget.isManager && hiddenCount > 0)
              ListTile(
                title: Text(
                  hiddenCount == 1
                      ? "1 more Open shift isn't available to you."
                      : "$hiddenCount more Open shifts aren't available to you.",
                ),
              ),
            for (final shift in monthShifts)
              Card(
                child: ListTile(
                  title: Text(
                    '${DateFormat.MMMd().format(shift.date)} — ${shift.shiftCode}',
                  ),
                  subtitle: Text(
                    shift.originalStaffMemberId == null
                        ? '${shift.jobRole.label} • Posted by Manager • ${shift.requiresApproval ? 'Approval required' : 'Immediate pickup'}'
                        : '${shift.jobRole.label} • ${grid.displayNameOf(shift.originalStaffMemberId!)} • ${shift.requiresApproval ? 'Approval required' : 'Immediate pickup'}',
                  ),
                  trailing: widget.isManager
                      ? Switch(
                          value: shift.requiresApproval,
                          onChanged: _busy
                              ? null
                              : (value) => _run(
                                  () => widget.rules.setShiftApproval(
                                    shift.id,
                                    value,
                                  ),
                                ),
                        )
                      : widget.staffMemberId == null || _busy
                      ? null
                      : pickups.any(
                          (pickup) =>
                              pickup.openShiftId == shift.id &&
                              pickup.staffMemberId == widget.staffMemberId,
                        )
                      ? const Text('Requested')
                      : FilledButton(
                          onPressed: () =>
                              _run(() => widget.rules.requestPickup(shift.id)),
                          child: const Text('Pick up'),
                        ),
                ),
              ),
            if (widget.isManager) ...[
              const ListTile(title: Text('Pickup approvals')),
              for (final pickup in pickups.where(
                (p) => p.status == PickupStatus.pending,
              ))
                if (monthShifts
                        .where((shift) => shift.id == pickup.openShiftId)
                        .firstOrNull
                    case final shift?)
                  Card(
                    child: ListTile(
                      title: Text(grid.displayNameOf(pickup.staffMemberId)),
                      subtitle: Text(
                        '${DateFormat.MMMd().format(shift.date)} — ${shift.shiftCode}',
                      ),
                      trailing: _busy
                          ? null
                          : FilledButton(
                              onPressed: () => _run(
                                () => widget.rules.approvePickup(pickup.id),
                              ),
                              child: const Text('Approve'),
                            ),
                    ),
                  ),
            ],
          ],
        );
      },
    ),
  );
}
