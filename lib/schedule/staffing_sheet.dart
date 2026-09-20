import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

Future<bool?> showStaffingSheet(
  BuildContext context, {
  required OpenShiftRules rules,
  required DateTime date,
  required SectionStaffing staffing,
}) async {
  final minimum = TextEditingController(text: staffing.minimum?.toString() ?? '');
  final rnFloor = TextEditingController(text: (staffing.rnFloor ?? 0).toString());
  final code = TextEditingController();
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

        (int, int) parseMinimum() {
          final value = int.tryParse(minimum.text.trim());
          final floor = staffing.pool == RolePool.nurses
              ? int.tryParse(rnFloor.text.trim())
              : 0;
          if (value == null || value < 0 || value > 100 || floor == null ||
              floor < 0 || floor > value) {
            throw const FormatException(
              'Enter a minimum from 0 to 100 and an RN floor no higher than the minimum.',
            );
          }
          return (value, floor);
        }

        return AlertDialog(
          title: Text('${staffing.pool.label} • ${staffing.coverageWindow.label} • ${DateFormat.MMMd().format(date)}'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${staffing.workingCount} working • minimum ${staffing.minimum?.toString() ?? 'not set'} • ${staffing.openCount} Open'),
                  if (staffing.shortCount case final short? when short > 0)
                    Text(
                      staffing.rnShortCount == short
                          ? 'Short $short RN'
                          : 'Short $short',
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: minimum,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Minimum people'),
                  ),
                  if (staffing.pool == RolePool.nurses) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: rnFloor,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'RN floor'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: saving ? null : () => run(() {
                          final (count, floor) = parseMinimum();
                          return rules.setWeekdayMinimum(staffing.pool,
                              staffing.coverageWindow, date.weekday % 7, count, floor);
                        }),
                        child: Text('Save every ${DateFormat.EEEE().format(date)}'),
                      ),
                      OutlinedButton(
                        onPressed: saving ? null : () => run(() {
                          final (count, floor) = parseMinimum();
                          return rules.setDateMinimum(staffing.pool,
                              staffing.coverageWindow, date, count, floor);
                        }),
                        child: const Text('Save this date'),
                      ),
                      if (staffing.dateMinimum != null)
                        TextButton(
                          onPressed: saving ? null : () => run(() =>
                              rules.setDateMinimum(staffing.pool,
                                  staffing.coverageWindow, date, null, null)),
                          child: const Text('Remove date override'),
                        ),
                    ],
                  ),
                  const Divider(height: 32),
                  TextField(
                    controller: code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Open shift Shift code'),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: saving ? null : () => run(() async {
                          await rules.postOpenShifts(date, code.text, staffing.pool, 1);
                        }),
                        child: const Text('Post one'),
                      ),
                      if ((staffing.unpostedCount ?? 0) > 0)
                        FilledButton(
                          onPressed: saving ? null : () => run(() async {
                            await rules.postOpenShifts(date, code.text,
                                staffing.pool, staffing.unpostedCount!, fillGap: true);
                          }),
                          child: Text('Post ${staffing.unpostedCount} Open shifts'),
                        ),
                    ],
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(error!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(dialogContext).pop(false),
              child: const Text('Close'),
            ),
          ],
        );
      },
    ),
  );
  minimum.dispose();
  rnFloor.dispose();
  code.dispose();
  return result;
}
