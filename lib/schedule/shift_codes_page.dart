import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:schedule_rules/schedule_rules.dart';

/// The Shift code catalog. The Manager may edit it; Staff members may read it.
/// A used code can change meaning or hours; renaming keeps its historical
/// definition for existing cells, and deletion is refused.
class ShiftCodesPage extends StatefulWidget {
  const ShiftCodesPage({super.key, required this.rules, this.readOnly = false});

  final ScheduleRules rules;
  final bool readOnly;

  @override
  State<ShiftCodesPage> createState() => _ShiftCodesPageState();
}

class _ShiftCodesPageState extends State<ShiftCodesPage> {
  static final _validTime = RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$');
  late Future<List<LegendCode>> _codes = widget.rules.shiftCodes();

  void _reload() => setState(() {
    _codes = widget.rules.shiftCodes();
  });

  Future<void> _pickTime(
    BuildContext context,
    TextEditingController controller,
  ) async {
    final value = controller.text.trim();
    final initialTime = _validTime.hasMatch(value)
        ? TimeOfDay(
            hour: int.parse(value.substring(0, 2)),
            minute: int.parse(value.substring(3, 5)),
          )
        : TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    controller.text =
        '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _edit([LegendCode? original]) async {
    final code = TextEditingController(text: original?.code);
    final meaning = TextEditingController(text: original?.meaning);
    final start = TextEditingController(text: original?.startTime);
    final end = TextEditingController(text: original?.endTime);
    var working = original?.isWorking ?? true;
    var coverageSelection = original?.coverageWindow ?? 'auto';
    String? lengthError;
    final route = DialogRoute<LegendCode>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(original == null ? 'Add Shift code' : 'Edit Shift code'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: code,
                  maxLength: shiftCodeLimit,
                  maxLengthEnforcement: MaxLengthEnforcement.none,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Code'),
                  onChanged: (_) => update(() => lengthError = null),
                ),
                TextField(
                  controller: meaning,
                  maxLength: shiftMeaningLimit,
                  maxLengthEnforcement: MaxLengthEnforcement.none,
                  decoration: const InputDecoration(
                    labelText: 'Meaning (optional)',
                  ),
                  onChanged: (_) => update(() => lengthError = null),
                ),
                if (lengthError != null)
                  Text(
                    lengthError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                TextField(
                  controller: start,
                  decoration: InputDecoration(
                    labelText: 'Starts (HH:mm, optional)',
                    suffixIcon: IconButton(
                      tooltip: 'Pick Starts time',
                      icon: const Icon(Icons.access_time),
                      onPressed: () => _pickTime(context, start),
                    ),
                  ),
                ),
                TextField(
                  controller: end,
                  decoration: InputDecoration(
                    labelText: 'Ends (HH:mm, optional)',
                    suffixIcon: IconButton(
                      tooltip: 'Pick Ends time',
                      icon: const Icon(Icons.access_time),
                      onPressed: () => _pickTime(context, end),
                    ),
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: coverageSelection,
                  decoration: const InputDecoration(
                    labelText: 'Coverage window',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('From hours')),
                    DropdownMenuItem(value: 'day', child: Text('Day')),
                    DropdownMenuItem(value: 'night', child: Text('Night')),
                  ],
                  onChanged: (value) =>
                      update(() => coverageSelection = value ?? 'auto'),
                ),
                SwitchListTile(
                  title: const Text('Worked shift'),
                  value: working,
                  onChanged: (value) => update(() => working = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = code.text.trim().toUpperCase();
                if (name.runes.length > shiftCodeLimit ||
                    meaning.text.trim().runes.length > shiftMeaningLimit) {
                  update(
                    () => lengthError =
                        'Use at most $shiftCodeLimit characters for the code and '
                        '$shiftMeaningLimit for its meaning.',
                  );
                  return;
                }
                final first = start.text.trim();
                final last = end.text.trim();
                if (name.isEmpty ||
                    (first.isEmpty != last.isEmpty) ||
                    (first.isNotEmpty &&
                        (!_validTime.hasMatch(first) ||
                            !_validTime.hasMatch(last)))) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Enter a code and both hours as HH:mm, or leave both blank.',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(
                  context,
                  LegendCode(
                    name,
                    meaning: meaning.text.trim(),
                    startTime: first.isEmpty ? null : first,
                    endTime: last.isEmpty ? null : last,
                    isWorking: working,
                    coverageWindow: first.isEmpty || coverageSelection == 'auto'
                        ? null
                        : coverageSelection,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final result = await Navigator.of(context).push(route);
    await route.completed;
    code.dispose();
    meaning.dispose();
    start.dispose();
    end.dispose();
    if (result == null) return;
    try {
      await widget.rules.saveShiftCode(result, originalCode: original?.code);
      _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _delete(LegendCode code) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${code.code}?'),
        content: const Text('Codes used on the Schedule cannot be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.rules.deleteShiftCode(code.code);
      _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Shift codes')),
    floatingActionButton: widget.readOnly
        ? null
        : FloatingActionButton.extended(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('Add code'),
          ),
    body: FutureBuilder<List<LegendCode>>(
      future: _codes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Could not load Shift codes: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          children: [
            if (!widget.readOnly &&
                snapshot.data!.any(
                  (code) =>
                      code.isWorking &&
                      code.startTime == null &&
                      code.endTime == null,
                ))
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Working Shift codes without times appear as all-day calendar events. Tap a code to set its hours or mark it not worked.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            for (final code in snapshot.data!)
              ListTile(
                title: Text(code.code),
                subtitle: Text(
                  [
                    if (code.hours != null) code.hours!,
                    if (code.isWorking &&
                        code.startTime == null &&
                        code.endTime == null)
                      'Time not set',
                    if (code.meaning?.isNotEmpty == true) code.meaning!,
                    if (code.coverageWindow != null)
                      code.coverageWindow == 'day' ? 'Day' : 'Night',
                    if (code.isWorking && code.coverageWindow == null)
                      'No Coverage window',
                    code.isWorking ? 'Worked shift' : 'Not worked',
                  ].join(' · '),
                ),
                onTap: widget.readOnly ? null : () => _edit(code),
                trailing: widget.readOnly
                    ? null
                    : IconButton(
                        tooltip: 'Delete ${code.code}',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(code),
                      ),
              ),
          ],
        );
      },
    ),
  );
}
