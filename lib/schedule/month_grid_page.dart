import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'announce_sheet.dart';
import 'cell_edit_sheet.dart';
import 'change_log_page.dart';
import 'messages_composer.dart';
import 'night_scheduler_page.dart';

enum ScheduleView { month, day, person }

class MonthGridPage extends StatefulWidget {
  const MonthGridPage({
    super.key,
    required this.rules,
    required this.month,
    this.onSignOut,
    this.onManageStaff,
    this.messagesComposer,
    this.printBookPage,
  });

  final ScheduleRules rules;
  final DateTime month;
  final VoidCallback? onSignOut;
  final VoidCallback? onManageStaff;
  final MessagesComposer? messagesComposer;

  /// Prints a Schedule book page, given as an HTML document.
  final ValueChanged<String>? printBookPage;

  @override
  State<MonthGridPage> createState() => _MonthGridPageState();
}

class _MonthGridPageState extends State<MonthGridPage> {
  late DateTime _month = DateTime(widget.month.year, widget.month.month);
  StreamSubscription<void>? _updates;
  MonthGrid? _grid;
  ChangeAnnouncement? _announcement;

  /// The Manager: may confirm the month and manage the Night scheduler.
  bool _canEdit = false;
  EditableSections _editable = const EditableSections.only({});
  Object? _loadError;
  ScheduleView _view = ScheduleView.month;
  late DateTime _day = _defaultDay();
  String? _personId;

  @override
  void initState() {
    super.initState();
    _listen();
    _load();
  }

  void _listen() {
    _updates?.cancel();
    _updates = widget.rules.monthUpdates(_month).listen((_) => _reload());
  }

  void _goToMonth(int offset) {
    setState(() {
      _month = DateTime(_month.year, _month.month + offset);
      _grid = null;
      _loadError = null;
      _day = _defaultDay();
    });
    _listen();
    _load();
  }

  @override
  void dispose() {
    _updates?.cancel();
    super.dispose();
  }

  DateTime _defaultDay() {
    final now = DateTime.now();
    return now.year == _month.year && now.month == _month.month
        ? DateTime(now.year, now.month, now.day)
        : _month;
  }

