import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'month_session.dart';

Future<StaffCellAction?> showStaffCellSheet(
  BuildContext context, {
  required ScheduleRow row,
  required DateTime date,
  required StaffCellReview review,
  bool canEditShift = false,
}) => showModalBottomSheet<StaffCellAction>(
  context: context,
  showDragHandle: true,
  builder: (context) => _StaffCellSheet(
    row: row,
    date: date,
    review: review,
    canEditShift: canEditShift,
  ),
);

class _StaffCellSheet extends StatelessWidget {
  const _StaffCellSheet({
    required this.row,
    required this.date,
    required this.review,
    required this.canEditShift,
  });

  final ScheduleRow row;
  final DateTime date;
  final StaffCellReview review;
  final bool canEditShift;

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
            if (canEditShift) ...[
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(StaffCellAction.editShift),
                icon: const Icon(Icons.edit),
                label: const Text('Edit Shift'),
              ),
              const SizedBox(height: 12),
            ],
            if (action != null)
              FilledButton(
                onPressed: () => Navigator.of(context).pop(action),
                child: Text(
                  action == StaffCellAction.recordCallIn
                      ? 'Record a Call-in'
                      : 'Withdraw the Call-in',
                ),
              )
            else if (review.swap == null || !review.swap!.available) ...[
              Text(_unavailableReason(review.unavailableReason!)),
              const SizedBox(height: 8),
            ],
            if (review.swap case final swap?) ...[
              if (action != null) const SizedBox(height: 12),
              if (swap.available)
                FilledButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(StaffCellAction.proposeSwap),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Propose a Swap'),
                )
              else ...[
                Text(
                  'Propose a Swap',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(_swapUnavailableReason(swap.unavailableReason!)),
                const SizedBox(height: 8),
              ],
            ],
            if (action == null &&
                (review.swap == null || !review.swap!.available))
              Text(
                'There are no actions available for this cell.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
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

  String _swapUnavailableReason(StaffCellSwapUnavailableReason reason) {
    switch (reason) {
      case StaffCellSwapUnavailableReason.monthNotReleased:
        return 'This Schedule month is not released.';
      case StaffCellSwapUnavailableReason.colleagueNotInApp:
        return '${row.displayName} is not in the app yet.';
      case StaffCellSwapUnavailableReason.targetNotWorking:
        return 'This day is not a working Shift for ${row.displayName}.';
      case StaffCellSwapUnavailableReason.dayNotFuture:
        return 'Swap shifts must be after today.';
    }
  }
}
