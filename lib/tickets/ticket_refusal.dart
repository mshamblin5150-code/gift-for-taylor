import 'package:flutter/material.dart';

import 'ticket_activity.dart';

export 'ticket_refusal_context.dart';

const putRefusalInTicketLabel = 'Put in a ticket about this';

class TicketRefusalButton extends StatelessWidget {
  const TicketRefusalButton({
    super.key,
    required this.refusal,
    this.onAccessRejected,
  });

  final TicketRefusalContext refusal;
  final VoidCallback? onAccessRejected;

  @override
  Widget build(BuildContext context) {
    final launcher = TicketLauncherScope.maybeOf(context);
    if (launcher == null) return const SizedBox.shrink();
    return TextButton(
      onPressed: () => launcher.openRefusal(
        context,
        refusal: refusal,
        onAccessRejected: onAccessRejected,
      ),
      child: const Text(putRefusalInTicketLabel),
    );
  }
}

SnackBar mappedRefusalSnackBar(
  BuildContext context, {
  required String message,
  required TicketRefusalContext refusal,
  VoidCallback? onAccessRejected,
}) {
  final launcher = TicketLauncherScope.maybeOf(context);
  return SnackBar(
    content: Text(message),
    action: launcher == null
        ? null
        : SnackBarAction(
            label: putRefusalInTicketLabel,
            onPressed: () => launcher.openRefusal(
              context,
              refusal: refusal,
              onAccessRejected: onAccessRejected,
            ),
          ),
  );
}

void recordTicketScreenVisit(BuildContext context, String screen) =>
    TicketLauncherScope.maybeOf(context)?.actions.screenVisited(screen);
