import 'package:flutter/material.dart';
import 'package:schedule_rules/schedule_rules.dart';

/// The Manager's catalog. A used code can change meaning or hours; renaming
/// keeps its historical definition for existing cells, and deletion is refused.
class ShiftCodesPage extends StatefulWidget {
  const ShiftCodesPage({super.key, required this.rules});

  final ScheduleRules rules;

  @override
  State<ShiftCodesPage> createState() => _ShiftCodesPageState();
}

class _ShiftCodesPageState extends State<ShiftCodesPage> {
  late Future<List<LegendCode>> _codes = widget.rules.shiftCodes();

  void _reload() => setState(() => _codes = widget.rules.shiftCodes());

  Future<void> _edit([LegendCode? original]) async {
    final code = TextEditingController(text: original?.code);
    final meaning = TextEditingController(text: original?.meaning);
    final start = TextEditingController(text: original?.startTime);
    final end = TextEditingController(text: original?.endTime);
    var working = original?.isWorking ?? true;
    final result = await showDialog<LegendCode>(
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
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Code'),
                ),
                TextField(
                  controller: meaning,
                  decoration: const InputDecoration(
                    labelText: 'Meaning (optional)',
                  ),
                ),
                TextField(
                  controller: start,
                  decoration: const InputDecoration(
                    labelText: 'Starts (HH:mm, optional)',
                  ),
                ),
                TextField(
                  controller: end,
                  decoration: const InputDecoration(
                    labelText: 'Ends (HH:mm, optional)',
                  ),
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
                final first = start.text.trim();
                final last = end.text.trim();
                final validTime = RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$');
                if (name.isEmpty ||
                    (first.isEmpty != last.isEmpty) ||
                    (first.isNotEmpty &&
                        (!validTime.hasMatch(first) ||
                            !validTime.hasMatch(last)))) {
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
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    // Controllers outlive the dialog transition; dispose after its route exits.
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
    floatingActionButton: FloatingActionButton.extended(
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
            if (snapshot.data!.any((code) =>
                code.isWorking && code.startTime == null && code.endTime == null))
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
                    if (code.isWorking && code.startTime == null && code.endTime == null)
                      'Time not set',
                    if (code.meaning?.isNotEmpty == true) code.meaning!,
                    code.isWorking ? 'Worked shift' : 'Not worked',
                  ].join(' · '),
                ),
                onTap: () => _edit(code),
                trailing: IconButton(
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
