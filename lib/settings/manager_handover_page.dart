import 'package:flutter/material.dart';

import '../staff/staff_gateway.dart';

/// Transfers Manager in one database transaction. Maintainer access uses a
/// separate provisioned login.
class ManagerHandoverPage extends StatefulWidget {
  const ManagerHandoverPage({
    super.key,
    required this.gateway,
    this.isMaintainer = false,
  });

  final StaffGateway gateway;
  final bool isMaintainer;

  @override
  State<ManagerHandoverPage> createState() => _ManagerHandoverPageState();
}

class _ManagerHandoverPageState extends State<ManagerHandoverPage> {
  late final Future<(StaffList, List<StaffListMember>)> _choices = _load();
  String? _successorId;
  bool _formerAdministrator = false;
  final Set<String> _formerSections = {};
  bool _saving = false;
  String? _error;

  Future<(StaffList, List<StaffListMember>)> _load() async {
    final (list, currentId) = await (
      widget.gateway.loadStaffList(),
      widget.gateway.currentAccess(),
    ).wait;
    final others = list.members
        .where((member) => member.id != currentId.ownStaffMemberId)
        .toList();
    final eligible = await Future.wait(
      others.map((member) => widget.gateway.canTransferManagerTo(member.id)),
    );
    final roles = widget.isMaintainer
        ? await Future.wait(
            others.map(
              (member) => widget.gateway.loadStaffMemberDetails(member.id),
            ),
          )
        : null;
    return (
      list,
      [
        for (var i = 0; i < others.length; i++)
          if (eligible[i] && (roles == null || !roles[i].grants.manager))
            others[i],
      ],
    );
  }

  Future<void> _transfer(List<StaffListMember> candidates) async {
    final successorId = _successorId;
    if (successorId == null || _saving) return;
    final successor = candidates.firstWhere(
      (member) => member.id == successorId,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transfer Manager?'),
        content: Text(
          widget.isMaintainer
              ? '${successor.displayName} will become Manager immediately. '
                    'The current Manager will become a Staff member.'
              : '${successor.displayName} will become Manager immediately. '
                    'Your Manager access will end. Your selected Staff access will remain. '
                    'The Maintainer hat is unchanged by this transfer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Transfer Manager'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.gateway.transferManagerWithAccess(
        successorId,
        _formerAdministrator,
        _formerSections,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not transfer Manager. Try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Transfer Manager')),
    body: FutureBuilder<(StaffList, List<StaffListMember>)>(
      future: _choices,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('Could not load eligible Staff members.'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final (list, candidates) = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Choose the next Manager'),
            const SizedBox(height: 8),
            if (candidates.isEmpty)
              const Text(
                'No eligible Staff member has accepted an Invite yet.',
              ),
            for (final member in candidates)
              ListTile(
                title: Text(member.displayName),
                leading: Icon(
                  _successorId == member.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                selected: _successorId == member.id,
                onTap: _saving
                    ? null
                    : () => setState(() => _successorId = member.id),
              ),
            const Divider(),
            if (!widget.isMaintainer) ...[
              const Text('Your Staff access after handover'),
              const Text(
                'Staff member is the default. Your Manager access ends.',
              ),
              CheckboxListTile(
                title: const Text('Administrator'),
                value: _formerAdministrator,
                onChanged: _saving
                    ? null
                    : (value) =>
                          setState(() => _formerAdministrator = value ?? false),
              ),
              const Text('Night scheduler Sections'),
              for (final section in list.sections)
                CheckboxListTile(
                  title: Text(section.name),
                  value: _formerSections.contains(section.id),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          if (value == true) {
                            _formerSections.add(section.id);
                          } else {
                            _formerSections.remove(section.id);
                          }
                        }),
                ),
              const SizedBox(height: 12),
              const Text(
                'This transfer does not grant, remove, or replace the '
                'database-bound Maintainer hat.',
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _successorId == null || _saving
                  ? null
                  : () => _transfer(candidates),
              child: Text(_saving ? 'Transferring…' : 'Transfer Manager'),
            ),
          ],
        );
      },
    ),
  );
}
