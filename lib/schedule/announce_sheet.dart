import 'package:flutter/material.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'messages_composer.dart';

/// Lists each affected person's prefilled text, and a group text when more
/// than one person is affected. The returned IDs are the people whose Messages drafts
/// opened successfully; null means the sheet was dismissed.
Future<Set<String>?> showAnnounceSheet(
  BuildContext context, {
  required ChangeAnnouncement announcement,
  required MessagesComposer? messagesComposer,
}) {
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _AnnounceSheet(
      announcement: announcement,
      messagesComposer: messagesComposer,
    ),
  );
}

class _AnnounceSheet extends StatefulWidget {
  const _AnnounceSheet({
    required this.announcement,
    required this.messagesComposer,
  });

  final ChangeAnnouncement announcement;
  final MessagesComposer? messagesComposer;

  @override
  State<_AnnounceSheet> createState() => _AnnounceSheetState();
}

class _AnnounceSheetState extends State<_AnnounceSheet> {
  final Set<String> _draftOpenedStaffMemberIds = {};
  int _openingDrafts = 0;

  Future<void> _open(
    List<String> cellNumbers,
    String body,
    Iterable<String> staffMemberIds,
  ) async {
    setState(() => _openingDrafts++);
    try {
      await widget.messagesComposer!.open(cellNumbers, body);
      _draftOpenedStaffMemberIds.addAll(staffMemberIds);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Messages couldn't be opened.")),
      );
    } finally {
      if (mounted) setState(() => _openingDrafts--);
    }
  }

  @override
  Widget build(BuildContext context) {
    final announcement = widget.announcement;
    final groupMessage = announcement.groupMessage;
    final groupRecipients = announcement.groupRecipients;
    final canText = widget.messagesComposer != null;
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
                            ? () => _open(
                                [cellNumber],
                                person.message,
                                [person.row.staffMemberId],
                              )
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
                    ? () => _open(
                        groupRecipients,
                        groupMessage,
                        announcement.people
                            .where((person) =>
                                person.cellNumber != null &&
                                !person.row.hasPushSubscription)
                            .map((person) => person.row.staffMemberId),
                      )
                    : null,
                icon: const Icon(Icons.groups_outlined),
                label: Text('Group text all ${groupRecipients.length}'),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _openingDrafts == 0
                ? () => Navigator.of(context)
                    .pop(Set<String>.of(_draftOpenedStaffMemberIds))
                : null,
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
