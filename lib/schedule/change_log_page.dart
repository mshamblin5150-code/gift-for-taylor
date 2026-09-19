import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

/// The Manager's view of who changed which cell in a month, and when.
class ChangeLogPage extends StatefulWidget {
  const ChangeLogPage({super.key, required this.rules, required this.month});

  final ScheduleRules rules;
  final DateTime month;

  @override
  State<ChangeLogPage> createState() => _ChangeLogPageState();
}

class _ChangeLogPageState extends State<ChangeLogPage> {
  MonthGrid? _grid;

  /// Everyone who changed a cell this month, by id, for the person filter.
  Map<String, String> _changers = const {};
  List<ScheduleChange>? _entries;
  Object? _loadError;
  String? _changedBy;
  DateTime? _changedOn;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (grid, everything, entries) = await (
        widget.rules.monthGrid(widget.month),
        widget.rules.changeLogView(widget.month),
        widget.rules.changeLogView(
          widget.month,
          changedBy: _changedBy,
          changedOn: _changedOn,
        ),
      ).wait;
      if (!mounted) return;
      setState(() {
        _grid = grid;
        _changers = {
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

  void _filter({required String? changedBy, required DateTime? changedOn}) {
    setState(() {
      _changedBy = changedBy;
      _changedOn = changedOn;
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
    final grid = _grid;
    final entries = _entries;
    return Scaffold(
      appBar: AppBar(
        title: Text('Change log · ${DateFormat.yMMMM().format(widget.month)}'),
      ),
      body: switch ((grid, entries, _loadError)) {
        (_, _, Object()) => const Center(
          child: Text("The change log couldn't be loaded."),
        ),
        (final MonthGrid grid, final List<ScheduleChange> entries, _) => Column(
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
                          _ChangeTile(grid: grid, change: change),
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
              for (final MapEntry(:key, :value) in _changers.entries)
                DropdownMenuItem(value: key, child: Text(value)),
            ],
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
  const _ChangeTile({required this.grid, required this.change});

  final MonthGrid grid;
  final ScheduleChange change;

  @override
  Widget build(BuildContext context) {
    final person =
        grid.rows
            .where((row) => row.staffMemberId == change.staffMemberId)
            .firstOrNull
            ?.displayName ??
        'Former Staff member';
    final oldCode = change.oldShiftCode.isEmpty ? 'blank' : change.oldShiftCode;
    final newCode = change.newShiftCode.isEmpty ? 'blank' : change.newShiftCode;
    return ListTile(
      title: Text(
        '$person · ${DateFormat('EEE d').format(change.date)}: '
        '$oldCode → $newCode',
      ),
      subtitle: Text(
        '${change.changedByName} · '
        '${DateFormat.MMMd().add_jm().format(change.changedAt)}',
      ),
    );
  }
}
