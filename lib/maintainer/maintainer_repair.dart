import 'package:flutter/material.dart';
import 'package:schedule_rules/schedule_rules.dart';

import '../tickets/ticket_close_dialog.dart';
import '../tickets/ticket_gateway.dart';
import 'repair_controller.dart';

class MaintainerRepairPage extends StatefulWidget {
  const MaintainerRepairPage({
    super.key,
    required this.controller,
    this.ticketGateway,
  });

  final RepairController controller;
  final TicketGateway? ticketGateway;

  @override
  State<MaintainerRepairPage> createState() => _MaintainerRepairPageState();
}

class _MaintainerRepairPageState extends State<MaintainerRepairPage> {
  final _detail = TextEditingController();
  RepairReasonCategory? _category;
  bool _opening = false;
  String? _error;
  String? _ticketId;
  late final Future<List<Ticket>> _tickets =
      widget.ticketGateway?.readForMaintainer() ?? Future.value(const []);

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  bool get _valid {
    final detail = _detail.text.trim();
    return _category != null &&
        (detail.isEmpty || detail.length >= 3) &&
        (_category != RepairReasonCategory.somethingElse || detail.length >= 3);
  }

  Future<void> _open() async {
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final detail = _detail.text.trim();
      await widget.controller.open(
        _category!,
        detail.isEmpty ? null : detail,
        ticketId: _ticketId,
      );
      if (mounted) Navigator.maybePop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _opening = false;
          _error = 'The Repair could not be opened.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Maintainer repairs')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Break the glass',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose the work you need to repair. Manager controls remain hidden '
          'until this recorded Repair opens, and close again within one hour.',
        ),
        const SizedBox(height: 16),
        if (widget.ticketGateway != null) ...[
          FutureBuilder<List<Ticket>>(
            future: _tickets,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text('Tickets could not be loaded.');
              }
              if (!snapshot.hasData) {
                return const LinearProgressIndicator();
              }
              final tickets = snapshot.data!
                  .where(
                    (ticket) =>
                        ticket.state != TicketState.done &&
                        ticket.state != TicketState.wontDo,
                  )
                  .toList();
              return DropdownButtonFormField<String>(
                initialValue: _ticketId,
                decoration: const InputDecoration(
                  labelText: 'Ticket cause (optional)',
                ),
                hint: const Text('No Ticket'),
                items: [
                  for (final ticket in tickets)
                    DropdownMenuItem(
                      value: ticket.id,
                      child: Text(
                        '${ticket.kind.label} · ${ticket.firstLine}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _opening
                    ? null
                    : (value) => setState(() => _ticketId = value),
              );
            },
          ),
          if (_ticketId != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _opening
                    ? null
                    : () => setState(() => _ticketId = null),
                child: const Text('Use no Ticket'),
              ),
            ),
          const SizedBox(height: 16),
        ],
        for (final category in RepairReasonCategory.values)
          ListTile(
            leading: Icon(
              _category == category
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(category.label),
            subtitle: Text(_description(category)),
            selected: _category == category,
            onTap: _opening ? null : () => setState(() => _category = category),
          ),
        TextField(
          controller: _detail,
          enabled: !_opening,
          maxLength: 240,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: _category == RepairReasonCategory.somethingElse
                ? 'Detail (required)'
                : 'Detail (optional)',
          ),
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _opening || !_valid ? null : _open,
          child: const Text('Break the glass'),
        ),
      ],
    ),
  );
}

String _description(RepairReasonCategory category) => switch (category) {
  RepairReasonCategory.managerHandover =>
    'A handover refused or only partly applied.',
  RepairReasonCategory.scheduleOrMonth =>
    'A Schedule or Month state the Manager cannot correct.',
  RepairReasonCategory.unitSettings =>
    'Sections, Shift codes, Staffing minimums, or Coverage windows.',
  RepairReasonCategory.staffOrInvite =>
    'A Staff record or Invite that will not accept.',
  RepairReasonCategory.investigation =>
    'Investigate a fault without intending a change.',
  RepairReasonCategory.somethingElse =>
    'A visibly distinct reason that requires written detail.',
};

class RepairBanner extends StatelessWidget {
  const RepairBanner({
    super.key,
    required this.controller,
    this.ticketGateway,
    this.onClosed,
  });

  final RepairController controller;
  final TicketGateway? ticketGateway;
  final VoidCallback? onClosed;

  Future<void> _close(BuildContext context) async {
    final repair = controller.repair;
    if (repair == null) return;
    if (repair.ticketId != null && ticketGateway != null) {
      late final List<Ticket> tickets;
      try {
        tickets = await ticketGateway!.readForMaintainer();
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('The linked Ticket could not be loaded.'),
            ),
          );
        }
        return;
      }
      final linked = tickets.where((ticket) => ticket.id == repair.ticketId);
      if (linked.isNotEmpty &&
          linked.single.state != TicketState.done &&
          linked.single.state != TicketState.wontDo) {
        if (!context.mounted) return;
        final closeTicket = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Close linked Ticket?'),
            content: const Text(
              'This Repair was prompted by a Ticket. You can close the Repair '
              'alone, or also close that Ticket as Done.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Keep Repair open'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Close Repair only'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Close Ticket as Done'),
              ),
            ],
          ),
        );
        if (closeTicket == null) return;
        if (closeTicket) {
          if (!context.mounted) return;
          final reason = await showTicketCloseReasonDialog(
            context,
            TicketState.done,
          );
          if (reason == null) return;
          try {
            await ticketGateway!.close(
              repair.ticketId!,
              outcome: TicketState.done,
              reason: reason,
            );
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'The Ticket could not be closed. The Repair remains open.',
                  ),
                ),
              );
            }
            return;
          }
        }
      }
    }
    await controller.close();
    onClosed?.call();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final repair = controller.repair;
      if (repair == null) return const SizedBox.shrink();
      final colors = Theme.of(context).colorScheme;
      return ColoredBox(
        color: colors.tertiaryContainer,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Icon(Icons.build_outlined, color: colors.onTertiaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Repairing: ${repair.category.label}',
                    style: TextStyle(color: colors.onTertiaryContainer),
                  ),
                ),
                TextButton(
                  onPressed: () => _close(context),
                  child: const Text('Close this repair'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