  Future<void> _load() async {
    try {
      final month = _month;
      final (canEdit, editable) = await (
        widget.rules.canEditSchedule(),
        widget.rules.editableSections(),
      ).wait;
      final (grid, announcement) = await _read(month, editable);
      if (!mounted || month != _month) return;
      setState(() {
        _canEdit = canEdit;
        _editable = editable;
        _grid = grid;
        _announcement = announcement;
        _loadError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  Future<void> _reload() async {
    try {
      final month = _month;
      final (grid, announcement) = await _read(month, _editable);
      if (!mounted || month != _month) return;
      setState(() {
        _grid = grid;
        _announcement = announcement;
      });
    } catch (_) {
      // The next save or update reloads again.
    }
  }

  /// The grid, and the unannounced tray for someone who can edit.
  Future<(MonthGrid, ChangeAnnouncement?)> _read(
    DateTime month,
    EditableSections editable,
  ) {
    return (
      widget.rules.monthGrid(month),
      editable.isEmpty
          ? Future<ChangeAnnouncement?>.value()
          : widget.rules.changeAnnouncement(month),
    ).wait;
  }

  Future<void> _announce(ChangeAnnouncement announcement) async {
    final marked = await showAnnounceSheet(
      context,
      announcement: announcement,
      messagesComposer: widget.messagesComposer,
    );
    if (marked != true) return;
    try {
      await widget.rules.markAnnounced(announcement);
      await _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("The changes weren't marked announced. Try again."),
        ),
      );
    }
  }

  Future<void> _edit(ScheduleRow row, DateTime date) async {
    final grid = _grid;
    if (!_editable.contains(row.sectionId) || grid == null) return;
    if (!grid.isOnSchedule(row, date)) return;
    if (grid.status == MonthStatus.notStarted) {
      // An edit would create the month empty, and it could then no longer be
      // started from last month.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Start ${DateFormat.MMMM().format(_month)} first.'),
        ),
      );
      return;
    }
    final edit = await showCellEditSheet(
      context,
      row: row,
      date: date,
      currentCode: grid.shiftCodeFor(row.staffMemberId, date) ?? '',
      publishedCode: grid.isUnannounced(row.staffMemberId, date)
          ? grid.publishedCodeFor(row.staffMemberId, date)
          : null,
    );
    if (edit == null) return;
    try {
      switch (edit) {
        case SaveCode(:final shiftCode):
          await widget.rules.saveCell(
            SaveCell(
              staffMemberId: row.staffMemberId,
              sectionId: row.sectionId,
              date: date,
              shiftCode: shiftCode,
            ),
          );
        case UndoToPublished():
          await widget.rules.undoCell(
            UndoCell(
              staffMemberId: row.staffMemberId,
              sectionId: row.sectionId,
              date: date,
            ),
          );
      }
      await _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("That change wasn't saved. Try again.")),
      );
    }
  }

  Future<void> _print(ValueChanged<String> printBookPage) async {
    try {
      final grid = await widget.rules.monthGrid(_month);
      printBookPage(bookPageHtml(grid));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("The page couldn't be printed. Try again."),
        ),
      );
    }
  }

  Future<void> _confirmMonth() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm ${DateFormat.yMMMM().format(_month)}?'),
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
    if (confirmed != true) return;
    try {
      await widget.rules.confirmLoadedMonth(_month);
      await _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("The month wasn't confirmed. Try again.")),
      );
    }
  }

  void _open(Widget Function(BuildContext context) page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: page));
  }

  Future<void> _startMonth() async {
    try {
      await widget.rules.startNextMonth(_previousMonth);
      await _reload();
    } on MonthAlreadyStarted {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This month has already been started.')),
      );
      await _reload();
    } on StateError {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${DateFormat.MMMM().format(_previousMonth)} has no Schedule '
            'to start from.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("The month wasn't started. Try again.")),
      );
    }
  }

  Future<void> _releaseMonth() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Release ${DateFormat.yMMMM().format(_month)}?'),
        content: const Text(
          'This month then becomes the live Schedule that staff can see.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Release'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.rules.releaseMonth(_month);
      await _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("The month wasn't released. Try again.")),
      );
    }
  }

  DateTime get _previousMonth => DateTime(_month.year, _month.month - 1);

  Widget? _banner(MonthGrid grid) {
    if (!_canEdit) return null;
    if (grid.awaitingConfirmation) {
      return _Banner(
        message:
            'Check this month against your Excel file. '
            'Tap any cell to correct it.',
        actionLabel: 'Confirm month',
        onPressed: _confirmMonth,
      );
    }
    return switch (grid.status) {
      MonthStatus.notStarted => _Banner(
        message:
            "${DateFormat.MMMM().format(_month)} hasn't been started. "
            'Start it from last month, lined up by weekday.',
        actionLabel: 'Start from ${DateFormat.MMMM().format(_previousMonth)}',
        onPressed: _startMonth,
      ),
      MonthStatus.unpublished => _Banner(
        message: "Unpublished: staff can't see this month yet.",
        actionLabel: 'Release month',
        onPressed: _releaseMonth,
      ),
      MonthStatus.released => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final grid = _grid;
    final announcement = _announcement;
    final banner = grid == null ? null : _banner(grid);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Previous month',
              onPressed: () => _goToMonth(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Text(DateFormat.yMMMM().format(_month)),
            IconButton(
              tooltip: 'Next month',
              onPressed: () => _goToMonth(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        actions: [
          if (_canEdit) ...[
            IconButton(
              tooltip: 'Change log',
              onPressed: () => _open(
                (context) => ChangeLogPage(rules: widget.rules, month: _month),
              ),
              icon: const Icon(Icons.history),
            ),
            IconButton(
              tooltip: 'Night scheduler',
              onPressed: () => _open(
                (context) =>
                    NightSchedulerPage(rules: widget.rules, month: _month),
              ),
              icon: const Icon(Icons.nightlight_outlined),
            ),
          ],
          if (widget.printBookPage case final printBookPage?)
            IconButton(
              tooltip: 'Print the book page',
              onPressed: () => _print(printBookPage),
              icon: const Icon(Icons.print_outlined),
            ),
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SegmentedButton<ScheduleView>(
              segments: const [
                ButtonSegment(
                  value: ScheduleView.month,
                  label: Text('Month'),
                  icon: Icon(Icons.grid_on),
                ),
                ButtonSegment(
                  value: ScheduleView.day,
                  label: Text('Day'),
                  icon: Icon(Icons.today),
                ),
                ButtonSegment(
                  value: ScheduleView.person,
                  label: Text('Person'),
                  icon: Icon(Icons.person_outline),
                ),
              ],
              selected: {_view},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  setState(() => _view = selection.single),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (banner != null)
              banner
            else if (announcement != null && !announcement.isEmpty)
              _AnnounceTray(
                changeCount: announcement.changeCount,
                onAnnounce: () => _announce(announcement),
              ),
            Expanded(child: _body(grid)),
          ],
        ),
      ),
    );
  }

  Widget _body(MonthGrid? grid) {
    return switch ((grid, _loadError)) {
      (null, null) => const Center(child: CircularProgressIndicator()),
      (null, _) => const Center(
        child: Text("The Schedule couldn't be loaded."),
      ),
      (final MonthGrid grid, _)
          when !_canEdit && grid.status != MonthStatus.released =>
        Center(
          child: Text(
            "${DateFormat.yMMMM().format(_month)} hasn't been released yet.",
          ),
        ),
      (final MonthGrid grid, _) => switch (_view) {
        ScheduleView.month => _MonthView(grid: grid, onEdit: _edit),
        ScheduleView.day => _DayView(
          grid: grid,
          day: _day,
          onDayChanged: (day) => setState(() => _day = day),
          onEdit: _edit,
        ),
        ScheduleView.person => _PersonView(
          grid: grid,
          staffMemberId: _personId ?? grid.rows.firstOrNull?.staffMemberId,
          onPersonChanged: (id) => setState(() => _personId = id),
          onEdit: _edit,
        ),
      },
    };
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.message,
    required this.actionLabel,
    required this.onPressed,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Expanded(child: Text(message)),
            const SizedBox(width: 12),
            FilledButton(onPressed: onPressed, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

/// Stays on screen until the changes are announced.
class _AnnounceTray extends StatelessWidget {
  const _AnnounceTray({required this.changeCount, required this.onAnnounce});

  final int changeCount;
  final VoidCallback onAnnounce;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _unannouncedColor(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            const Icon(Icons.campaign_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                changeCount == 1
                    ? '1 unannounced change'
                    : '$changeCount unannounced changes',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(onPressed: onAnnounce, child: const Text('Announce')),
          ],
        ),
      ),
    );
  }
}

typedef _OnEdit = Future<void> Function(ScheduleRow row, DateTime date);

class _MonthView extends StatelessWidget {
  const _MonthView({required this.grid, required this.onEdit});

  final MonthGrid grid;
  final _OnEdit onEdit;

  @override
  Widget build(BuildContext context) {
    final days = grid.days;
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DayHeader(days: days),
            for (final section in grid.sections) ...[
              _SectionBand(grid: grid, section: section, days: days),
              for (final row in grid.rowsIn(section.id))
                _StaffRow(grid: grid, row: row, days: days, onEdit: onEdit),
            ],
          ],
        ),
      ),
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
        const SizedBox(width: _nameWidth, height: _cellHeight),
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
  const _SectionBand({
    required this.grid,
    required this.section,
    required this.days,
  });

  final MonthGrid grid;
  final ScheduleSection section;
  final List<DateTime> days;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: _nameWidth,
          height: _bandHeight,
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
              '${_isWeekend(day) ? 'weekend' : 'weekday'}-${_dateKey(day)}',
            ),
            width: _dayWidth,
            height: _bandHeight,
            alignment: Alignment.center,
            decoration: _cellDecoration(day, context),
            child: _ShortMarker(
              key: ValueKey('short-${section.id}-${_dateKey(day)}'),
              shortShifts: grid.shortShiftsOn(section.id, day),
            ),
          ),
      ],
    );
  }
}

