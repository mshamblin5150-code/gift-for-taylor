import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'undelivered_invitation_log.dart';
import 'undelivered_invitations_session.dart';

class UndeliveredInvitationsPage extends StatefulWidget {
  const UndeliveredInvitationsPage({super.key, required this.log});

  final UndeliveredInvitationLog log;

  @override
  State<UndeliveredInvitationsPage> createState() =>
      _UndeliveredInvitationsPageState();
}

class _UndeliveredInvitationsPageState
    extends State<UndeliveredInvitationsPage> {
  late final UndeliveredInvitationsSession _session =
      UndeliveredInvitationsSession(widget.log)..load();

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Undelivered invitations')),
    body: ListenableBuilder(
      listenable: _session,
      builder: (context, _) => switch (_session.state) {
        UndeliveredInvitationsLoading() => const Center(
          child: CircularProgressIndicator(),
        ),
        UndeliveredInvitationsFailed() => const Center(
          child: Text('Could not load Undelivered invitations.'),
        ),
        UndeliveredInvitationsLoaded(:final invitations)
            when invitations.isEmpty =>
          const Center(child: Text('No Undelivered invitations.')),
        UndeliveredInvitationsLoaded(:final invitations) => ListView(
          children: [
            for (final invitation in invitations)
              ListTile(
                title: Text(
                  '${invitation.staffDisplayName} · '
                  '${DateFormat.yMMMd().format(invitation.workDate)} · '
                  '${invitation.shiftCode}',
                ),
                subtitle: Text(_details(invitation)),
                isThreeLine: true,
              ),
          ],
        ),
      },
    ),
  );

  String _details(UndeliveredInvitation invitation) {
    final attempts = invitation.deliveryAttempts == 1
        ? '1 attempt'
        : '${invitation.deliveryAttempts} attempts';
    final status = [
      invitation.errorCode,
      if (invitation.statusCode case final code?) 'SMTP $code',
    ].whereType<String>().join(' · ');
    return '$attempts · failed '
        '${DateFormat.yMMMd().add_jm().format(invitation.failedAt.toLocal())}'
        '\n${invitation.recipient} · ${invitation.method}'
        '${status.isEmpty ? '' : '\n$status'}'
        '\n${invitation.errorMessage}';
  }
}
