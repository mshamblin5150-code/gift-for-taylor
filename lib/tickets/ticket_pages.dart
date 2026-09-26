import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'ticket_gateway.dart';
import 'ticket_session.dart';

class PutInTicketPage extends StatefulWidget {
  const PutInTicketPage({
    super.key,
    required this.gateway,
    required this.attachedContext,
    this.onAccessRejected,
  });

  final TicketGateway gateway;
  final TicketContext attachedContext;
  final VoidCallback? onAccessRejected;

  @override
  State<PutInTicketPage> createState() => _PutInTicketPageState();
}

class _PutInTicketPageState extends State<PutInTicketPage> {
  final _formKey = GlobalKey<FormState>();
  final _text = TextEditingController();
  late final TicketFormSession _session = TicketFormSession(
    widget.gateway,
    onAccessRejected: widget.onAccessRejected,
  );
  TicketKind? _kind;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    _session.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_session.state == TicketFormState.sending ||
        !_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _error = null);
    final outcome = await _session.putIn(
      kind: _kind!,
      text: _text.text,
      context: widget.attachedContext,
    );
    if (!mounted) return;
    switch (outcome) {
      case TicketSent():
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Ticket sent.')));
        }
      case TicketPutInRefused(:final reason):
        setState(() {
          _error = switch (reason) {
            TicketSubmissionRefusal.staffAccountRequired =>
              'A current Staff account is required.',
            TicketSubmissionRefusal.textInvalid =>
              'Write between 1 and 2000 characters.',
            TicketSubmissionRefusal.contextIncomplete => 'The attached context is incomplete. Reopen this form and try again.',
          };
        });
      case TicketPutInFailed():
        setState(() => _error = "The Ticket wasn't sent. Try again.");
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _session,
    builder: (context, _) {
      final sending = _session.state == TicketFormState.sending;
      return Scaffold(
        appBar: AppBar(title: const Text('Put in a ticket')),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<TicketKind>(
                  initialValue: _kind,
                  decoration: const InputDecoration(
                    labelText: 'Kind',
                    border: OutlineInputBorder(),
                  ),
                  hint: const Text('Choose a kind'),
                  items: [
                    for (final kind in TicketKind.values)
                      DropdownMenuItem(value: kind, child: Text(kind.label)),
                  ],
                  onChanged: sending
                      ? null
                      : (kind) => setState(() => _kind = kind),
                  validator: (kind) => kind == null ? 'Choose a kind.' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('ticket-text'),
                  controller: _text,
                  enabled: !sending && _kind != null,
                  decoration: const InputDecoration(
                    labelText: 'What would you like the Maintainer to know?',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  minLines: 5,
                  maxLines: 10,
                  maxLength: 2000,
                  inputFormatters: [LengthLimitingTextInputFormatter(2000)],
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Write something before sending.'
                      : null,
                ),
                const SizedBox(height: 8),
                Text(
                  'Attached context',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    ticketContextSummary(widget.attachedContext),
                    maxLines: 1,
                    key: const Key('ticket-attached-context'),
                  ),
                ),
                if (_error case final error?) ...[
                  const SizedBox(height: 12),
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: sending || _kind == null ? null : _send,
                  child: Text(sending ? 'Sending…' : 'Send Ticket'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class TicketsPage extends StatefulWidget {
  const TicketsPage({
    super.key,
    required this.gateway,
    required this.maintainer,
    this.ownStaffMemberId,
    this.onAccessRejected,
  }) : assert(maintainer || ownStaffMemberId != null);

  final TicketGateway gateway;
  final bool maintainer;
  final String? ownStaffMemberId;
  final VoidCallback? onAccessRejected;

  @override
  State<TicketsPage> createState() => _TicketsPageState();
}

class _TicketsPageState extends State<TicketsPage> {
  late final TicketsSession _session = TicketsSession(
    widget.gateway,
    maintainer: widget.maintainer,
    ownStaffMemberId: widget.ownStaffMemberId,
    onAccessRejected: widget.onAccessRejected,
  )..load();

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  Future<void> _open(Ticket ticket) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TicketDetailPage(
          gateway: widget.gateway,
          ticket: ticket,
          maintainer: widget.maintainer,
          onAccessRejected: widget.onAccessRejected,
        ),
      ),
    );
    if (mounted) _session.load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.maintainer ? 'Tickets' : 'My tickets')),
    body: ListenableBuilder(
      listenable: _session,
      builder: (context, _) => switch (_session.state) {
        TicketsLoading() => const Center(child: CircularProgressIndicator()),
        TicketsFailed() => Center(
          child: Text(
            widget.maintainer
                ? 'Could not load Tickets.'
                : 'Could not load My tickets.',
          ),
        ),
        TicketsLoaded(:final tickets) when tickets.isEmpty => Center(
          child: Text(
            widget.maintainer ? 'No Tickets yet.' : 'No tickets yet.',
          ),
        ),
        TicketsLoaded(:final tickets) => ListView(
          children: [
            for (final ticket in tickets)
              ListTile(
                key: Key('ticket-${ticket.id}'),
                title: Text(
                  widget.maintainer
                      ? '${ticket.senderDisplayName} · ${ticket.kind.label}'
                      : ticket.kind.label,
                ),
                subtitle: Text(
                  '${ticket.firstLine}\n'
                  '${DateFormat.yMMMd().format(ticket.createdAt.toLocal())} · '
                  '${ticket.state.label}'
                  '${widget.maintainer ? '\n${ticketContextSummary(ticket.context)}' : ''}',
                ),
                isThreeLine: widget.maintainer,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(ticket),
              ),
          ],
        ),
      },
    ),
  );
}