class _StaffRow extends StatelessWidget {
  const _StaffRow({
    required this.grid,
    required this.row,
    required this.days,
    required this.onEdit,
  });

  final MonthGrid grid;
  final ScheduleRow row;
  final List<DateTime> days;
  final _OnEdit onEdit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: _nameWidth,
          height: _cellHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Text(row.displayName, overflow: TextOverflow.ellipsis),
        ),
        for (final day in days)
          if (grid.isOnSchedule(row, day))
            _GridCell(
              key: ValueKey('cell-${row.staffMemberId}-${_dateKey(day)}'),
              day: day,
              code: grid.shiftCodeFor(row.staffMemberId, day) ?? '',
              unannounced: grid.isUnannounced(row.staffMemberId, day),
              unannouncedKey: ValueKey(
                'unannounced-${row.staffMemberId}-${_dateKey(day)}',
              ),
              onTap: () => onEdit(row, day),
            )
          else
            // After their Last day: no longer on the Schedule.
            Container(
              key: ValueKey('gone-${row.staffMemberId}-${_dateKey(day)}'),
              width: _dayWidth,
              height: _cellHeight,
              decoration: _cellDecoration(
                day,
                context,
              ).copyWith(color: Theme.of(context).colorScheme.outlineVariant),
            ),
      ],
    );
  }
}

/// How many shifts in a Section are uncovered that day, if any.
class _ShortMarker extends StatelessWidget {
  const _ShortMarker({super.key, required this.shortShifts});

  final List<ShortShift> shortShifts;

