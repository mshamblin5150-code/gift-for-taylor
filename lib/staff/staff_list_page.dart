import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

import '../help/help_page.dart';
import 'contact_picker.dart';
import 'invite_composer.dart';
import 'past_staff_page.dart';
import 'staff_dialogs.dart';
import 'staff_details_page.dart';
import 'staff_gateway.dart';
import 'staff_contacts.dart';

export 'invite_composer.dart' show InviteComposer;

class StaffListPage extends StatefulWidget {
  const StaffListPage({
    super.key,
    required this.gateway,
    required this.rules,
    required this.inviteComposer,
    this.phoneContacts = const BrowserPhoneContacts(),
  });

  final StaffGateway gateway;

  /// Last days and dated Section and role changes go through the rules.
  final ScheduleRules rules;
  final InviteComposer inviteComposer;
  final PhoneContacts phoneContacts;

  @override
  State<StaffListPage> createState() => _StaffListPageState();
}

class _StaffListPageState extends State<StaffListPage> {
  StaffList? _staffList;
  Object? _loadError;
  bool _canManageSections = false;
  String? _currentRole;
  bool _savingSectionOrder = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (staffList, canManageSections, currentRole) = await (
        widget.gateway.loadStaffList(),
        widget.gateway.canManageSections(),
        widget.gateway.currentStaffRole(),
      ).wait;
      if (mounted) {
        setState(() {
          _staffList = staffList;
          _canManageSections = canManageSections;
          _currentRole = currentRole;
          _loadError = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  Future<void> _addStaffMember() async {
    final staffList = _staffList;
    if (staffList == null || staffList.sections.isEmpty) return;
    final draft = await showDialog<StaffMemberDraft>(
      context: context,
      builder: (context) => _AddStaffMemberDialog(
        sections: staffList.sections,
        phoneContacts: widget.phoneContacts,
      ),
    );
    if (draft == null) return;

    try {
      final pastStaff = await widget.gateway.loadPastStaff();
      if (!mounted) return;
      final matches = pastStaff
          .where((member) => member.cellNumber == draft.cellNumber)
          .toList();
      var allowRecycledCell = false;
      for (final match in matches) {
        final bringBack = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Past Staff member found'),
            content: Text(
              match.lastDay == null
                  ? '${match.displayName} was on the Staff list before. Bring them back?'
                  : '${match.displayName} was on the Staff list until '
                        '${DateFormat.MMMM().format(match.lastDay!)}. Bring them back?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  matches.length == 1
                      ? 'Add different person'
                      : 'Not this person',
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Bring them back'),
              ),
            ],
          ),
        );
        if (bringBack == null || !mounted) return;
        if (bringBack) {
          await _reactivateMatchedStaff(match, staffList.sections);
          return;
        }
        allowRecycledCell = true;
      }
      final invite = await widget.gateway.addStaffMember(
        draft,
        allowRecycledCell: allowRecycledCell,
      );
      await widget.inviteComposer.open(invite);
      await _load();
    } catch (error) {
      if (mounted) {
        _showError('Could not add the Staff member or open Messages.');
      }
    }
  }

  Future<void> _reactivateMatchedStaff(
    PastStaffMember member,
    List<StaffSection> sections,
  ) async {
    final reactivation = await showDialog<Reactivation>(
      context: context,
      builder: (context) =>
          ReactivateDialog(member: member, sections: sections),
    );
    if (reactivation == null || !mounted) return;
    try {
      await widget.rules.reactivate(
        Reactivate(
          staffMemberId: member.id,
          sectionId: reactivation.sectionId,
          firstDay: reactivation.firstDay,
        ),
      );
    } catch (_) {
      if (mounted) _showError('Could not reactivate ${member.displayName}.');
      return;
    }
    await _load();
    try {
      final invite = await widget.gateway.resendInvite(member.id);
      await widget.inviteComposer.open(invite);
    } catch (_) {
      if (mounted) {
        _showError(
          '${member.displayName} is back on the Staff list. '
          'Resend their Invite from there.',
        );
      }
    }
  }

  Future<void> _resendInvite(StaffListMember member) async {
    try {
      final invite = await widget.gateway.resendInvite(member.id);
      await widget.inviteComposer.open(invite);
    } catch (error) {
      if (mounted) _showError('Could not create or text a fresh Invite.');
    }
  }