class TicketDetailPage extends StatefulWidget {
  const TicketDetailPage({
    super.key,
    required this.gateway,
    required this.ticket,
    required this.maintainer,
    this.onAccessRejected,
  });

  final TicketGateway gateway;
  final Ticket ticket;
  final bool maintainer;
  final VoidCallback? onAccessRejected;

  @override
  State<TicketDetailPage> createState() => _TicketDetailPageState();
}

class _TicketDetailPageState extends State<TicketDetailPage> {
  late final TicketDetailSession _session = TicketDetailSession(
    widget.gateway,
    widget.ticket,
    widget.maintainer,
    onAccessRejected: widget.onAccessRejected,
  )..load();

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ticket')),
    body: ListenableBuilder(
      listenable: _session,
      builder: (context, _) => switch (_session.state) {
        TicketDetailLoading() => const Center(
          child: CircularProgressIndicator(),
        ),
        TicketDetailFailed() => const Center(
          child: Text('Could not open this Ticket.'),
        ),
        TicketDetailLoaded(:final ticket) => SelectionArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                ticket.kind.label,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(ticket.state.label),
              if (widget.maintainer)
                Text('Sender: ${ticket.senderDisplayName}'),
              const SizedBox(height: 20),
              Text(
                'Ticket text',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(ticket.text),
              const SizedBox(height: 20),
              Text(
                'Attached context',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text('Screen: ${ticket.context.screen}'),
              Text(
                'Month: ${ticket.context.month == null ? 'None' : DateFormat.yMMMM().format(ticket.context.month!)}',
              ),
              Text('Release: ${ticket.context.release}'),
              Text('Device/browser: ${ticket.context.device}'),
              Text(
                'Time: ${DateFormat.yMMMd().add_jm().format(ticket.context.capturedAt.toLocal())}',
              ),
            ],
          ),
        ),
      },
    ),
  );
}

String ticketContextSummary(TicketContext context) => [
  context.screen,
  if (context.month case final month?) DateFormat.yMMMM().format(month),
  'release ${context.release}',
  context.device,
  DateFormat.yMMMd().add_jm().format(context.capturedAt.toLocal()),
].join(' · ');