  @override
  Widget build(BuildContext context) {
    if (shortShifts.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Short: ${shortShifts.map((s) => s.shiftCode).join(', ')}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '−${shortShifts.length}',
          style: TextStyle(
            color: colors.onErrorContainer,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _GridCell extends StatelessWidget {
  const _GridCell({
    super.key,
    required this.day,
    required this.code,
    required this.unannounced,
    required this.unannouncedKey,
    required this.onTap,
  });

  final DateTime day;
  final String code;
  final bool unannounced;
  final Key unannouncedKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final decoration = _cellDecoration(day, context);
    return InkWell(
      onTap: onTap,
      child: Container(
        key: unannounced ? unannouncedKey : null,
        width: _dayWidth,
        height: _cellHeight,
        alignment: Alignment.center,
        decoration: unannounced
            ? decoration.copyWith(color: _unannouncedColor(context))
            : decoration,
        child: Text(
          code,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _DayView extends StatelessWidget {
  const _DayView({
    required this.grid,
    required this.day,
    required this.onDayChanged,
    required this.onEdit,
  });

  final MonthGrid grid;
  final DateTime day;
  final ValueChanged<DateTime> onDayChanged;
  final _OnEdit onEdit;

  @override
  Widget build(BuildContext context) {
    final days = grid.days;
    final entries = grid.rowsOn(day);
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous day',
              onPressed: day.day > 1
                  ? () => onDayChanged(days[day.day - 2])
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                DateFormat.MMMMEEEEd().format(day),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Pick a date',
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: day,
                  firstDate: days.first,
                  lastDate: days.last,
                );
                if (picked != null) onDayChanged(picked);
              },
              icon: const Icon(Icons.calendar_month),
            ),
            IconButton(
              tooltip: 'Next day',
              onPressed: day.day < days.length
                  ? () => onDayChanged(days[day.day])
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Expanded(
          child: ListView(
            children: [
              for (final section in grid.sections) ...[
                _SectionHeading(section.name),
                for (final short in grid.shortShiftsOn(section.id, day))
                  ListTile(
                    leading: Icon(
                      Icons.warning_amber,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: const Text('Short'),
                    trailing: Text(
                      short.shiftCode,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                for (final entry in entries.where(
                  (entry) => entry.row.sectionId == section.id,
                ))
                  _EntryTile(
                    title: entry.row.displayName,
                    entry: entry,
                    onTap: () => onEdit(entry.row, entry.date),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PersonView extends StatelessWidget {
  const _PersonView({
    required this.grid,
    required this.staffMemberId,
    required this.onPersonChanged,
    required this.onEdit,
  });

  final MonthGrid grid;
  final String? staffMemberId;
  final ValueChanged<String> onPersonChanged;
  final _OnEdit onEdit;

  @override
  Widget build(BuildContext context) {
    final selected = grid.rows.any((row) => row.staffMemberId == staffMemberId)
        ? staffMemberId
        : null;
    if (selected == null) {
      return const Center(child: Text('No one is on the Staff list yet.'));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButton<String>(
            isExpanded: true,
            value: selected,
            onChanged: (id) {
              if (id != null) onPersonChanged(id);
            },
            items: [
              for (final row in grid.rows)
                DropdownMenuItem(
                  value: row.staffMemberId,
                  child: Text(row.displayName),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final entry in grid.monthFor(selected))
                _EntryTile(
                  title: DateFormat('EEE d').format(entry.date),
                  entry: entry,
                  shaded: _isWeekend(entry.date),
                  onTap: () => onEdit(entry.row, entry.date),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.title,
    required this.entry,
    required this.onTap,
    this.shaded = false,
  });

  final String title;
  final RowDay entry;
  final VoidCallback onTap;
  final bool shaded;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      title: Text(title),
      trailing: Text(
        entry.shiftCode,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      tileColor: entry.unannounced
          ? _unannouncedColor(context)
          : shaded
          ? colors.surfaceContainerHighest
          : null,
      onTap: onTap,
    );
  }
}

BoxDecoration _cellDecoration(DateTime day, BuildContext context) {
  return BoxDecoration(
    color: _isWeekend(day)
        ? Theme.of(context).colorScheme.surfaceContainerHighest
        : Theme.of(context).colorScheme.surface,
    border: Border.all(color: Theme.of(context).dividerColor),
  );
}

Color _unannouncedColor(BuildContext context) {
  return Theme.of(context).colorScheme.tertiaryContainer;
}

bool _isWeekend(DateTime day) {
  return day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
}

String _dateKey(DateTime day) => DateFormat('yyyy-MM-dd').format(day);

const _nameWidth = 160.0;
const _dayWidth = 48.0;
const _cellHeight = 44.0;
const _bandHeight = 32.0;
