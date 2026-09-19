import 'package:flutter/material.dart';

import 'invite_composer.dart';
import 'staff_gateway.dart';

export 'invite_composer.dart' show InviteComposer;

class StaffListPage extends StatefulWidget {
  const StaffListPage({
    super.key,
    required this.gateway,
    required this.inviteComposer,
  });

  final StaffGateway gateway;
  final InviteComposer inviteComposer;

  @override
  State<StaffListPage> createState() => _StaffListPageState();
}

class _StaffListPageState extends State<StaffListPage> {
  StaffList? _staffList;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final staffList = await widget.gateway.loadStaffList();
      if (mounted) {
        setState(() {
          _staffList = staffList;
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
      ),
    );
    if (draft == null) return;

    try {
      final invite = await widget.gateway.addStaffMember(draft);
      await widget.inviteComposer.open(invite);
      await _load();
    } catch (error) {
      if (mounted) _showError('Could not add the Staff member or open Messages.');
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

  Future<void> _reorder(
    StaffSection section,
    List<StaffListMember> members,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex > oldIndex) newIndex -= 1;
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

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final staffList = _staffList;
    return Scaffold(
      appBar: AppBar(title: const Text('Staff list')),
      floatingActionButton: staffList == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _addStaffMember,
              icon: const Icon(Icons.person_add),
              label: const Text('Add Staff member'),
            ),
      body: switch ((staffList, _loadError)) {
        (_, Object()) => const Center(child: Text('Could not load the Staff list.')),
        (null, _) => const Center(child: CircularProgressIndicator()),
        (final StaffList list, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            for (final section in list.sections) _buildSection(list, section),
          ],
        ),
      },
    );
  }

  Widget _buildSection(StaffList list, StaffSection section) {
    final members = list.membersInSection(section.id);
    return _SectionStaffList(
      section: section,
      members: members,
      onReorder: (oldIndex, newIndex) => _reorder(
        section,
        members,
        oldIndex,
        newIndex,
      ),
      onResendInvite: _resendInvite,
    );
  }
}

class _SectionStaffList extends StatelessWidget {
  const _SectionStaffList({
    required this.section,
    required this.members,
    required this.onReorder,
    required this.onResendInvite,
  });

  final StaffSection section;
  final List<StaffListMember> members;
  final ReorderCallback onReorder;
  final ValueChanged<StaffListMember> onResendInvite;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(section.name, style: Theme.of(context).textTheme.titleMedium),
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
                onReorder: onReorder,
                itemBuilder: (context, index) {
                  final member = members[index];
                  return ListTile(
                    key: ValueKey(member.id),
                    contentPadding: EdgeInsets.zero,
                    leading: ReorderableDragStartListener(
                      index: index,
                      child: const Icon(Icons.drag_handle),
                    ),
                    title: Text(member.displayName),
                    subtitle: Text(
                      member.personalEmail ?? '${member.cellNumber} · Invite pending',
                    ),
                    trailing: member.personalEmail == null
                        ? IconButton(
                            tooltip: 'Resend Invite to ${member.displayName}',
                            onPressed: () => onResendInvite(member),
                            icon: const Icon(Icons.sms_outlined),
                          )
                        : const Tooltip(
                            message: 'Invite accepted',
                            child: Icon(Icons.check_circle_outline),
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
