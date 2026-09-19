import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'schedule_gateway.dart';

class MonthGridPage extends StatefulWidget {
  const MonthGridPage({
    super.key,
    required this.month,
    required this.sections,
    this.scheduleGateway,
    this.onSignOut,
    this.onManageStaff,
  });

  static Widget testable({
    required DateTime month,
    required List<ScheduleSection> sections,
    ScheduleGateway? scheduleGateway,
  }) {
    return MaterialApp(
      home: MonthGridPage(
        month: month,
        sections: sections,
        scheduleGateway: scheduleGateway,
      ),
    );
  }

  final DateTime month;
  final List<ScheduleSection> sections;
  final ScheduleGateway? scheduleGateway;
  final VoidCallback? onSignOut;
  final VoidCallback? onManageStaff;

  @override
  State<MonthGridPage> createState() => _MonthGridPageState();
}

class _MonthGridPageState extends State<MonthGridPage> {
  late DateTime _month = DateTime(widget.month.year, widget.month.month);
  late final Future<bool> _canEdit =
      widget.scheduleGateway?.canEditSchedule() ?? Future.value(false);
  late Future<_MonthView> _view = _loadView();

  /// Without a gateway the page shows the empty Sections at once.
  late final _MonthView? _emptyView = widget.scheduleGateway == null
      ? (
          month: _month,
          grid: MonthGrid(sections: widget.sections, cells: const []),
          canEdit: false,
        )
      : null;

  Future<_MonthView> _loadView() async {
    final gateway = widget.scheduleGateway;
    if (gateway == null) return _emptyView!;
    final month = _month;
    final grid = gateway.loadMonth(month);
    return (month: month, grid: await grid, canEdit: await _canEdit);
  }

  void _reload() {
    setState(() {
      _view = _loadView();
    });
  }

  void _moveMonth(int offset) {
    _month = DateTime(_month.year, _month.month + offset);
    _reload();
  }

  Future<void> _editCell(ScheduleRow row, DateTime day, String code) async {
    final newCode = await showDialog<String>(
      context: context,
      builder: (context) => _ShiftCodeDialog(
        title: '${row.displayName}, ${DateFormat.MMMd().format(day)}',
        initialCode: code,
      ),
    );
    if (newCode == null || !mounted) return;
    try {
      await widget.scheduleGateway!.saveCell(
        staffMemberId: row.staffMemberId,
        date: day,
        shiftCode: newCode,
      );
    } catch (_) {
      if (mounted) _showMessage('That change was not saved. Try again.');
      return;
    }
    _reload();
  }

