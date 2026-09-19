import 'package:flutter/material.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'invite_composer.dart';
import 'past_staff_page.dart';
import 'staff_dialogs.dart';
import 'staff_details_page.dart';
import 'staff_gateway.dart';

export 'invite_composer.dart' show InviteComposer;

class StaffListPage extends StatefulWidget {
  const StaffListPage({
    super.key,
    required this.gateway,
    required this.rules,
    required this.inviteComposer,
  });

  final StaffGateway gateway;

  /// Last days and dated Section and role changes go through the rules.
  final ScheduleRules rules;
  final InviteComposer inviteComposer;

  @override
  State<StaffListPage> createState() => _StaffListPageState();
}

class _StaffListPageState extends State<StaffListPage> {
  StaffList? _staffList;
  Object? _loadError;
  bool _canManageSections = false;
  bool _savingSectionOrder = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (staffList, canManageSections) = await (
        widget.gateway.loadStaffList(),
        widget.gateway.canManageSections(),
      ).wait;
      if (mounted) {
        setState(() {
          _staffList = staffList;
          _canManageSections = canManageSections;
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
      builder: (context) => _AddStaffMemberDialog(sections: staffList.sections),
    );
    if (draft == null) return;

    try {
      final invite = await widget.gateway.addStaffMember(draft);
      await widget.inviteComposer.open(invite);
      await _load();
    } catch (error) {
      if (mounted) {
        _showError('Could not add the Staff member or open Messages.');
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
                  final contact =
                      member.personalEmail ??
                      (member.cellNumber == null
                          ? 'No cell number yet'
                          : '${member.cellNumber} · Invite pending');
                  return ListTile(
                    key: ValueKey(member.id),
                    onTap: () => onOpenDetails(member),
                    contentPadding: EdgeInsets.zero,
                    leading: ReorderableDragStartListener(
                      index: index,
                      child: const Icon(Icons.drag_handle),
                    ),
                    title: Text(member.displayName),
                    subtitle: Text(
                      [?member.jobRole?.label, contact].join(' · '),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (member.personalEmail != null)
                          const Tooltip(
                            message: 'Invite accepted',
                            child: Icon(Icons.check_circle_outline),
                          )
                        else if (member.cellNumber != null)
                          IconButton(
                            tooltip: 'Resend Invite to ${member.displayName}',
                            onPressed: () => onResendInvite(member),
                            icon: const Icon(Icons.sms_outlined),
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
                              child: Text('Change Section or role'),
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
      autofocus: true,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(labelText: 'Section name'),
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
    if (name.isNotEmpty) Navigator.pop(context, name);
  }
}

class _AddStaffMemberDialog extends StatefulWidget {
  const _AddStaffMemberDialog({required this.sections});

  final List<StaffSection> sections;

  @override
  State<_AddStaffMemberDialog> createState() => _AddStaffMemberDialogState();
}

class _AddStaffMemberDialogState extends State<_AddStaffMemberDialog> {
  final _name = TextEditingController();
  final _cellNumber = TextEditingController();
  late String _sectionId = widget.sections.first.id;

  @override
  void dispose() {
    _name.dispose();
    _cellNumber.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().isEmpty || _cellNumber.text.trim().isEmpty) return;
    Navigator.of(context).pop(
      StaffMemberDraft(
        displayName: _name.text.trim(),
        cellNumber: _cellNumber.text.trim(),
        sectionId: _sectionId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Staff member'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: _cellNumber,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Cell number'),
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
