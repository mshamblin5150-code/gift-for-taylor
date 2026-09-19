import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'request_off_mail.dart';

class RequestsOffPage extends StatefulWidget {
  const RequestsOffPage({
    super.key,
    required this.rules,
    required this.isManager,
  });

  final ScheduleRules rules;
  final bool isManager;

  @override
  State<RequestsOffPage> createState() => _RequestsOffPageState();
}

class _RequestsOffPageState extends State<RequestsOffPage> {
  List<RequestOff>? _requests;
  Object? _error;
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    _openPage();
  }

  Future<void> _openPage() async {
    try {
      await widget.rules.acknowledgeRequestOffNotices();
    } catch (_) {
      // The queue and history are still useful if acknowledging fails.
    }
    await _reload();
  }

  Future<void> _reload() async {
    try {
      final requests = widget.isManager
          ? _showHistory
                ? await widget.rules.requestOffHistory()
                : await widget.rules.approvalQueue()
          : await widget.rules.myRequestsOff();
      if (mounted) {
        setState(() {
          _requests = requests;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _newRequest() async {
    final dates = <DateTime>{};
    final reason = TextEditingController();
    final draft = await showDialog<RequestOffDraft>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Request off'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 6,
                  children: [
                    for (final date in dates.toList()..sort())
                      InputChip(
                        label: Text(DateFormat.yMMMd().format(date)),
                        onDeleted: () => refresh(() => dates.remove(date)),
                      ),
                  ],
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add a day'),
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 365),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 730)),
                    );
                    if (date != null) refresh(() => dates.add(date));
                  },
                ),
                TextField(
                  controller: reason,
                  decoration: const InputDecoration(
                    labelText: 'Reason (optional)',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: dates.isEmpty
                  ? null
                  : () => Navigator.pop(
                      context,
                      RequestOffDraft(
                        dates: dates.toList(),
                        reason: reason.text,
                      ),
                    ),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    reason.dispose();
    if (draft == null) return;
    try {
      final email = await widget.rules.requestOff(draft);
      await _reload();
      await openRequestOffMail(email);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Check your Request off. If it appears below, open your email app to send the copy.',
          ),
        ),
      );
    }
  }

  Future<void> _decide(RequestOff request, RequestOffDecision decision) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '${decision == RequestOffDecision.approved ? 'Approve' : 'Decline'} Request off?',
        ),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: 'Reason (optional)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    final explanation = reason.text;
    reason.dispose();
    if (confirmed != true) return;
    try {
      await widget.rules.decideRequestOff(
        request.id,
        decision,
        reason: explanation,
      );
      await _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The decision was not saved. Check that the Schedule month is started.',
          ),
        ),
      );
    }
  }

  Future<void> _confirmEmail(RequestOff request) async {
    try {
      await widget.rules.confirmRequestOffEmail(request.id);
      await _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email confirmation was not saved.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.isManager
            ? (_showHistory
                  ? 'Requests off history'
                  : 'Request off approval queue')
            : 'My Requests off',
      ),
      actions: widget.isManager
          ? [
              TextButton(
                onPressed: () {
                  setState(() {
                    _showHistory = !_showHistory;
                    _requests = null;
                  });
                  _reload();
                },
                child: Text(_showHistory ? 'Pending' : 'History'),
              ),
            ]
          : null,
    ),
    floatingActionButton: widget.isManager
        ? null
        : FloatingActionButton.extended(
            onPressed: _newRequest,
            icon: const Icon(Icons.add),
            label: const Text('Request off'),
          ),
    body: _error != null
        ? Center(child: Text('Requests off could not be loaded.'))
        : _requests == null
        ? const Center(child: CircularProgressIndicator())
        : _requests!.isEmpty
        ? Center(
            child: Text(
              widget.isManager
                  ? 'No pending Requests off.'
                  : 'No Requests off yet.',
            ),
          )
        : ListView(
            children: [
              for (final request in _requests!)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.isManager)
                          Text(
                            request.staffMemberName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        Text(
                          request.dates
                              .map((date) => DateFormat.yMMMd().format(date))
                              .join(', '),
                        ),
                        if (request.reason != null &&
                            request.reason!.isNotEmpty)
                          Text('Reason: ${request.reason}'),
                        Text(
                          'Submitted ${DateFormat.yMMMd().add_jm().format(request.submittedAt)}',
                        ),
                        Text(
                          request.emailCopyConfirmed
                              ? 'Email copy confirmed'
                              : 'email copy not confirmed',
                        ),
                        if (!widget.isManager || _showHistory) ...[
                          Text('Decision: ${request.decision.name}'),
                          if (request.decisionReason != null)
                            Text('Manager reason: ${request.decisionReason}'),
                          if (request.decidedAt != null)
                            Text(
                              'Decided ${DateFormat.yMMMd().add_jm().format(request.decidedAt!)}',
                            ),
                        ],
                        if (!widget.isManager) ...[
                          if (!request.emailCopyConfirmed)
                            TextButton(
                              onPressed: () => _confirmEmail(request),
                              child: const Text('I sent the email copy'),
                            ),
                        ],
                        if (widget.isManager &&
                            request.decision == RequestOffDecision.pending)
                          Row(
                            children: [
                              TextButton(
                                onPressed: () => _decide(
                                  request,
                                  RequestOffDecision.declined,
                                ),
                                child: const Text('Decline'),
                              ),
                              FilledButton(
                                onPressed: () => _decide(
                                  request,
                                  RequestOffDecision.approved,
                                ),
                                child: const Text('Approve'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
  );
}
