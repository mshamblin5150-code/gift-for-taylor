import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'contact_picker.dart';
import 'invite_composer.dart';
import 'manager_handover_wording.dart';
import 'staff_details_session.dart';
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
    this.onAccessRejected,
  });

  final String staffMemberId;
  final StaffGateway gateway;
  final ScheduleRules rules;
  final InviteComposer inviteComposer;
  final PhoneContacts phoneContacts;
  final VoidCallback? onAccessRejected;

  @override
  State<StaffDetailsPage> createState() => _StaffDetailsPageState();
}

class _StaffDetailsPageState extends State<StaffDetailsPage> {
  late final StaffDetailsSession _session;

  @override
  void initState() {
    super.initState();
    _session = StaffDetailsSession(
      widget.staffMemberId,
      widget.gateway,
      widget.rules,
      widget.onAccessRejected,
    )..load();
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editContact() async {
    final details = _session.state.details!;
    final update = await showDialog<(String, String?)>(
      context: context,
      builder: (context) => _EditContactDialog(
        details: details,
        phoneContacts: widget.phoneContacts,
      ),
    );
    if (update == null) return;
    final outcome = await _session.updateContact(update.$1, update.$2);
    if (outcome case StaffCommandFailed()) {
      if (mounted) _showError('Could not save name and cell number.');
    }
  }

  void _saveToContacts() {
    final details = _session.state.details!;
    try {
      widget.phoneContacts.save(details.displayName, details.cellNumber!);
    } catch (_) {
      _showError('Could not save this contact to your phone.');
    }
  }

  Future<void> _changeSectionOrRole() async {
    final state = _session.state;
    final details = state.details!;
    final sectionId =
        managerHandoverPresentation(state.handoverCandidate?.blocker)
                .resolution ==
            ManagerHandoverResolution.assignSection
        ? null
        : details.sectionId;
    if (state.list == null) return;
    final change = await showDialog<SectionOrRoleChange>(
      context: context,
      builder: (context) => ChangeSectionOrRoleDialog(
        displayName: details.displayName,
        sections: state.list!.sections,
        sectionId: sectionId,
        jobRole: details.jobRole,
      ),
    );
    if (change == null) return;
    final outcome = await _session.changeSectionOrRole(
      from: change.from,
      sectionId: change.sectionId,
      jobRole: change.jobRole,
    );
    if (outcome case StaffCommandFailed()) {
      if (mounted) _showError('Could not save the change.');
    }
  }

  Future<void> _setLastDay() async {
    final details = _session.state.details!;
    final day = await showDialog<DateTime>(
      context: context,
      builder: (context) => SetLastDayDialog(displayName: details.displayName),
    );
    if (day == null) return;
    final outcome = await _session.setLastDay(day);
    if (outcome case StaffCommandFailed()) {
      if (mounted) _showError('Could not set the Last day.');
    }
  }

  Future<void> _resendInvite() async {
    final outcome = await _session.resendInvite();
    switch (outcome) {
      case StaffInviteReady(:final invite):
        await widget.inviteComposer.open(invite);
      case StaffInviteFailed():
        if (mounted) _showError('Could not create or text a fresh Invite.');
    }
  }

  Future<void> _resolveHandoverBlocker(ManagerHandoverBlocker blocker) async {
    switch (managerHandoverPresentation(blocker).resolution) {
      case ManagerHandoverResolution.resendInvite:
        await _resendInvite();
        return;
      case ManagerHandoverResolution.reviewInviteAcceptance:
      case ManagerHandoverResolution.reactivateStaff:
        if (mounted) Navigator.pop(context);
        return;
      case ManagerHandoverResolution.assignSection:
        await _changeSectionOrRole();
        return;
      case ManagerHandoverResolution.none:
        return;
    }
  }

  Future<void> _changeAccessRole() async {
    final state = _session.state;
    final details = state.details!;
    final selection =
        await showDialog<
          ({
            Grants grants,
            bool transfer,
            bool formerAdministrator,
            Set<String> formerSections,
          })
        >(
          context: context,
          builder: (context) => _AccessRoleDialog(
            details: details,
            sections: state.list!.sections,
            grants: state.targetGrants,
            canTransferManager: state.access.canTransferManager,
            handoverCandidate: state.handoverCandidate,
            onResolveHandoverBlocker:
                switch (state.handoverCandidate?.blocker) {
                  final ManagerHandoverBlocker blocker
                      when blocker != ManagerHandoverBlocker.alreadyManager =>
                    () => _resolveHandoverBlocker(blocker),
                  _ => null,
                },
          ),
        );
    if (selection == null) return;
    final outcome = await _session.saveAccess(
      grants: selection.grants,
      transfer: selection.transfer,
      formerAdministrator: selection.formerAdministrator,
      formerSections: selection.formerSections,
    );
    if (outcome case StaffCommandFailed()) {
      if (mounted) _showError('Could not change the access role.');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _session,
    builder: (context, _) {
      final state = _session.state;
      final details = state.details;
      final sectionName = state.list?.sections
          .where((section) => section.id == details?.sectionId)
          .firstOrNull
          ?.name;
      return Scaffold(
        appBar: AppBar(
          title: Text(details?.displayName ?? 'Staff member details'),
        ),
        body: switch ((details, state.loadError)) {
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
                  if (state.targetGrants.manager) 'Manager',
                  if (state.targetGrants.administrator) 'Administrator',
                  if (state.targetGrants.nightSchedulerSectionIds.isNotEmpty)
                    'Night scheduler',
                  if (!state.targetGrants.manager &&
                      !state.targetGrants.administrator &&
                      state.targetGrants.nightSchedulerSectionIds.isEmpty)
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
              if (state.access.canChangeAccess(state.targetGrants))
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
              if (state.accessChanges.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Access history'),
                for (final change in state.accessChanges)
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
    },
  );
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
    required this.grants,
    required this.canTransferManager,
    required this.handoverCandidate,
    required this.onResolveHandoverBlocker,
  });

  final StaffMemberDetails details;
  final List<StaffSection> sections;
  final Grants grants;
  final bool canTransferManager;
  final ManagerHandoverCandidate? handoverCandidate;
  final Future<void> Function()? onResolveHandoverBlocker;

  @override
  State<_AccessRoleDialog> createState() => _AccessRoleDialogState();
}

class _AccessRoleDialogState extends State<_AccessRoleDialog> {
  late bool _administrator = widget.grants.administrator;
  late final Set<String> _sectionIds = {
    ...widget.grants.nightSchedulerSectionIds,
  };
  bool _transfer = false;
  bool _formerAdministrator = false;
  final Set<String> _formerSections = {};

  Future<void> _resolveHandoverBlocker() async {
    Navigator.pop(context);
    await widget.onResolveHandoverBlocker?.call();
  }

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
            if (widget.canTransferManager &&
                widget.handoverCandidate != null) ...[
              const Divider(),
              if (!departed && widget.handoverCandidate!.isEligible) ...[
                CheckboxListTile(
                  title: const Text('Transfer Manager'),
                  value: _transfer,
                  onChanged: (value) =>
                      setState(() => _transfer = value ?? false),
                ),
                if (_transfer) ...[
                  const Text(
                    'The selected Staff member becomes Manager immediately.',
                  ),
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
              ] else if (!widget.handoverCandidate!.isEligible) ...[
                Text(managerHandoverNextStep(widget.handoverCandidate!)),
                if (widget.onResolveHandoverBlocker != null)
                  TextButton(
                    onPressed: _resolveHandoverBlocker,
                    child: Text(
                      managerHandoverPresentation(
                        widget.handoverCandidate!.blocker,
                      ).resolution.label,
                    ),
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
                  _administrator == widget.grants.administrator &&
                  _sectionIds.length ==
                      widget.grants.nightSchedulerSectionIds.length &&
                  _sectionIds.containsAll(
                    widget.grants.nightSchedulerSectionIds,
                  )
              ? null
              : () => Navigator.pop(context, (
                  grants: widget.grants.copyWith(
                    administrator: _administrator,
                    nightSchedulerSectionIds: _sectionIds,
                  ),
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
