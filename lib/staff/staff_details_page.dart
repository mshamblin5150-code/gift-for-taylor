import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'invite_composer.dart';
import 'staff_dialogs.dart';
import 'staff_gateway.dart';

class StaffDetailsPage extends StatefulWidget {
  const StaffDetailsPage({
    super.key,
    required this.staffMemberId,
    required this.gateway,
    required this.rules,
    required this.inviteComposer,
  });

  final String staffMemberId;
  final StaffGateway gateway;
  final ScheduleRules rules;
  final InviteComposer inviteComposer;

  @override
  State<StaffDetailsPage> createState() => _StaffDetailsPageState();
}

class _StaffDetailsPageState extends State<StaffDetailsPage> {
  StaffMemberDetails? _details;
  StaffList? _list;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (details, list) = await (
        widget.gateway.loadStaffMemberDetails(widget.staffMemberId),
        widget.gateway.loadStaffList(),
      ).wait;
      if (mounted) {
        setState(() {
          _details = details;
          _list = list;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editContact() async {
    final details = _details!;
    final update = await showDialog<(String, String?)>(
      context: context,
      builder: (context) => _EditContactDialog(details: details),
    );
    if (update == null) return;
    try {
      await widget.gateway.updateStaffContact(details.id, update.$1, update.$2);
      await _load();
    } catch (_) {
      if (mounted) _showError('Could not save name and cell number.');
    }
  }

  Future<void> _changeSectionOrRole() async {
    final details = _details!;
    final sectionId = details.sectionId;
    if (sectionId == null || _list == null) return;
    final change = await showDialog<SectionOrRoleChange>(
      context: context,
      builder: (context) => ChangeSectionOrRoleDialog(
        displayName: details.displayName,
        sections: _list!.sections,
        sectionId: sectionId,
        jobRole: details.jobRole,
      ),
    );
    if (change == null) return;
    try {
      if (change.sectionId case final id?) {
        await widget.rules.changeSection(
          ChangeSection(
            staffMemberId: details.id,
            sectionId: id,
            from: change.from,
          ),
        );
      }
      if (change.jobRole case final role?) {
        await widget.rules.changeJobRole(
          ChangeJobRole(
            staffMemberId: details.id,
            jobRole: role,
            from: change.from,
          ),
        );
      }
      await _load();
    } catch (_) {
      await _load();
      if (mounted) _showError('Could not save the change.');
    }
  }

  Future<void> _setLastDay() async {
    final details = _details!;
    final day = await showDialog<DateTime>(
      context: context,
      builder: (context) => SetLastDayDialog(displayName: details.displayName),
    );
    if (day == null) return;
    try {
      await widget.rules.setLastDay(
        SetLastDay(staffMemberId: details.id, lastDay: day),
      );
      await _load();
    } catch (_) {
      if (mounted) _showError('Could not set the Last day.');
    }
  }

  Future<void> _resendInvite() async {
    try {
      final invite = await widget.gateway.resendInvite(widget.staffMemberId);
      await widget.inviteComposer.open(invite);
    } catch (_) {
      if (mounted) _showError('Could not create or text a fresh Invite.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = _details;
    final sectionName = _list?.sections
        .where((section) => section.id == details?.sectionId)
        .firstOrNull
        ?.name;
    return Scaffold(
      appBar: AppBar(
        title: Text(details?.displayName ?? 'Staff member details'),
      ),
      body: switch ((details, _error)) {
        (_, Object()) => const Center(
          child: Text('Could not load Staff member details.'),
        ),
        (null, _) => const Center(child: CircularProgressIndicator()),
        (final StaffMemberDetails person, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Detail(label: 'Name', value: person.displayName),
            _Detail(
              label: 'Cell number',
              value: person.cellNumber ?? 'No cell number yet',
            ),
            _Detail(label: 'Section', value: sectionName ?? 'No Section'),
            _Detail(
              label: 'Job role',
              value: person.jobRole?.label ?? 'Not set',
            ),
            _Detail(label: 'Access role', value: person.role.replaceAll('_', ' ')),
            _Detail(
              label: 'Last day',
              value: person.lastDay == null
                  ? 'Not set'
                  : DateFormat.yMMMd().format(person.lastDay!),
            ),
            _Detail(
              label: 'Personal email',
              value: person.personalEmail ?? 'Not signed up yet',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _editContact,
              child: const Text('Edit name and cell number'),
            ),
            if (person.lastDay == null) ...[
              OutlinedButton(
                onPressed: _changeSectionOrRole,
                child: const Text('Change Section or role'),
              ),
              OutlinedButton(
                onPressed: _setLastDay,
                child: const Text('Set Last day'),
              ),
              if (person.personalEmail == null && person.cellNumber != null)
                OutlinedButton(
                  onPressed: _resendInvite,
                  child: const Text('Resend Invite'),
                ),
            ],
          ],
        ),
      },
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) =>
      ListTile(title: Text(label), subtitle: Text(value));
}

class _EditContactDialog extends StatefulWidget {
  const _EditContactDialog({required this.details});
  final StaffMemberDetails details;

  @override
  State<_EditContactDialog> createState() => _EditContactDialogState();
}

class _EditContactDialogState extends State<_EditContactDialog> {
  late final _name = TextEditingController(text: widget.details.displayName);
  late final _cell = TextEditingController(text: widget.details.cellNumber);

  @override
  void dispose() {
    _name.dispose();
    _cell.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit Staff member'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        TextField(
          controller: _cell,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Cell number'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _name.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, (
                _name.text.trim(),
                _cell.text.trim().isEmpty ? null : _cell.text.trim(),
              )),
        child: const Text('Save'),
      ),
    ],
  );
}
