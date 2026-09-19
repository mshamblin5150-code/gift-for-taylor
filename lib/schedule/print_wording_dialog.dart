import 'package:flutter/material.dart';
import 'package:schedule_rules/schedule_rules.dart';

Future<PrintWording?> showPrintWordingDialog(
  BuildContext context,
  PrintWording current,
) => showDialog<PrintWording>(
  context: context,
  builder: (context) => _PrintWordingDialog(current: current),
);

class _PrintWordingDialog extends StatefulWidget {
  const _PrintWordingDialog({required this.current});
  final PrintWording current;

  @override
  State<_PrintWordingDialog> createState() => _PrintWordingDialogState();
}

class _PrintWordingDialogState extends State<_PrintWordingDialog> {
  late PrintTooltipStyle tooltip = widget.current.tooltip;
  late PrintTitleStyle title = widget.current.title;
  late PrintNoticeStyle notice = widget.current.notice;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Print wording'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'These choices apply to every month. Only approved Schedule wording can be used.',
          ),
          const SizedBox(height: 16),
          const Text('Print button tooltip'),
          DropdownButton<PrintTooltipStyle>(
            value: tooltip,
            isExpanded: true,
            items: [
              for (final choice in PrintTooltipStyle.values)
                DropdownMenuItem(value: choice, child: Text(choice.label)),
            ],
            onChanged: (choice) => setState(() => tooltip = choice ?? tooltip),
          ),
          const Text('Printed title'),
          DropdownButton<PrintTitleStyle>(
            value: title,
            isExpanded: true,
            items: [
              for (final choice in PrintTitleStyle.values)
                DropdownMenuItem(value: choice, child: Text(choice.label)),
            ],
            onChanged: (choice) => setState(() => title = choice ?? title),
          ),
          const Text('Printed notice'),
          DropdownButton<PrintNoticeStyle>(
            value: notice,
            isExpanded: true,
            items: [
              for (final choice in PrintNoticeStyle.values)
                DropdownMenuItem(
                  value: choice,
                  child: Text(
                    choice == PrintNoticeStyle.none
                        ? 'No notice'
                        : choice.label,
                  ),
                ),
            ],
            onChanged: (choice) => setState(() => notice = choice ?? notice),
          ),
          const SizedBox(height: 8),
          Text(
            'Example: ${PrintWording(title: title).titleFor(DateTime(2026, 9))}',
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
        onPressed: () => Navigator.pop(
          context,
          PrintWording(tooltip: tooltip, title: title, notice: notice),
        ),
        child: const Text('Save'),
      ),
    ],
  );
}
