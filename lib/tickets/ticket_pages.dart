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
                  '${widget.maintainer && ticket.hasNewReply ? ' · New reply' : ''}'
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
  final _question = TextEditingController();
  final _suggestedAnswer = TextEditingController();
  final _answer = TextEditingController();
  String? _threadError;
  late final TicketDetailSession _session = TicketDetailSession(
    widget.gateway,
    widget.ticket,
    widget.maintainer,
    onAccessRejected: widget.onAccessRejected,
  )..load();

  @override
  void dispose() {
    _question.dispose();
    _suggestedAnswer.dispose();
    _answer.dispose();
    _session.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    if (_question.text.trim().isEmpty) return;
    setState(() => _threadError = null);
    final outcome = await _session.askQuestion(
      question: _question.text.trim(),
      suggestedAnswer: _suggestedAnswer.text.trim().isEmpty
          ? null
          : _suggestedAnswer.text.trim(),
    );
    if (!mounted) return;
    switch (outcome) {
      case TicketThreadCommandCompleted():
        _question.clear();
        _suggestedAnswer.clear();
      case TicketThreadCommandRefused(:final reason):
        setState(() => _threadError = _threadRefusalMessage(reason));
      case TicketThreadCommandFailed():
        setState(() => _threadError = 'The question was not sent. Try again.');
    }
  }

  Future<void> _answerQuestion(
    TicketThreadEntry question, {
    required bool acceptSuggestion,
  }) async {
    if (!acceptSuggestion && _answer.text.trim().isEmpty) return;
    setState(() => _threadError = null);
    final outcome = await _session.answerQuestion(
      question.id,
      answer: acceptSuggestion ? null : _answer.text.trim(),
      acceptSuggestion: acceptSuggestion,
    );
    if (!mounted) return;
    switch (outcome) {
      case TicketThreadCommandCompleted():
        _answer.clear();
      case TicketThreadCommandRefused(:final reason):
        setState(() => _threadError = _threadRefusalMessage(reason));
      case TicketThreadCommandFailed():
        setState(() => _threadError = 'The answer was not sent. Try again.');
    }
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
        TicketDetailLoaded(:final ticket, :final thread, :final working) =>
          SelectionArea(
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
                const SizedBox(height: 24),
                Text(
                  'Private thread',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text('Questions asked: ${ticket.questionCount} of 2'),
                if (ticket.questionCount >= 2)
                  const Text(
                    'Two questions have already been asked. Ask in person if more is needed.',
                  ),
                const SizedBox(height: 12),
                if (thread.isEmpty) const Text('No questions yet.'),
                for (final entry in thread) ...[
                  Text(
                    entry.author == TicketThreadAuthor.maintainer
                        ? 'Maintainer'
                        : ticket.senderDisplayName,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(entry.text),
                  if (entry.suggestedAnswer case final suggestion?)
                    Text('Suggested answer: $suggestion'),
                  const SizedBox(height: 12),
                ],
                if (widget.maintainer && ticket.state == TicketState.seen) ...[
                  TextField(
                    key: const Key('ticket-question'),
                    controller: _question,
                    enabled: !working,
                    maxLength: 1000,
                    decoration: InputDecoration(
                      labelText: 'Question for the sender',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('ticket-suggested-answer'),
                    controller: _suggestedAnswer,
                    enabled: !working,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'Suggested answer (optional)',
                      helperText: 'The sender can confirm this with one tap.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  FilledButton(
                    onPressed: working ? null : _ask,
                    child: const Text('Ask sender'),
                  ),
                ] else if (widget.maintainer &&
                    ticket.state == TicketState.waitingOnSender) ...[
                  const Text("Waiting for the sender's answer."),
                ] else if (_pendingQuestion(thread) case final pending?
                    when ticket.state == TicketState.waitingOnSender) ...[
                  if (pending.suggestedAnswer != null)
                    FilledButton(
                      key: const Key('ticket-answer-yes'),
                      onPressed: working
                          ? null
                          : () => _answerQuestion(
                              pending,
                              acceptSuggestion: true,
                            ),
                      child: const Text('Yes'),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('ticket-answer'),
                    controller: _answer,
                    enabled: !working,
                    maxLength: 1000,
                    decoration: InputDecoration(
                      labelText: pending.suggestedAnswer == null
                          ? 'Your answer'
                          : 'No, it was…',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  FilledButton(
                    onPressed: working
                        ? null
                        : () =>
                              _answerQuestion(pending, acceptSuggestion: false),
                    child: const Text('Send answer'),
                  ),
                ],
                if (_threadError case final error?) ...[
                  const SizedBox(height: 8),
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
      },
    ),
  );
}

TicketThreadEntry? _pendingQuestion(List<TicketThreadEntry> thread) {
  final answered = {for (final entry in thread) ?entry.replyToId};
  for (final entry in thread.reversed) {
    if (entry.author == TicketThreadAuthor.maintainer &&
        !answered.contains(entry.id)) {
      return entry;
    }
  }
  return null;
}

String _threadRefusalMessage(TicketThreadRefusal reason) => switch (reason) {
  TicketThreadRefusal.questionInvalid =>
    'Write a question between 1 and 1000 characters.',
  TicketThreadRefusal.ticketNotReady =>
    'Wait for the sender to answer before asking another question.',
  TicketThreadRefusal.answerInvalid =>
    'Write an answer between 1 and 1000 characters.',
  TicketThreadRefusal.questionNotWaiting =>
    'This question is no longer waiting for an answer.',
};

String ticketContextSummary(TicketContext context) => [
  context.screen,
  if (context.month case final month?) DateFormat.yMMMM().format(month),
  'release ${context.release}',
  context.device,
  DateFormat.yMMMd().add_jm().format(context.capturedAt.toLocal()),
].join(' · ');
