import 'package:flutter/material.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'ticket_activity.dart';

const putRefusalInTicketLabel = 'Put in a ticket about this';

enum TicketScreen {
  schedule('Schedule'),
  swaps('Swaps'),
  staffList('Staff list'),
  staffDetails('Staff details'),
  shiftCodes('Shift codes'),
  managerHandover('Transfer Manager'),
  approvalQueue('Approval queue'),
  acceptInvite('Accept Invite');

  const TicketScreen(this.label);

  final String label;
}

class TicketScope extends StatefulWidget {
  const TicketScope({
    super.key,
    required this.screen,
    required this.child,
    this.month,
    this.onAccessRejected,
  });

  final TicketScreen screen;
  final DateTime? month;
  final VoidCallback? onAccessRejected;
  final Widget child;

  static _TicketScopeState _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TicketScopeData>()!.state;

  @override
  State<TicketScope> createState() => _TicketScopeState();
}

final class _TicketScopeState extends State<TicketScope> {
  TicketLauncher? _launcher;
  bool _visitRecorded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _launcher = TicketLauncherScope.maybeOf(context);
    if (!_visitRecorded && _launcher != null) {
      final launcher = _launcher!;
      launcher.actions.screenVisited(widget.screen.label);
      _visitRecorded = true;
    }
  }

  void openRefusal(Refusal refusal) => _launcher?.openRefusal(
    context,
    refusal: refusal,
    screen: widget.screen.label,
    month: widget.month,
    onAccessRejected: widget.onAccessRejected,
  );

  @override
  Widget build(BuildContext context) =>
      _TicketScopeData(state: this, child: widget.child);
}

final class _TicketScopeData extends InheritedTheme {
  const _TicketScopeData({required this.state, required super.child});

  final _TicketScopeState state;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      _TicketScopeData(state: state, child: child);

  @override
  bool updateShouldNotify(_TicketScopeData oldWidget) => true;
}

void showRefusal(BuildContext context, Refusal refusal, String sentence) {
  final scope = TicketScope._of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(sentence),
      action: scope._launcher == null
          ? null
          : SnackBarAction(
              label: putRefusalInTicketLabel,
              onPressed: () => scope.openRefusal(refusal),
            ),
    ),
  );
}

class RefusalTicketButton extends StatelessWidget {
  const RefusalTicketButton(this.refusal, {super.key});

  final Refusal refusal;

  @override
  Widget build(BuildContext context) {
    final scope = TicketScope._of(context);
    if (scope._launcher == null) return const SizedBox.shrink();
    return TextButton(
      onPressed: () => scope.openRefusal(refusal),
      child: const Text(putRefusalInTicketLabel),
    );
  }
}