  Future<void> _setLastDay(StaffListMember member) async {
    final lastDay = await showDialog<DateTime>(
      context: context,
      builder: (context) => SetLastDayDialog(displayName: member.displayName),
    );
    if (lastDay == null) return;
    try {
      await widget.rules.setLastDay(
        SetLastDay(staffMemberId: member.id, lastDay: lastDay),
      );
      await _load();
    } catch (error) {
      if (mounted) _showError('Could not set the Last day.');
    }
  }

  Future<void> _changeSectionOrRole(StaffListMember member) async {
    final staffList = _staffList;
    if (staffList == null) return;
    final change = await showDialog<SectionOrRoleChange>(
      context: context,
      builder: (context) => ChangeSectionOrRoleDialog(
        displayName: member.displayName,
        sections: staffList.sections,
        sectionId: member.sectionId,
        jobRole: member.jobRole,
      ),
    );
    if (change == null) return;
    try {
      if (change.sectionId case final sectionId?) {
        await widget.rules.changeSection(
          ChangeSection(
            staffMemberId: member.id,
            sectionId: sectionId,
            from: change.from,
          ),
        );
      }
      if (change.jobRole case final jobRole?) {
        await widget.rules.changeJobRole(
          ChangeJobRole(
            staffMemberId: member.id,
            jobRole: jobRole,
            from: change.from,
          ),
        );
      }
      await _load();
    } catch (error) {
      await _load();
      if (mounted) _showError('Could not save the change.');
    }
  }

  Future<void> _openPastStaff() async {
    final staffList = _staffList;
    if (staffList == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PastStaffPage(
          gateway: widget.gateway,
          rules: widget.rules,
          inviteComposer: widget.inviteComposer,
          sections: staffList.sections,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openDetails(StaffListMember member) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => StaffDetailsPage(
          staffMemberId: member.id,
          gateway: widget.gateway,
          rules: widget.rules,
          inviteComposer: widget.inviteComposer,
          phoneContacts: widget.phoneContacts,
        ),
      ),
    );
    await _load();
  }

  Future<void> _reorder(
    StaffSection section,
    List<StaffListMember> members,
    int oldIndex,
    int newIndex,
  ) async {
    final reordered = [...members];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    final current = _staffList!;
    setState(() {
      _staffList = current.withSectionOrder(section.id, reordered);
    });

    try {
      await widget.gateway.reorderSection(
        section.id,
        reordered.map((member) => member.id).toList(growable: false),
      );
    } catch (error) {
      await _load();
      if (mounted) _showError('Could not save the new Staff list order.');
    }
  }

  Future<void> _moveSection(int index, int offset) async {
    if (_savingSectionOrder) return;
    final current = _staffList!;
    final ordered = [...current.sections];
    final moved = ordered.removeAt(index);
    ordered.insert(index + offset, moved);
    setState(() {
      _staffList = current.withSections(ordered);
      _savingSectionOrder = true;
    });
    try {
      await widget.gateway.reorderSections([
        for (final section in ordered) section.id,
      ]);
    } catch (_) {
      await _load();
      if (mounted) _showError('Could not save the new Section order.');
    } finally {
      if (mounted) setState(() => _savingSectionOrder = false);
    }
  }

  Future<String?> _sectionName({String? initialName}) => showDialog<String>(
    context: context,
    builder: (context) => _SectionNameDialog(initialName: initialName),
  );

  Future<void> _addSection() async {
    final name = await _sectionName();
    if (name == null) return;
    try {
      await widget.gateway.addSection(name);
      await _load();
    } catch (_) {
      if (mounted) _showError('Could not add the Section. Check its name.');
    }
  }

  Future<void> _renameSection(StaffSection section) async {
    final name = await _sectionName(initialName: section.name);
    if (name == null || name == section.name) return;
    try {
      await widget.gateway.renameSection(section.id, name);
      await _load();
    } catch (_) {
      if (mounted) _showError('Could not rename the Section. Check its name.');
    }
  }

