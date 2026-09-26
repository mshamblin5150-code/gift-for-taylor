import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

Future<bool> confirmShiftCodeChange(
  BuildContext context,
  List<ShiftCodeChangePlan> plan,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review Calendar invitations'),
        content: SizedBox(
          width: 460,
          child: plan.isEmpty
              ? const Text(
                  'No released Schedule needs Calendar invitations changed.',
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Saving this Shift code will change these Calendar '
                      'invitations:',
                    ),
                    const SizedBox(height: 12),
                    for (final row in plan)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${DateFormat.MMMd().format(row.workDate)} · '
                          '${row.shiftCode} · '
                          '${row.method == 'CANCEL' ? 'withdraw' : 'replace'} '
                          '${row.count} '
                          '${row.count == 1 ? 'invitation' : 'invitations'}',
                        ),
                      ),
                    const Text(
                      'Each affected Staff member receives one summary message.',
                    ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm change'),
          ),
        ],
      ),
    ) ??
    false;
