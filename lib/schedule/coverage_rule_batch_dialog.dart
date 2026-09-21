import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

/// Returns the Manager's choices for every set of newly needed Open shifts.
/// Null means the edit was cancelled before it reached the database.
Future<List<Map<String, dynamic>>?> confirmCoverageRuleBatch(
  BuildContext context, {
  required List<Map<String, dynamic>> plan,
  required List<CoveragePoolConfig> pools,
  required List<LegendCode> codes,
}) async {
  final choices = <String, _BatchChoice>{};
  String key(Map<String, dynamic> row) =>
      '${row['work_date']}:${row['pool']}:${row['window']}';
  for (final row in plan) {
    final pool = pools.where((item) => item.id == row['pool']).firstOrNull;
    final windowCodes = codes
        .where(
          (code) =>
              code.active &&
              code.isWorking &&
              code.coverageWindow == row['window'],
        )
        .toList();
    choices[key(row)] = _BatchChoice(
      ordinaryRole: pool?.jobRoles.firstOrNull,
      floorCode: windowCodes.firstOrNull?.code,
      ordinaryCode: windowCodes.firstOrNull?.code,
    );
  }
  String? error;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Review rule change'),
        content: SizedBox(
          width: 520,
          height: plan.isEmpty ? 120 : 450,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (plan.isEmpty)
                  const Text(
                    'No released Schedule needs Open shifts changed. '
                    'Unpublished Schedules will show the new shortfalls '
                    'without posting shifts.',
                  ),
                for (final row in plan) ...[
                  Builder(
                    builder: (context) {
                      final pool = pools
                          .where((item) => item.id == row['pool'])
                          .firstOrNull;
                      final choice = choices[key(row)]!;
                      final windowCodes = codes
                          .where(
                            (code) =>
                                code.active &&
                                code.isWorking &&
                                code.coverageWindow == row['window'],
                          )
                          .toList();
                      final date = DateTime.parse(row['work_date'] as String);
                      final floorCount = row['post_floor'] as int;
                      final ordinaryCount = row['post_ordinary'] as int;
                      final withdrawn =
                          (row['withdraw_floor'] as int) +
                          (row['withdraw_ordinary'] as int);
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${DateFormat.MMMd().format(date)} · '
                                '${pool?.name ?? row['pool']} · ${row['window']}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (withdrawn > 0)
                                Text(
                                  'Withdraw $withdrawn unfilled rule-created '
                                  'Open shifts. Pending applicants are notified.',
                                ),
                              if (floorCount > 0) ...[
                                Text(
                                  'Post $floorCount floor-critical '
                                  '${row['floor_role']} shifts (approval required).',
                                ),
                                DropdownButtonFormField<String>(
                                  initialValue: choice.floorCode,
                                  decoration: const InputDecoration(
                                    labelText: 'Floor Shift code',
                                  ),
                                  items: [
                                    for (final code in windowCodes)
                                      DropdownMenuItem(
                                        value: code.code,
                                        child: Text(code.code),
                                      ),
                                  ],
                                  onChanged: (value) =>
                                      setState(() => choice.floorCode = value),
                                ),
                              ],
                              if (ordinaryCount > 0) ...[
                                Text('Post $ordinaryCount other Open shifts.'),
                                DropdownButtonFormField<JobRole>(
                                  initialValue: choice.ordinaryRole,
                                  decoration: const InputDecoration(
                                    labelText: 'Job role',
                                  ),
                                  items: [
                                    for (final role
                                        in pool?.jobRoles ?? const <JobRole>{})
                                      DropdownMenuItem(
                                        value: role,
                                        child: Text(role.label),
                                      ),
                                  ],
                                  onChanged: (value) => setState(
                                    () => choice.ordinaryRole = value,
                                  ),
                                ),
                                DropdownButtonFormField<String>(
                                  initialValue: choice.ordinaryCode,
                                  decoration: const InputDecoration(
                                    labelText: 'Shift code',
                                  ),
                                  items: [
                                    for (final code in windowCodes)
                                      DropdownMenuItem(
                                        value: code.code,
                                        child: Text(code.code),
                                      ),
                                  ],
                                  onChanged: (value) => setState(
                                    () => choice.ordinaryCode = value,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (plan.any((row) {
                final choice = choices[key(row)]!;
                return (row['post_floor'] as int) > 0 &&
                        choice.floorCode == null ||
                    (row['post_ordinary'] as int) > 0 &&
                        (choice.ordinaryCode == null ||
                            choice.ordinaryRole == null);
              })) {
                setState(
                  () => error =
                      'Choose a Job role and Shift code for '
                      'every new set of Open shifts.',
                );
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: Text(plan.isEmpty ? 'Save rule' : 'Confirm batch'),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true) return null;
  return [
    for (final row in plan)
      if ((row['post_floor'] as int) > 0 || (row['post_ordinary'] as int) > 0)
        {
          'work_date': row['work_date'],
          'pool': row['pool'],
          'window': row['window'],
          'floor_role': row['floor_role'],
          'floor_shift_code': choices[key(row)]!.floorCode,
          'ordinary_role': choices[key(row)]!.ordinaryRole?.value,
          'ordinary_shift_code': choices[key(row)]!.ordinaryCode,
        },
  ];
}

final class _BatchChoice {
  _BatchChoice({this.ordinaryRole, this.floorCode, this.ordinaryCode});
  JobRole? ordinaryRole;
  String? floorCode;
  String? ordinaryCode;
}
