import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'coverage_rule_batch_dialog.dart';

Future<bool?> showStaffingSheet(
  BuildContext context, {
  required OpenShiftStore rules,
  required List<LegendCode> shiftCodes,
  required DateTime date,
  required SectionStaffing staffing,
  required WindowCoverage reading,
  VoidCallback? onStandingMinimums,
}) async {
  final minimum = TextEditingController(
    text: staffing.minimum?.toString() ?? '',
  );
  final rnFloor = TextEditingController(
    text: (staffing.rnFloor ?? 0).toString(),
  );
  final code = TextEditingController();
  var saving = false;
  String? error;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        Future<void> run(Future<bool> Function() action) async {
          setState(() {
            saving = true;
            error = null;
          });
          try {
            final saved = await action();
            if (saved && dialogContext.mounted) {
              Navigator.of(dialogContext).pop(true);
            }
          } catch (failure) {
            setState(() => error = failure.toString());
          } finally {
            if (dialogContext.mounted) setState(() => saving = false);
          }
        }

        (int, int) parseMinimum() {
          final value = int.tryParse(minimum.text.trim());
          final floor = staffing.floorRole != null
              ? int.tryParse(rnFloor.text.trim())
              : 0;
          if (value == null ||
              value < 0 ||
              value > 100 ||
              floor == null ||
              floor < 0 ||
              floor > value) {
            throw const FormatException(
              'Enter a minimum from 0 to 100 and a floor no higher than the minimum.',
            );
          }
          return (value, floor);
        }

        Future<bool> saveDate(int? count, int floor) async {
          final plan = await rules.previewDateMinimum(
            staffing.pool,
            staffing.coverageWindow,
            date,
            count,
            staffing.floorRole,
            floor,
          );
          if (!dialogContext.mounted) return false;
          final pools = await rules.coveragePoolsOn(date);
          if (!dialogContext.mounted) return false;
          final choices = await confirmCoverageRuleBatch(
            dialogContext,
            plan: plan,
            pools: pools,
            codes: shiftCodes,
          );
          if (choices == null) return false;
          await rules.commitDateMinimum(
            staffing.pool,
            staffing.coverageWindow,
            date,
            count,
            staffing.floorRole,
            floor,
            plan,
            choices,
          );
          return true;
        }

        return AlertDialog(
          title: Text(
            '${staffing.pool.label} • ${staffing.coverageWindow.label} • ${DateFormat.MMMd().format(date)}',
          ),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${staffing.workingCount} working • minimum ${staffing.minimum?.toString() ?? 'not set'} • ${staffing.openCount} Open',
                  ),
                  if (reading.shortfall > 0)
                    Text(
                      reading.summary,
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
                  if (staffing.floorRole != null) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: rnFloor,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '${staffing.floorRole!.label} floor',
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (onStandingMinimums != null)
                        TextButton(
                          onPressed: saving
                              ? null
                              : () {
                                  Navigator.of(dialogContext).pop(false);
                                  onStandingMinimums();
                                },
                          child: const Text('Standing minimums in Settings'),
                        ),
                      OutlinedButton(
                        onPressed: saving
                            ? null
                            : () => run(() {
                                final (count, floor) = parseMinimum();
                                return saveDate(count, floor);
                              }),
                        child: const Text('Save this date'),
                      ),
                      if (staffing.dateMinimum != null)
                        TextButton(
                          onPressed: saving
                              ? null
                              : () => run(() => saveDate(null, 0)),
                          child: const Text('Remove date override'),
                        ),
                    ],
                  ),
                  const Text(
                    'Standing weekday defaults are in Unit coverage settings.',
                  ),
                  const Divider(height: 32),
                  TextField(
                    controller: code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Open shift Shift code',
                    ),
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
                                  date,
                                  code.text,
                                  staffing.pool,
                                  1,
                                );
                                return true;
                              }),
                        child: const Text('Post one'),
                      ),
                      if ((staffing.unpostedCount ?? 0) > 0)
                        FilledButton(
                          onPressed: saving
                              ? null
                              : () => run(() async {
                                  await rules.postOpenShifts(
                                    date,
                                    code.text,
                                    staffing.pool,
                                    staffing.unpostedCount!,
                                    fillGap: true,
                                  );
                                  return true;
                                }),
                          child: Text(
                            'Post ${staffing.unpostedCount} Open shifts',
                          ),
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
  rnFloor.dispose();
  code.dispose();
  return result;
}
