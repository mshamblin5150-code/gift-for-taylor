import 'package:flutter/material.dart';
import 'package:schedule_rules/schedule_rules.dart';

/// The Manager gives the Night scheduler role to Staff members, chooses the
/// Sections each may edit, and takes the role back.
class NightSchedulerPage extends StatefulWidget {
  const NightSchedulerPage({
    super.key,
    required this.rules,
    required this.month,
  });

  final ScheduleRules rules;

  /// The month whose Staff list rows offer who can take the role.
  final DateTime month;

  @override
  State<NightSchedulerPage> createState() => _NightSchedulerPageState();
}

class _NightSchedulerPageState extends State<NightSchedulerPage> {
  MonthGrid? _grid;
  List<NightScheduler> _schedulers = const [];
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (grid, schedulers) = await (
        widget.rules.monthGrid(widget.month),
        widget.rules.nightSchedulers(),
      ).wait;
      if (!mounted) return;
      setState(() {
        _grid = grid;
        _schedulers = schedulers;
        _loadError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  Future<void> _assign(MonthGrid grid, [NightScheduler? current]) async {
    final assignment = await showDialog<NightScheduler>(
      context: context,
      builder: (context) => _AssignDialog(
        grid: grid,
        current: current,
        taken: {for (final scheduler in _schedulers) scheduler.staffMemberId},
      ),
    );
    if (assignment == null) return;
    await _run(
      () => widget.rules.assignNightScheduler(
        assignment.staffMemberId,
        assignment.sectionIds,
      ),
      "The Night scheduler wasn't saved. Try again.",
    );
  }

  Future<void> _remove(NightScheduler scheduler) async {
    await _run(
      () => widget.rules.removeNightScheduler(scheduler.staffMemberId),
      "The Night scheduler role wasn't removed. Try again.",
    );
  }

  Future<void> _run(Future<void> Function() action, String failure) async {
    try {
      await action();
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final grid = _grid;
    return Scaffold(
      appBar: AppBar(title: const Text('Night scheduler')),
      floatingActionButton: grid == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _assign(grid),
              icon: const Icon(Icons.nightlight_outlined),
              label: const Text('Give the role'),
            ),
      body: switch ((grid, _loadError)) {
        (_, Object()) => const Center(
          child: Text("The Night scheduler couldn't be loaded."),
        ),
        (null, _) => const Center(child: CircularProgressIndicator()),
        (MonthGrid(), _) when _schedulers.isEmpty => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No one has the Night scheduler role. '
              'Give it to a Staff member to let them edit chosen Sections.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        (final MonthGrid grid, _) => ListView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
          children: [
            for (final scheduler in _schedulers)
              ListTile(
                title: Text(_nameOf(grid, scheduler.staffMemberId)),
                subtitle: Text(
                  [
                    for (final section in grid.sections)
                      if (scheduler.sectionIds.contains(section.id))
                        section.name,
                  ].join(', '),
                ),
                onTap: () => _assign(grid, scheduler),
                trailing: IconButton(
                  tooltip:
                      'Remove the role from '
                      '${_nameOf(grid, scheduler.staffMemberId)}',
                  onPressed: () => _remove(scheduler),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ),
          ],
        ),
      },
    );
  }
}

String _nameOf(MonthGrid grid, String staffMemberId) =>
    grid.rows
        .where((row) => row.staffMemberId == staffMemberId)
        .firstOrNull
        ?.displayName ??
    'Former Staff member';

class _AssignDialog extends StatefulWidget {
  const _AssignDialog({
    required this.grid,
    required this.current,
    required this.taken,
  });

  final MonthGrid grid;
  final NightScheduler? current;

  /// Staff members who already have the role.
  final Set<String> taken;

  @override
  State<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends State<_AssignDialog> {
  late String? _staffMemberId = widget.current?.staffMemberId;
  late final Set<String> _sectionIds = {...?widget.current?.sectionIds};

  @override
  Widget build(BuildContext context) {
    final current = widget.current;
    final candidates = [
      for (final row in widget.grid.rows)
        if (!widget.taken.contains(row.staffMemberId) ||
            row.staffMemberId == current?.staffMemberId)
          row,
    ];
    return AlertDialog(
      title: Text(
        current == null
            ? 'Give the Night scheduler role'
            : _nameOf(widget.grid, current.staffMemberId),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (current == null)
              DropdownButtonFormField<String>(
                initialValue: _staffMemberId,
                decoration: const InputDecoration(labelText: 'Staff member'),
                items: [
                  for (final row in candidates)
                    DropdownMenuItem(
                      value: row.staffMemberId,
                      child: Text(row.displayName),
                    ),
                ],
                onChanged: (value) => setState(() => _staffMemberId = value),
              ),
            const Padding(
              padding: EdgeInsets.only(top: 16, bottom: 4),
              child: Text('Sections they may edit'),
            ),
            for (final section in widget.grid.sections)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(section.name),
                value: _sectionIds.contains(section.id),
                onChanged: (checked) => setState(
                  () => checked == true
                      ? _sectionIds.add(section.id)
                      : _sectionIds.remove(section.id),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _staffMemberId == null || _sectionIds.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  NightScheduler(
                    staffMemberId: _staffMemberId!,
                    sectionIds: {..._sectionIds},
                  ),
                ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
