import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late final tooltip = TextEditingController(text: widget.current.tooltip);
  late final title = TextEditingController(text: widget.current.title);
  late final notice = TextEditingController(text: widget.current.notice);
  String? error;

  @override
  void dispose() {
    tooltip.dispose();
    title.dispose();
    notice.dispose();
    super.dispose();
  }

  void save() {
    final required = title.text.trim().isEmpty || tooltip.text.trim().isEmpty;
    final tooLong = [
      tooltip,
      title,
      notice,
    ].any((field) => field.text.runes.length > 80);
    if (required || tooLong) {
      setState(
        () => error = [
          if (required) 'The title and tooltip are required.',
          if (tooLong) 'Each field must be 80 characters or fewer.',
        ].join(' '),
      );
      return;
    }
    Navigator.pop(
      context,
      PrintWording(
        tooltip: tooltip.text,
        title: title.text,
        notice: notice.text,
      ),
    );
  }

  Widget wordingField(
    String label,
    TextEditingController controller,
    String defaultText,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        maxLength: 80,
        maxLengthEnforcement: MaxLengthEnforcement.none,
        buildCounter:
            (context, {required currentLength, required isFocused, maxLength}) {
              final length = controller.text.runes.length;
              return length < 60 ? null : Text('$length/80');
            },
        onChanged: (_) => setState(() => error = null),
      ),
      TextButton(
        onPressed: () => setState(() {
          controller.text = defaultText;
          error = null;
        }),
        child: Text('Reset $label to default'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Print wording'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('These choices apply to every month.'),
          const SizedBox(height: 16),
          wordingField(
            'Print button tooltip',
            tooltip,
            PrintTooltipStyle.bookPage.label,
          ),
          wordingField('Printed title', title, PrintTitleStyle.hospital.label),
          wordingField(
            'Printed notice',
            notice,
            PrintNoticeStyle.subjectToChange.label,
          ),
          const SizedBox(height: 8),
          Text(
            'Example: ${PrintWording(title: title.text).titleFor(DateTime(2026, 9))}',
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: save, child: const Text('Save')),
    ],
  );
}
