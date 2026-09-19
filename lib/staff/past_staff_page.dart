import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'invite_composer.dart';
import 'staff_dialogs.dart';
import 'staff_gateway.dart';

/// Everyone who has left, from which the Manager reactivates a returning
/// person.
class PastStaffPage extends StatefulWidget {
  const PastStaffPage({
    super.key,
    required this.gateway,
    required this.rules,
    required this.inviteComposer,
    required this.sections,
  });

  final StaffGateway gateway;
  final ScheduleRules rules;
  final InviteComposer inviteComposer;
  final List<StaffSection> sections;

  @override
  State<PastStaffPage> createState() => _PastStaffPageState();
}

class _PastStaffPageState extends State<PastStaffPage> {
  List<PastStaffMember>? _pastStaff;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final pastStaff = await widget.gateway.loadPastStaff();
      if (mounted) {
        setState(() {
          _pastStaff = pastStaff;
          _loadError = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  Future<void> _reactivate(PastStaffMember member) async {
    if (widget.sections.isEmpty) return;
    final reactivation = await showDialog<Reactivation>(
      context: context,
      builder: (context) =>
          ReactivateDialog(member: member, sections: widget.sections),
    );
    if (reactivation == null) return;
    try {
      await widget.rules.reactivate(
        Reactivate(
          staffMemberId: member.id,
          sectionId: reactivation.sectionId,
          firstDay: reactivation.firstDay,
        ),
      );
    } catch (error) {
      if (mounted) _showError('Could not reactivate ${member.displayName}.');
      return;
    }
    await _load();
    try {
      final invite = await widget.gateway.resendInvite(member.id);
      await widget.inviteComposer.open(invite);
    } catch (error) {
      if (mounted) {
        _showError(
          '${member.displayName} is back on the Staff list. '
          'Resend their Invite from there.',
        );
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Past staff')),
      body: switch ((_pastStaff, _loadError)) {
        (_, Object()) => const Center(
          child: Text('Could not load past staff.'),
        ),
        (null, _) => const Center(child: CircularProgressIndicator()),
        (final List<PastStaffMember> pastStaff, _) when pastStaff.isEmpty =>
          const Center(child: Text('No one has left yet.')),
        (final List<PastStaffMember> pastStaff, _) => ListView(
          children: [
            for (final member in pastStaff)
              ListTile(
                title: Text(member.displayName),
                subtitle: Text(
                  member.lastDay == null
                      ? 'Deactivated'
                      : 'Last day ${DateFormat.yMMMd().format(member.lastDay!)}',
                ),
                trailing: TextButton(
                  onPressed: () => _reactivate(member),
                  child: const Text('Reactivate'),
                ),
              ),
          ],
        ),
      },
    );
  }
}