  Future<void> _deleteSection(StaffSection section) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${section.name}?'),
        content: const Text(
          'Only a Section with no Staff members or Schedule history can be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete Section'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.gateway.deleteEmptySection(section.id);
      await _load();
    } catch (_) {
      if (mounted) {
        _showError(
          'This Section has Staff members or Schedule history and cannot be deleted.',
        );
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final staffList = _staffList;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff list'),
        actions: [
          IconButton(
            tooltip: 'Help',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => HelpPage(
                  role: helpRoleForAccess(
                    _currentRole,
                    canEditSchedule:
                        _currentRole == null || _currentRole == 'manager',
                    hasEditableSections: false,
                  ),
                ),
              ),
            ),
            icon: const Icon(Icons.help_outline),
          ),
          if (staffList != null)
            IconButton(
              tooltip: 'Past staff',
              onPressed: _openPastStaff,
              icon: const Icon(Icons.history),
            ),
          if (staffList != null && _canManageSections)
            IconButton(
              tooltip: 'Add Section',
              onPressed: _addSection,
              icon: const Icon(Icons.create_new_folder_outlined),
            ),
        ],
      ),
      floatingActionButton: staffList == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _addStaffMember,
              icon: const Icon(Icons.person_add),
              label: const Text('Add Staff member'),
            ),
      body: switch ((staffList, _loadError)) {
        (_, Object()) => const Center(
          child: Text('Could not load the Staff list.'),
        ),
        (null, _) => const Center(child: CircularProgressIndicator()),
        (final StaffList list, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            for (final (index, section) in list.sections.indexed)
              _buildSection(list, section, index),
          ],
        ),
      },
    );
  }

  Widget _buildSection(StaffList list, StaffSection section, int index) {
    final members = list.membersInSection(section.id);
    return _SectionStaffList(
      section: section,
      members: members,
      canManageSection: _canManageSections,
      onMoveUp: index == 0 || _savingSectionOrder
          ? null
          : () => _moveSection(index, -1),
      onMoveDown: index == list.sections.length - 1 || _savingSectionOrder
          ? null
          : () => _moveSection(index, 1),
      onRename: () => _renameSection(section),
      onDelete: members.isEmpty ? () => _deleteSection(section) : null,
      onReorder: (oldIndex, newIndex) =>
          _reorder(section, members, oldIndex, newIndex),
      onResendInvite: _resendInvite,
      onChangeSectionOrRole: _changeSectionOrRole,
      onSetLastDay: _setLastDay,
      onOpenDetails: _openDetails,
    );
  }
}

class _SectionStaffList extends StatelessWidget {
  const _SectionStaffList({
    required this.section,
    required this.members,
    required this.canManageSection,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRename,
    required this.onDelete,
    required this.onReorder,
    required this.onResendInvite,
    required this.onChangeSectionOrRole,
    required this.onSetLastDay,
    required this.onOpenDetails,
  });

