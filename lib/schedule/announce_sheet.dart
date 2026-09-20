import 'package:flutter/material.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'messages_composer.dart';

/// Lists each affected person's prefilled text, and a group text when more
/// than one person is affected. Returns true when the scheduler marks the
/// changes announced.
Future<bool?> showAnnounceSheet(
  BuildContext context, {
  required ChangeAnnouncement announcement,
  required MessagesComposer? messagesComposer,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _AnnounceSheet(
      announcement: announcement,
      messagesComposer: messagesComposer,
    ),
  );
}

class _AnnounceSheet extends StatelessWidget {
  const _AnnounceSheet({
    required this.announcement,
    required this.messagesComposer,
  });

  final ChangeAnnouncement announcement;
  final MessagesComposer? messagesComposer;

  Future<void> _open(
    BuildContext context,
    List<String> cellNumbers,
    String body,
  ) async {
    try {
      await messagesComposer!.open(cellNumbers, body);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Messages couldn't be opened.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupMessage = announcement.groupMessage;
    final groupRecipients = announcement.groupRecipients;
    final canText = messagesComposer != null;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      minChildSize: 0.4,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(
            'Announce changes',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          const Text(
            'Only the people whose own shifts changed are listed. '
            'Mark announced sends notifications; text anyone without them.',
          ),
          for (final person in announcement.people)
            _MessageCard(
              title: person.row.displayName,
              message: person.message,
              button: person.row.hasPushSubscription
                  ? const Text('Will be notified · no text needed')
                  : switch (person.cellNumber) {
                      null => const Text(
                        'Nobody will be told · no notification or cell number',
                      ),
                      final cellNumber => FilledButton.icon(
                        onPressed: canText
                            ? () => _open(context, [cellNumber], person.message)
                            : null,
                        icon: const Icon(Icons.sms_outlined),
                        label: Text('Text ${person.row.displayName}'),
                      ),
                    },
            ),
          if (groupMessage != null)
            _MessageCard(
              title: 'Or one group text',
              message: groupMessage,
              button: FilledButton.tonalIcon(
                onPressed: canText && groupRecipients.length > 1
                    ? () => _open(context, groupRecipients, groupMessage)
                    : null,
                icon: const Icon(Icons.groups_outlined),
                label: Text('Group text all ${groupRecipients.length}'),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Mark announced'),
          ),
          const SizedBox(height: 4),
          const Text(
            'This sends app notifications and clears the tray and highlights.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.title,
    required this.message,
    required this.button,
  });

  final String title;
  final String message;
  final Widget button;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(message),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft, child: button),
          ],
        ),
      ),
    );
  }
}
