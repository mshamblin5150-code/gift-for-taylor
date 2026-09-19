import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'staff_gateway.dart';

/// Asks for a departing person's Last day; pops the chosen day.
class SetLastDayDialog extends StatefulWidget {
  const SetLastDayDialog({super.key, required this.displayName});

  final String displayName;

  @override
  State<SetLastDayDialog> createState() => _SetLastDayDialogState();
}

class _SetLastDayDialogState extends State<SetLastDayDialog> {
  DateTime _lastDay = _today();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Set ${widget.displayName}\'s Last day'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DateField(
            label: 'Last day',
            value: _lastDay,
            onChanged: (day) => setState(() => _lastDay = day),
          ),
          const SizedBox(height: 12),
          const Text(
            'Their shifts after this day are cleared and marked short. '
            'They move to Past staff and can no longer sign in.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_lastDay),
          child: const Text('Set Last day'),
        ),
      ],
    );
  }
}

/// A dated Section and/or role change. A field is null when it is unchanged.
final class SectionOrRoleChange {
  const SectionOrRoleChange({required this.from, this.sectionId, this.jobRole});

  final DateTime from;
  final String? sectionId;
  final JobRole? jobRole;
}

class ChangeSectionOrRoleDialog extends StatefulWidget {
  const ChangeSectionOrRoleDialog({
    super.key,
    required this.displayName,
    required this.sections,
    required this.sectionId,
    required this.jobRole,
  });

  final String displayName;
  final List<StaffSection> sections;
  final String sectionId;
  final JobRole? jobRole;

  @override
  State<ChangeSectionOrRoleDialog> createState() =>
      _ChangeSectionOrRoleDialogState();
}

class _ChangeSectionOrRoleDialogState extends State<ChangeSectionOrRoleDialog> {
  late String _sectionId = widget.sectionId;
  late JobRole? _jobRole = widget.jobRole;
  DateTime _from = _today();

  void _submit() {
    final sectionChanged = _sectionId != widget.sectionId;
    final roleChanged = _jobRole != widget.jobRole;
    if (!sectionChanged && !roleChanged) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(
      SectionOrRoleChange(
        from: _from,
        sectionId: sectionChanged ? _sectionId : null,
        jobRole: roleChanged ? _jobRole : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Change ${widget.displayName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _sectionId,
              decoration: const InputDecoration(labelText: 'Section'),
              items: [
                for (final section in widget.sections)
                  DropdownMenuItem(
                    value: section.id,
                    child: Text(section.name),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _sectionId = value);
              },
            ),
            DropdownButtonFormField<JobRole>(
              initialValue: _jobRole,
              decoration: const InputDecoration(labelText: 'Role'),
              hint: const Text('Not set'),
              items: [
                for (final role in JobRole.values)
                  DropdownMenuItem(value: role, child: Text(role.label)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _jobRole = value);
              },
            ),
            const SizedBox(height: 8),
            DateField(
              label: 'From',
              value: _from,
              onChanged: (day) => setState(() => _from = day),
            ),
            const SizedBox(height: 12),
            const Text(
              'Their row moves from this date. Shifts already scheduled stay '
              'for you to adjust.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save change')),
      ],
    );
  }
}

/// Where and when a past Staff member comes back.
final class Reactivation {
  const Reactivation({required this.sectionId, required this.firstDay});

  final String sectionId;
  final DateTime firstDay;
}

class ReactivateDialog extends StatefulWidget {
  const ReactivateDialog({
    super.key,
    required this.member,
    required this.sections,
  });

  final PastStaffMember member;
  final List<StaffSection> sections;

  @override
  State<ReactivateDialog> createState() => _ReactivateDialogState();
}

class _ReactivateDialogState extends State<ReactivateDialog> {
  late String _sectionId =
      widget.sections.any((section) => section.id == widget.member.sectionId)
      ? widget.member.sectionId!
      : widget.sections.first.id;
  late DateTime _firstDay = _earliestFirstDay;

  DateTime get _earliestFirstDay {
    final lastDay = widget.member.lastDay;
    final dayAfter = lastDay == null
        ? null
        : DateTime(lastDay.year, lastDay.month, lastDay.day + 1);
    final today = _today();
    return dayAfter != null && dayAfter.isAfter(today) ? dayAfter : today;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Reactivate ${widget.member.displayName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _sectionId,
            decoration: const InputDecoration(labelText: 'Section'),
            items: [
              for (final section in widget.sections)
                DropdownMenuItem(value: section.id, child: Text(section.name)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _sectionId = value);
            },
          ),
          const SizedBox(height: 8),
          DateField(
            label: 'First day back',
            value: _firstDay,
            firstDate: _earliestFirstDay,
            onChanged: (day) => setState(() => _firstDay = day),
          ),
          const SizedBox(height: 12),
          const Text(
            'They return at the bottom of the Section, with their past '
            'months still connected, and get a fresh Invite by text.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(Reactivation(sectionId: _sectionId, firstDay: _firstDay)),
          child: const Text('Reactivate and text Invite'),
        ),
      ],
    );
  }
}

/// A labeled date that opens the date picker when tapped.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? firstDate;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: firstDate ?? DateTime(value.year - 1),
          lastDate: DateTime(value.year + 2),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_month),
        ),
        child: Text(DateFormat.yMMMEd().format(value)),
      ),
    );
  }
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}