  Future<void> _confirmMonth() async {
    final monthName = DateFormat.yMMMM().format(_month);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm $monthName?'),
        content: const Text(
          'This month then replaces your Excel file as the live Schedule.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.scheduleGateway!.confirmMonth(_month);
    } catch (_) {
      if (mounted) _showMessage('The month was not confirmed. Try again.');
      return;
    }
    _reload();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final days = List.generate(
      DateTime(_month.year, _month.month + 1, 0).day,
      (index) => DateTime(_month.year, _month.month, index + 1),
    );
    final canNavigate = widget.scheduleGateway != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat.yMMMM().format(_month)),
        actions: [
          if (canNavigate) ...[
            IconButton(
              tooltip: 'Previous month',
              onPressed: () => _moveMonth(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: () => _moveMonth(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
          if (widget.onManageStaff != null)
            IconButton(
              tooltip: 'Manage Staff list',
              onPressed: widget.onManageStaff,
              icon: const Icon(Icons.people_outline),
            ),
          if (widget.onSignOut != null)
            IconButton(
              tooltip: 'Sign out',
              onPressed: widget.onSignOut,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<_MonthView>(
          future: _view,
          initialData: _emptyView,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                child: Text('The Schedule could not be loaded.'),
              );
            }
            // A reload after an edit keeps the grid (and its scroll position)
            // on screen; a different month waits for its own data.
            final data = snapshot.data;
            if (data == null || data.month != _month) {
              return const Center(child: CircularProgressIndicator());
            }
            final (month: _, :grid, :canEdit) = data;
            final editable = canEdit && grid.started;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (canEdit && grid.awaitingConfirmation)
                  _ConfirmBanner(onConfirm: _confirmMonth),
                Expanded(
                  child: SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _DayHeader(days: days),
                          for (final section in grid.sections) ...[
                            _SectionBand(section: section, days: days),
                            for (final row in grid.rowsIn(section.id))
                              _StaffRow(
                                row: row,
                                days: days,
                                grid: grid,
                                onEdit: editable ? _editCell : null,
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

typedef _MonthView = ({DateTime month, MonthGrid grid, bool canEdit});

class _ConfirmBanner extends StatelessWidget {
  const _ConfirmBanner({required this.onConfirm});

  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Check this month against your Excel file. '
                'Tap any cell to correct it.',
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: onConfirm,
              child: const Text('Confirm month'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShiftCodeDialog extends StatefulWidget {
  const _ShiftCodeDialog({required this.title, required this.initialCode});

  final String title;
  final String initialCode;

  @override
  State<_ShiftCodeDialog> createState() => _ShiftCodeDialogState();
}

class _ShiftCodeDialogState extends State<_ShiftCodeDialog> {
  late final _controller = TextEditingController(text: widget.initialCode);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(labelText: 'Shift code'),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.days});

  final List<DateTime> days;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: _sectionWidth, height: _cellHeight),
        for (final day in days)
          Container(
            width: _dayWidth,
            height: _cellHeight,
            alignment: Alignment.center,
            decoration: _cellDecoration(day, context),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(DateFormat.E().format(day).substring(0, 1)),
                Text('${day.day}'),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionBand extends StatelessWidget {
  const _SectionBand({required this.section, required this.days});

  final ScheduleSection section;
  final List<DateTime> days;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: _sectionWidth,
          height: _cellHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            section.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        for (final day in days)
          Container(
            key: ValueKey(
              '${_isWeekend(day) ? 'weekend' : 'weekday'}-${_dayKey(day)}',
            ),
            width: _dayWidth,
            height: _cellHeight,
            decoration: _cellDecoration(day, context),
          ),
      ],
    );
  }
}

class _StaffRow extends StatelessWidget {
  const _StaffRow({
    required this.row,
    required this.days,
    required this.grid,
    required this.onEdit,
  });

  final ScheduleRow row;
  final List<DateTime> days;
  final MonthGrid grid;
  final void Function(ScheduleRow row, DateTime day, String code)? onEdit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: _sectionWidth,
          height: _cellHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Text(row.displayName, overflow: TextOverflow.ellipsis),
        ),
        for (final day in days)
          _codeCell(context, day, grid.shiftCodeFor(row.staffMemberId, day)),
      ],
    );
  }

  Widget _codeCell(BuildContext context, DateTime day, String? code) {
    final onEdit = this.onEdit;
    return InkWell(
      key: ValueKey('cell-${row.staffMemberId}-${_dayKey(day)}'),
      onTap: onEdit == null ? null : () => onEdit(row, day, code ?? ''),
      child: Container(
        width: _dayWidth,
        height: _cellHeight,
        alignment: Alignment.center,
        decoration: _cellDecoration(day, context),
        child: Text(
          code ?? '',
          style: const TextStyle(fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

String _dayKey(DateTime day) => DateFormat('yyyy-MM-dd').format(day);

BoxDecoration _cellDecoration(DateTime day, BuildContext context) {
  return BoxDecoration(
    color: _isWeekend(day)
        ? Theme.of(context).colorScheme.surfaceContainerHighest
        : Theme.of(context).colorScheme.surface,
    border: Border.all(color: Theme.of(context).dividerColor),
  );
}

bool _isWeekend(DateTime day) {
  return day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
}

const _sectionWidth = 180.0;
const _dayWidth = 48.0;
const _cellHeight = 58.0;
