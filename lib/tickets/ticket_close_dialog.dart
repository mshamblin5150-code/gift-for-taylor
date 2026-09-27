import 'package:flutter/material.dart';

import 'ticket_gateway.dart';

Future<String?> showTicketCloseReasonDialog(
  BuildContext context,
  TicketState outcome,
) {
  final formKey = GlobalKey<FormState>();
  var value = '';
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Close as ${outcome.label}'),
      content: SingleChildScrollView(
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                outcome == TicketState.done
                    ? 'Use Done only when the fix is live in a release, not when its pull request merges.'
                    : 'Explain in plain language why this Ticket will not be done.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('ticket-close-reason'),
                onChanged: (next) => value = next,
                decoration: const InputDecoration(
                  labelText: 'Reason for the sender',
                  border: OutlineInputBorder(),
                ),
                maxLength: 1000,
                minLines: 3,
                maxLines: 6,
                validator: (candidate) => (candidate?.trim().isEmpty ?? true)
                    ? 'Reason for the sender is required.'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(dialogContext, value.trim());
            }
          },
          child: const Text('Close Ticket'),
        ),
      ],
    ),
  );
}