  final StaffSection section;
  final List<StaffListMember> members;
  final bool canManageSection;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onRename;
  final VoidCallback? onDelete;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<StaffListMember> onResendInvite;
  final ValueChanged<StaffListMember> onChangeSectionOrRole;
  final ValueChanged<StaffListMember> onSetLastDay;
  final ValueChanged<StaffListMember> onOpenDetails;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    section.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (canManageSection) ...[
                  IconButton(
                    tooltip: 'Move ${section.name} up',
                    onPressed: onMoveUp,
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    tooltip: 'Move ${section.name} down',
                    onPressed: onMoveDown,
                    icon: const Icon(Icons.arrow_downward),
                  ),
                  IconButton(
                    tooltip: 'Rename ${section.name}',
                    onPressed: onRename,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Delete ${section.name}',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ],
            ),
            if (members.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No Staff members'),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: members.length,
                onReorderItem: onReorder,
                itemBuilder: (context, index) {
                  final member = members[index];
                  final contact = member.cellNumber == null
                      ? 'Add a cell number to finish setup'
                      : member.personalEmail ??
                            '${member.cellNumber} · Invite pending';
                  return ListTile(
                    key: ValueKey(member.id),
                    onTap: () => onOpenDetails(member),
                    contentPadding: EdgeInsets.zero,
                    leading: ReorderableDragStartListener(
                      index: index,
                      child: const Icon(Icons.drag_handle),
                    ),
                    title: Text(member.displayName),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text([?member.jobRole?.label, contact].join(' · ')),
                        if (member.inviteCellMismatchAt != null)
                          Text(
                            "Someone opened ${member.displayName}'s Invite and the number didn't match.",
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (member.personalEmail != null)
                          const Tooltip(
                            message: 'Invite accepted',
                            child: Icon(Icons.check_circle_outline),
                          )
                        else
                          Tooltip(
                            message: member.cellNumber == null
                                ? 'Add a cell number before sending an Invite'
                                : 'Resend Invite to ${member.displayName}',
                            child: IconButton(
                              onPressed: member.cellNumber == null
                                  ? null
                                  : () => onResendInvite(member),
                              icon: const Icon(Icons.sms_outlined),
                            ),
                          ),
                        PopupMenuButton<_MemberAction>(
                          tooltip: 'Change ${member.displayName}',
                          onSelected: (action) => switch (action) {
                            _MemberAction.sectionOrRole =>
                              onChangeSectionOrRole(member),
                            _MemberAction.lastDay => onSetLastDay(member),
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: _MemberAction.sectionOrRole,
                              child: Text('Change Section or Job role'),
                            ),
                            PopupMenuItem(
                              value: _MemberAction.lastDay,
                              child: Text('Set Last day'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

enum _MemberAction { sectionOrRole, lastDay }

class _SectionNameDialog extends StatefulWidget {
  const _SectionNameDialog({this.initialName});

  final String? initialName;

  @override
  State<_SectionNameDialog> createState() => _SectionNameDialogState();
}

class _SectionNameDialogState extends State<_SectionNameDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  String? _nameError;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initialName == null ? 'Add Section' : 'Rename Section'),
    content: TextField(
      controller: _name,
      maxLength: sectionNameLimit,
      maxLengthEnforcement: MaxLengthEnforcement.none,
      autofocus: true,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(
        labelText: 'Section name',
        errorText: _nameError,
      ),
      onChanged: (_) => setState(() => _nameError = null),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Save Section')),
    ],
  );

  void _submit() {
    final name = _name.text.trim();
    if (name.runes.length > sectionNameLimit) {
      setState(() => _nameError = 'Use $sectionNameLimit characters or fewer.');
      return;
    }
    if (name.isNotEmpty) Navigator.pop(context, name);
  }
}

class _AddStaffMemberDialog extends StatefulWidget {
  const _AddStaffMemberDialog({
    required this.sections,
    required this.phoneContacts,
  });

  final List<StaffSection> sections;
  final PhoneContacts phoneContacts;

  @override
  State<_AddStaffMemberDialog> createState() => _AddStaffMemberDialogState();
}

class _AddStaffMemberDialogState extends State<_AddStaffMemberDialog> {
  final _name = TextEditingController();
  String? _nameError;
  final _cellNumber = TextEditingController();
  late String _sectionId = widget.sections.first.id;
  String? _cellError;

  @override
  void dispose() {
    _name.dispose();
    _cellNumber.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().isEmpty || _cellNumber.text.trim().isEmpty) return;
    if (_name.text.trim().runes.length > staffNameLimit) {
      setState(() => _nameError = 'Use $staffNameLimit characters or fewer.');
      return;
    }
    String cellNumber;
    try {
      cellNumber = normalizeCellNumber(_cellNumber.text);
    } on FormatException {
      setState(() => _cellError = 'Enter a cell number with its area code.');
      return;
    }
    Navigator.of(context).pop(
      StaffMemberDraft(
        displayName: _name.text.trim(),
        cellNumber: cellNumber,
        sectionId: _sectionId,
      ),
    );
  }

  Future<void> _pickContact() async {
    try {
      final contact = await chooseContactNumber(context, widget.phoneContacts);
      if (contact == null || !mounted) return;
      _name.text = contact.$1.trim();
      _cellNumber.text = contact.$2.trim();
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Staff member'),
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
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Name',
                errorText: _nameError,
              ),
              onChanged: (_) => setState(() => _nameError = null),
            ),
            TextField(
              controller: _cellNumber,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Cell number',
                errorText: _cellError,
              ),
            ),
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Add and text Invite'),
        ),
      ],
    );
  }
}
