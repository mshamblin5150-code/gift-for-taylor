import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

Future<bool?> showStaffingSheet(
  BuildContext context, {
  required OpenShiftRules rules,
  required ScheduleSection section,
  required DateTime date,
  required SectionStaffing staffing,
}) async {
  final minimum = TextEditingController(text: '${staffing.minimum}');
  final code = TextEditingController();
  var role = JobRole.rn;
  var saving = false;
  String? error;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        Future<void> run(Future<void> Function() action) async {
          setState(() {
            saving = true;
            error = null;
          });
          try {
            await action();
            if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
          } catch (failure) {
            setState(() => error = failure.toString());
          } finally {
            if (dialogContext.mounted) setState(() => saving = false);
          }
        }

        int parseMinimum() {
          final value = int.tryParse(minimum.text.trim());
          if (value == null || value < 0 || value > 100) {
            throw const FormatException('Enter a minimum from 0 to 100.');
          }
          return value;
        }

        return AlertDialog(
          title: Text('${section.name} • ${DateFormat.MMMd().format(date)}'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${staffing.workingCount} working • minimum ${staffing.minimum} • ${staffing.openCount} Open',
                  ),
                  if (staffing.shortCount > 0)
                    Text(
                      'Short ${staffing.shortCount}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: minimum,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Minimum people',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: saving
                            ? null
                            : () => run(
                                () => rules.setWeekdayMinimum(
                                  section.id,
                                  date.weekday % 7,
                                  parseMinimum(),
                                ),
                              ),
                        child: Text(
                          'Save every ${DateFormat.EEEE().format(date)}',
                        ),
                      ),
                      OutlinedButton(
                        onPressed: saving
                            ? null
                            : () => run(
                                () => rules.setDateMinimum(
                                  section.id,
                                  date,
                                  parseMinimum(),
                                ),
                              ),
                        child: const Text('Save this date'),
                      ),
                      if (staffing.dateMinimum != null)
                        TextButton(
                          onPressed: saving
                              ? null
                              : () => run(
                                  () => rules.setDateMinimum(
                                    section.id,
                                    date,
                                    null,
                                  ),
                                ),
                          child: const Text('Remove date override'),
                        ),
                    ],
                  ),
                  const Divider(height: 32),
                  TextField(
                    controller: code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Open shift Shift code',
                    ),
                  ),
                  DropdownButtonFormField<JobRole>(
                    initialValue: role,
                    decoration: const InputDecoration(labelText: 'Pickup role'),
                    items: [
                      for (final choice in JobRole.values)
                        DropdownMenuItem(
                          value: choice,
                          child: Text(choice.label),
                        ),
                    ],
                    onChanged: saving
                        ? null
                        : (value) {
                            if (value != null) setState(() => role = value);
                          },
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: saving
                            ? null
                            : () => run(() async {
                                await rules.postOpenShifts(
                                  section.id,
                                  date,
                                  code.text,
                                  role,
                                  1,
                                );
                              }),
                        child: const Text('Post one'),
                      ),
                      if (staffing.unpostedCount > 0)
                        FilledButton(
                          onPressed: saving
                              ? null
                              : () => run(() async {
                                  await rules.postOpenShifts(
                                    section.id,
                                    date,
                                    code.text,
                                    role,
                                    staffing.unpostedCount,
                                    fillGap: true,
                                  );
                                }),
                          child: Text('Post ${staffing.unpostedCount} for gap'),
                        ),
                    ],
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving
                  ? null
                  : () => Navigator.of(dialogContext).pop(false),
              child: const Text('Close'),
            ),
          ],
        );
      },
    ),
  );
  minimum.dispose();
  code.dispose();
  return result;
}
