import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'month_session.dart';

Future<StaffCellAction?> showStaffCellSheet(
  BuildContext context, {
  required ScheduleRow row,
  required DateTime date,
  required StaffCellReview review,
}) => showModalBottomSheet<StaffCellAction>(
  context: context,
  showDragHandle: true,
  builder: (context) => _StaffCellSheet(row: row, date: date, review: review),
);

class _StaffCellSheet extends StatelessWidget {
  const _StaffCellSheet({
    required this.row,
    required this.date,
    required this.review,
  });

  final ScheduleRow row;
  final DateTime date;
  final StaffCellReview review;

  @override
  Widget build(BuildContext context) {
    final action = review.action;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              row.displayName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(DateFormat('EEEE, MMMM d').format(date)),
            const SizedBox(height: 4),
            Text(
              'Shift: ${review.currentCode.isEmpty ? '—' : review.currentCode}',
            ),
            const SizedBox(height: 20),
            if (action != null)
              FilledButton(
                onPressed: () => Navigator.of(context).pop(action),
                child: Text(
                  action == StaffCellAction.recordCallIn
                      ? 'Record a Call-in'
                      : 'Withdraw the Call-in',
                ),
              )
            else ...[
              Text(_unavailableReason(review.unavailableReason!)),
              const SizedBox(height: 8),
              Text(
                'There are no actions available for this cell.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _unavailableReason(StaffCellUnavailableReason reason) {
    switch (reason) {
      case StaffCellUnavailableReason.callInSettled:
        return 'This Call-in is settled because an Open shift was filled, so it cannot be withdrawn.';
      case StaffCellUnavailableReason.callInNotRecorded:
        return 'This Call-in was not recorded through the Staff action, so it cannot be withdrawn here.';
      case StaffCellUnavailableReason.withdrawalStateUnknown:
        return 'Whether this Call-in can be withdrawn could not be checked.';
      case StaffCellUnavailableReason.recorderNotWorkingToRecord:
        return 'You must be working now to record a Call-in.';
      case StaffCellUnavailableReason.recorderNotWorkingToWithdraw:
        return 'You must be working now to withdraw a Call-in.';
      case StaffCellUnavailableReason.targetNotWorking:
        return 'This cell has no working Shift to call in from.';
      case StaffCellUnavailableReason.onFloorUnknown:
        return 'Whether you are on the floor could not be checked.';
    }
  }
}
