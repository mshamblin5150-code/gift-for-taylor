import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

/// The Manager's view of who changed which cell in a month, and when.
class ChangeLogPage extends StatefulWidget {
  const ChangeLogPage({
    super.key,
    required this.rules,
    required this.month,
    this.unreachedOnly = false,
    this.weekStart,
  });

  final ScheduleRules rules;
  final DateTime month;
  final bool unreachedOnly;
  final DateTime? weekStart;

  @override
  State<ChangeLogPage> createState() => _ChangeLogPageState();
}

class _ChangeLogPageState extends State<ChangeLogPage> {
  Map<String, String>? _names;

  /// Everyone who changed a cell this month, by id, for the person filter.
  Map<String, String> _peopleWhoChanged = const {};
  List<ScheduleChange>? _entries;
  Object? _loadError;
  String? _changedBy;
  DateTime? _changedOn;
  late bool _unreachedOnly = widget.unreachedOnly;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final weekStart = widget.weekStart;
      final weekEnd = weekStart?.add(Duration(days: 7 - weekStart.weekday));
      final lastMonth = weekEnd == null
          ? widget.month
          : DateTime(weekEnd.year, weekEnd.month);
      final months = [widget.month, if (lastMonth != widget.month) lastMonth];
      final (grids, allLogs, filteredLogs) = await (
        Future.wait(months.map(widget.rules.monthGrid)),
        Future.wait(months.map(widget.rules.changeLogView)),
        Future.wait(
          months.map(
            (month) => widget.rules.changeLogView(
              month,
              changedBy: _changedBy,
              changedOn: _changedOn,
              unreachedOnly: _unreachedOnly,
            ),
          ),
        ),
      ).wait;
      if (!mounted) return;
      bool inWeek(ScheduleChange change) {
        if (weekStart == null || weekEnd == null) return true;
        final date = DateTime(
          change.date.year,
          change.date.month,
          change.date.day,
        );
        return !date.isBefore(weekStart) && !date.isAfter(weekEnd);
      }

      final everything = allLogs.expand((log) => log).where(inWeek).toList();
      final entries = filteredLogs.expand((log) => log).where(inWeek).toList()
        ..sort((a, b) => b.changedAt.compareTo(a.changedAt));
      setState(() {
        _names = {
          for (final grid in grids)
            for (final row in grid.rows) row.staffMemberId: row.displayName,
        };
        _peopleWhoChanged = {
          for (final change in everything.reversed)
            change.changedBy: change.changedByName,
        };
        _entries = entries;
        _loadError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  void _filter({
    required String? changedBy,
    required DateTime? changedOn,
    bool? unreachedOnly,
  }) {
    setState(() {
      _changedBy = changedBy;
      _changedOn = changedOn;
      _unreachedOnly = unreachedOnly ?? _unreachedOnly;
    });
    _load();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _changedOn ?? now,
      firstDate: DateTime(widget.month.year - 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Changes made on',
    );
    if (picked != null) _filter(changedBy: _changedBy, changedOn: picked);
  }

  @override
  Widget build(BuildContext context) {
    final names = _names;
    final entries = _entries;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.weekStart == null
              ? 'Change log · ${DateFormat.yMMMM().format(widget.month)}'
              : 'Change log · this week',
        ),
      ),
      body: switch ((names, entries, _loadError)) {
        (_, _, Object()) => const Center(
          child: Text("The change log couldn't be loaded."),
        ),
        (
          final Map<String, String> names,
          final List<ScheduleChange> entries,
          _,
        ) =>
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _filters(),
              const Divider(height: 1),
              Expanded(
                child: entries.isEmpty
                    ? const Center(child: Text('No changes match.'))
                    : ListView(
                        children: [
                          for (final change in entries)
                            _ChangeTile(
                              personName: names[change.staffMemberId] ?? '',
                              change: change,
                            ),
                        ],
                      ),
              ),
            ],
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _filters() {
    final changedOn = _changedOn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<String?>(
            value: _changedBy,
            hint: const Text('Everyone'),
            onChanged: (id) => _filter(changedBy: id, changedOn: _changedOn),
            items: [
              const DropdownMenuItem(value: null, child: Text('Everyone')),
              for (final MapEntry(:key, :value) in _peopleWhoChanged.entries)
                DropdownMenuItem(value: key, child: Text(value)),
            ],
          ),
          FilterChip(
            label: const Text('Unreached'),
            selected: _unreachedOnly,
            onSelected: (selected) => _filter(
              changedBy: _changedBy,
              changedOn: _changedOn,
              unreachedOnly: selected,
            ),
          ),
          if (changedOn == null)
            ActionChip(
              avatar: const Icon(Icons.calendar_month, size: 18),
              label: const Text('Any day'),
              onPressed: _pickDate,
            )
          else
            InputChip(
              avatar: const Icon(Icons.calendar_month, size: 18),
              label: Text('Made ${DateFormat.MMMd().format(changedOn)}'),
              onPressed: _pickDate,
              onDeleted: () => _filter(changedBy: _changedBy, changedOn: null),
              deleteButtonTooltipMessage: 'Any day',
            ),
        ],
      ),
    );
  }
}

class _ChangeTile extends StatelessWidget {
  const _ChangeTile({required this.personName, required this.change});

  final String personName;
  final ScheduleChange change;

  @override
  Widget build(BuildContext context) {
    final oldCode = change.oldShiftCode.isEmpty ? 'blank' : change.oldShiftCode;
    final newCode = change.newShiftCode.isEmpty ? 'blank' : change.newShiftCode;
    return ListTile(
      title: Text(
        '$personName · ${DateFormat('EEE d').format(change.date)}: '
        '$oldCode → $newCode',
      ),
      subtitle: Text(
        '${change.changedByName} · '
        '${DateFormat.MMMd().add_jm().format(change.changedAt)}\n'
        'Reach: ${switch ((change.moot, change.reach)) {
          (true, _) => 'Nothing to tell',
          (_, 'notified') => 'Notified',
          (_, 'draft_opened') => 'Text draft opened',
          (_, 'nobody') => 'Nobody',
          _ => 'Not yet announced',
        }}',
      ),
      isThreeLine: true,
    );
  }
}
