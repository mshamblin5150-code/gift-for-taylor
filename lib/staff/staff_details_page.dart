import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'contact_picker.dart';
import 'invite_composer.dart';
import 'staff_dialogs.dart';
import 'staff_gateway.dart';
import 'staff_contacts.dart';

class StaffDetailsPage extends StatefulWidget {
  const StaffDetailsPage({
    super.key,
    required this.staffMemberId,
    required this.gateway,
    required this.rules,
    required this.inviteComposer,
    this.phoneContacts = const BrowserPhoneContacts(),
  });

  final String staffMemberId;
  final StaffGateway gateway;
  final ScheduleRules rules;
  final InviteComposer inviteComposer;
  final PhoneContacts phoneContacts;

  @override
  State<StaffDetailsPage> createState() => _StaffDetailsPageState();
}

class _StaffDetailsPageState extends State<StaffDetailsPage> {
  StaffMemberDetails? _details;
  StaffList? _list;
  String? _currentRole;
  bool _canTransferManager = false;
  List<StaffAccessChange> _accessChanges = const [];
  Set<String> _nightSectionIds = const {};
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (
        details,
        list,
        currentRole,
        accessChanges,
        canTransferManager,
        nightSectionIds,
      ) = await (
        widget.gateway.loadStaffMemberDetails(widget.staffMemberId),
        widget.gateway.loadStaffList(),
        widget.gateway.currentStaffRole(),
        widget.gateway.loadStaffAccessChanges(widget.staffMemberId),
        widget.gateway.canTransferManagerTo(widget.staffMemberId),
        widget.gateway.loadNightSchedulerSections(widget.staffMemberId),
      ).wait;
      if (mounted) {
        setState(() {
          _details = details;
          _list = list;
          _currentRole = currentRole;
          _accessChanges = accessChanges;
          _canTransferManager = canTransferManager;
          _nightSectionIds = nightSectionIds;
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
      builder: (context) => _EditContactDialog(
        details: details,
        phoneContacts: widget.phoneContacts,
      ),
    );
    if (update == null) return;
    try {
      await widget.gateway.updateStaffContact(details.id, update.$1, update.$2);
      await _load();
    } catch (_) {
      if (mounted) _showError('Could not save name and cell number.');
    }
  }

  void _saveToContacts() {
    final details = _details!;
    try {
      widget.phoneContacts.save(details.displayName, details.cellNumber!);
    } catch (_) {
      _showError('Could not save this contact to your phone.');
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

  Future<void> _changeAccessRole() async {
    final details = _details!;
    final selection =
        await showDialog<
          ({
            bool administrator,
            Set<String> sections,
            bool transfer,
            bool formerAdministrator,
            Set<String> formerSections,
          })
        >(
          context: context,
          builder: (context) => _AccessRoleDialog(
            details: details,
            sections: _list!.sections,
            nightSectionIds: _nightSectionIds,
            canTransferManager:
                _currentRole == 'manager' && _canTransferManager,
          ),
        );
    if (selection == null) return;
    try {
      if (selection.transfer) {
        await widget.gateway.transferManagerWithAccess(
          details.id,
          selection.formerAdministrator,
          selection.formerSections,
        );
      } else {
        await widget.gateway.setAccessRole(
          details.id,
          selection.administrator
              ? 'administrator'
              : selection.sections.isNotEmpty
              ? 'night_scheduler'
              : 'staff_member',
          selection.sections,
        );
      }
      await _load();
    } catch (_) {
      if (mounted) _showError('Could not change the access role.');
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
              value: person.cellNumber ?? 'Add a cell number to finish setup',
            ),
            _Detail(label: 'Section', value: sectionName ?? 'No Section'),
            _Detail(
              label: 'Job role',
              value: person.jobRole?.label ?? 'Not set',
            ),
            _Detail(
              label: 'Access',
              value: [
                if (person.role == 'manager') 'Manager',
                if (person.role == 'administrator') 'Administrator',
                if (_nightSectionIds.isNotEmpty) 'Night scheduler',
                if (person.role == 'staff_member' && _nightSectionIds.isEmpty)
                  'Staff member',
              ].join(' and '),
            ),
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
            if (person.cellNumber?.trim().isNotEmpty ?? false)
              OutlinedButton(
                onPressed: _saveToContacts,
                child: const Text('Add to contacts'),
              ),
            FilledButton(
              onPressed: _editContact,
              child: const Text('Edit name and cell number'),
            ),
            if ((_currentRole == 'manager' ||
                    _currentRole == 'maintainer' ||
                    _currentRole == 'administrator') &&
                person.role != 'manager')
              OutlinedButton(
                onPressed: _changeAccessRole,
                child: const Text('Change access'),
              ),
            if (person.lastDay == null) ...[
              OutlinedButton(
                onPressed: _changeSectionOrRole,
                child: const Text('Change Section or Job role'),
              ),
              OutlinedButton(
                onPressed: _setLastDay,
                child: const Text('Set Last day'),
              ),
              if (person.personalEmail == null) ...[
                OutlinedButton(
                  onPressed: person.cellNumber == null ? null : _resendInvite,
                  child: const Text('Resend Invite'),
                ),
                if (person.cellNumber == null)
                  const Text('Add a cell number before sending an Invite'),
              ],
            ],
            if (_accessChanges.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Access history'),
              for (final change in _accessChanges)
                ListTile(
                  title: Text(
                    '${change.oldRole.replaceAll('_', ' ')} → ${change.newRole.replaceAll('_', ' ')}',
                  ),
                  subtitle: Text(
                    DateFormat.yMMMd().add_jm().format(change.changedAt),
                  ),
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

class _AccessRoleDialog extends StatefulWidget {
  const _AccessRoleDialog({
    required this.details,
    required this.sections,
    required this.nightSectionIds,
    required this.canTransferManager,
  });

  final StaffMemberDetails details;
  final List<StaffSection> sections;
  final Set<String> nightSectionIds;
  final bool canTransferManager;

  @override
  State<_AccessRoleDialog> createState() => _AccessRoleDialogState();
}

class _AccessRoleDialogState extends State<_AccessRoleDialog> {
  late bool _administrator = widget.details.role == 'administrator';
  late final Set<String> _sectionIds = {...widget.nightSectionIds};
  bool _transfer = false;
  bool _formerAdministrator = false;
  final Set<String> _formerSections = {};

  @override
  Widget build(BuildContext context) {
    final departed = widget.details.lastDay != null;
    return AlertDialog(
      title: Text('Change access for ${widget.details.displayName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (departed && (_administrator || _sectionIds.isNotEmpty))
              const Text('Remove access after the Last day.'),
            CheckboxListTile(
              title: const Text('Administrator'),
              value: _administrator,
              onChanged: departed && !_administrator
                  ? null
                  : (value) => setState(() => _administrator = value ?? false),
            ),
            if (!departed || _sectionIds.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Sections this Night scheduler may edit'),
              for (final section in widget.sections)
                CheckboxListTile(
                  title: Text(section.name),
                  value: _sectionIds.contains(section.id),
                  onChanged: departed && !_sectionIds.contains(section.id)
                      ? null
                      : (checked) => setState(() {
                          if (checked == true) {
                            _sectionIds.add(section.id);
                          } else {
                            _sectionIds.remove(section.id);
                          }
                        }),
                ),
            ],
            if (!departed && widget.canTransferManager) ...[
              const Divider(),
              CheckboxListTile(
                title: const Text('Transfer Manager'),
                value: _transfer,
                onChanged: (value) =>
                    setState(() => _transfer = value ?? false),
              ),
              if (_transfer) ...[
                const Text('The selected Staff member becomes Manager immediately.'),
                const Text(
                  'Your access after handover (Staff member by default)',
                ),
                CheckboxListTile(
                  title: const Text('Administrator'),
                  value: _formerAdministrator,
                  onChanged: (value) =>
                      setState(() => _formerAdministrator = value ?? false),
                ),
                const Text('Night scheduler Sections'),
                for (final section in widget.sections)
                  CheckboxListTile(
                    title: Text(section.name),
                    value: _formerSections.contains(section.id),
                    onChanged: (checked) => setState(() {
                      if (checked == true) {
                        _formerSections.add(section.id);
                      } else {
                        _formerSections.remove(section.id);
                      }
                    }),
                  ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              !_transfer &&
                  _administrator == (widget.details.role == 'administrator') &&
                  _sectionIds.length == widget.nightSectionIds.length &&
                  _sectionIds.containsAll(widget.nightSectionIds)
              ? null
              : () => Navigator.pop(context, (
                  administrator: _administrator,
                  sections: _sectionIds,
                  transfer: _transfer,
                  formerAdministrator: _formerAdministrator,
                  formerSections: _formerSections,
                )),
          child: Text(_transfer ? 'Transfer Manager' : 'Save access'),
        ),
      ],
    );
  }
}

class _EditContactDialog extends StatefulWidget {
  const _EditContactDialog({
    required this.details,
    required this.phoneContacts,
  });
  final StaffMemberDetails details;
  final PhoneContacts phoneContacts;

  @override
  State<_EditContactDialog> createState() => _EditContactDialogState();
}

class _EditContactDialogState extends State<_EditContactDialog> {
  late final _name = TextEditingController(text: widget.details.displayName);
  String? _nameError;
  late final _cell = TextEditingController(text: widget.details.cellNumber);
  String? _cellError;

  Future<void> _pickContact() async {
    try {
      final contact = await chooseContactNumber(context, widget.phoneContacts);
      if (contact == null || !mounted) return;
      _name.text = contact.$1.trim();
      _cell.text = contact.$2.trim();
      setState(() => _cellError = null);
    } catch (_) {
      if (mounted) {
        setState(
          () => _cellError =
              'Could not choose a contact. Enter the number below.',
        );
      }
    }
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    if (name.runes.length > staffNameLimit) {
      setState(() => _nameError = 'Use $staffNameLimit characters or fewer.');
      return;
    }
    final rawCell = _cell.text.trim();
    String? cell;
    try {
      cell = rawCell.isEmpty ? null : normalizeCellNumber(rawCell);
    } on FormatException {
      setState(() => _cellError = 'Enter a cell number with its area code.');
      return;
    }
    Navigator.pop(context, (name, cell));
  }

  @override
  void dispose() {
    _name.dispose();
    _cell.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit Staff member'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.phoneContacts.canPick)
            OutlinedButton(
              onPressed: _pickContact,
              child: const Text('Choose from contacts'),
            )
          else
            const Text(
              'Enter a name and cell number from your contacts below.',
            ),
          TextField(
            controller: _name,
            maxLength: staffNameLimit,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            decoration: InputDecoration(
              labelText: 'Name',
              errorText: _nameError,
            ),
            onChanged: (_) => setState(() => _nameError = null),
          ),
          TextField(
            controller: _cell,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Cell number',
              errorText: _cellError,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Save')),
    ],
  );
}
