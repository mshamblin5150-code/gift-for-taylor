import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

sealed class CellEdit {
  const CellEdit();
}

final class SaveCode extends CellEdit {
  const SaveCode(this.shiftCode);

  final String shiftCode;
}

final class UndoToPublished extends CellEdit {
  const UndoToPublished();
}

/// Offers the legend, a free-text Shift code, and undo when the cell has an
/// unannounced change ([publishedCode] is then its published value).
Future<CellEdit?> showCellEditSheet(
  BuildContext context, {
  required ScheduleRow row,
  required DateTime date,
  required String currentCode,
  required String? publishedCode,
  required List<LegendCode> codes,
}) {
  return showModalBottomSheet<CellEdit>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _CellEditSheet(
      row: row,
      date: date,
      currentCode: currentCode,
      publishedCode: publishedCode,
      codes: codes,
    ),
  );
}

class _CellEditSheet extends StatefulWidget {
  const _CellEditSheet({
    required this.row,
    required this.date,
    required this.currentCode,
    required this.publishedCode,
    required this.codes,
  });

  final ScheduleRow row;
  final DateTime date;
  final String currentCode;
  final String? publishedCode;
  final List<LegendCode> codes;

  @override
  State<_CellEditSheet> createState() => _CellEditSheetState();
}

class _CellEditSheetState extends State<_CellEditSheet> {
  final _otherCode = TextEditingController();

  @override
  void dispose() {
    _otherCode.dispose();
    super.dispose();
  }

  void _choose(String code) => Navigator.of(context).pop(SaveCode(code));

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final publishedCode = widget.publishedCode;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.row.displayName, style: textTheme.titleMedium),
            Text(
              '${DateFormat.MMMEd().format(widget.date)} · '
              'now ${widget.currentCode.isEmpty ? 'blank' : widget.currentCode}',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final legend in widget.codes)
                  SizedBox(
                    width: 96,
                    child: OutlinedButton(
                      onPressed: () => _choose(legend.code),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: Column(
                        children: [
                          Text(
                            legend.code,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            legend.hours ?? legend.meaning ?? '',
                            style: textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _otherCode,
                    decoration: const InputDecoration(
                      labelText: 'Other Shift code',
                    ),
                    textCapitalization: TextCapitalization.characters,
                    onSubmitted: (value) {
                      if (value.trim().isNotEmpty) _choose(value);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    if (_otherCode.text.trim().isNotEmpty) {
                      _choose(_otherCode.text);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (widget.currentCode.isNotEmpty)
                  TextButton(
                    onPressed: () => _choose(''),
                    child: const Text('Clear cell'),
                  ),
                if (publishedCode != null)
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pop(const UndoToPublished()),
                    icon: const Icon(Icons.undo),
                    label: Text(
                      publishedCode.isEmpty
                          ? 'Undo to blank'
                          : 'Undo to $publishedCode',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
