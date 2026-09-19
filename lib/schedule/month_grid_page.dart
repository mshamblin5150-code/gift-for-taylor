import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';

import '../notifications/notice_gateway.dart';
import '../notifications/notices_page.dart';

import 'announce_sheet.dart';
import 'cell_edit_sheet.dart';
import 'change_log_page.dart';
import 'messages_composer.dart';
import 'night_scheduler_page.dart';
import 'print_wording_dialog.dart';
import 'print_wording_gateway.dart';
import 'swaps_page.dart';
import 'open_shifts_page.dart';
import 'requests_off_page.dart';
import 'shift_codes_page.dart';
import 'staffing_sheet.dart';

enum ScheduleView { month, day, person }

class MonthGridPage extends StatefulWidget {
  const MonthGridPage({
    super.key,
    required this.rules,
    required this.month,
    this.staffMemberId,
    this.swapStaffMemberId,
    this.onSignOut,
    this.onCalendarFeed,
    this.onManageStaff,
    this.onOpenStaffDetails,
    this.messagesComposer,
    this.swapRules,
    this.openShiftRules,
    this.noticeGateway,
    this.printBookPage,
    this.printWordingGateway,
  });

  final ScheduleRules rules;
  final DateTime month;
  final String? staffMemberId;
  final String? swapStaffMemberId;
  final VoidCallback? onSignOut;
  final VoidCallback? onCalendarFeed;
  final Future<void> Function()? onManageStaff;
  final Future<void> Function(String staffMemberId)? onOpenStaffDetails;
  final MessagesComposer? messagesComposer;
  final SwapRules? swapRules;
  final OpenShiftRules? openShiftRules;
  final NoticeGateway? noticeGateway;

  /// Prints a Schedule book page, given as an HTML document.
  final ValueChanged<String>? printBookPage;
  final PrintWordingGateway? printWordingGateway;

  @override
  State<MonthGridPage> createState() => _MonthGridPageState();
}

class _MonthGridPageState extends State<MonthGridPage> {
  late DateTime _month = DateTime(widget.month.year, widget.month.month);
  StreamSubscription<void>? _updates;
  StreamSubscription<void>? _swapUpdates;
  StreamSubscription<void>? _openShiftUpdates;
  int _pendingSwaps = 0;
  Timer? _requestNoticeTimer;
  MonthGrid? _grid;
  List<LegendCode> _shiftCodes = const [];
  List<SectionStaffing> _staffing = [];
  ChangeAnnouncement? _announcement;
  PrintWording? _wording;

  /// The Manager: may confirm the month and manage the Night scheduler.
  bool _canEdit = false;
  EditableSections _editable = const EditableSections.only({});
  Object? _loadError;
  int _unreadRequests = 0;
  late ScheduleView _view = widget.staffMemberId == null
      ? ScheduleView.month
      : ScheduleView.person;
  late DateTime _day = _defaultDay();
  late String? _personId = widget.staffMemberId;

  @override
  void initState() {
    super.initState();
    _listen();
    if (widget.swapRules case final swapRules?) {
      _swapUpdates = swapRules.updates().listen((_) => _refreshSwaps());
    }
    if (widget.openShiftRules case final openShiftRules?) {
      _openShiftUpdates = openShiftRules.updates().listen((_) => _reload());
    }
    _load();
    _loadWording();
    _requestNoticeTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshRequestNotices(),
    );
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
    _loadWording();
  }

  @override
  void dispose() {
    _updates?.cancel();
    _swapUpdates?.cancel();
    _openShiftUpdates?.cancel();
    _requestNoticeTimer?.cancel();
    super.dispose();
  }

  DateTime _defaultDay() {
    final now = DateTime.now();
    return now.year == _month.year && now.month == _month.month
        ? DateTime(now.year, now.month, now.day)
        : _month;
  }

  Future<void> _load() async {
    _refreshRequestNotices();
    try {
      final month = _month;
      final (canEdit, editable) = await (
        widget.rules.canEditSchedule(),
        widget.rules.editableSections(),
      ).wait;
      final (grid, announcement, codes) = await _read(month, editable);
      final staffing =
          await widget.openShiftRules?.staffingForMonth(month) ??
          <SectionStaffing>[];
      if (!mounted || month != _month) return;
      setState(() {
        _canEdit = canEdit;
        _editable = editable;
        _grid = grid;
        _shiftCodes = codes;
        _staffing = staffing;
        _announcement = announcement;
        _loadError = null;
      });
      _refreshSwaps();
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  Future<void> _refreshSwaps() async {
    final swapRules = widget.swapRules;
    if (swapRules == null) return;
    try {
      final swaps = await swapRules.swaps();
      if (!mounted) return;
      setState(
        () => _pendingSwaps = swaps
            .where(
              (swap) =>
                  (swap.status == SwapStatus.proposed &&
                      swap.colleagueId == widget.swapStaffMemberId) ||
                  (swap.status == SwapStatus.accepted && _canEdit),
            )
            .length,
      );
    } catch (_) {
      // Schedule access still works if the Swap inbox is temporarily unavailable.
    }
  }

  Future<void> _refreshRequestNotices() async {
    try {
      final count = await widget.rules.unreadRequestOffNotices();
      if (mounted) setState(() => _unreadRequests = count);
    } catch (_) {
      // The Schedule stays usable if notices are temporarily unavailable.
    }
  }

  Future<void> _reload() async {
    try {
      final month = _month;
      final (grid, announcement, codes) = await _read(month, _editable);
      final staffing =
          await widget.openShiftRules?.staffingForMonth(month) ??
          <SectionStaffing>[];
      if (!mounted || month != _month) return;
      setState(() {
        _grid = grid;
        _shiftCodes = codes;
        _staffing = staffing;
        _announcement = announcement;
      });
    } catch (_) {
      // The next save or update reloads again.
    }
  }

  Future<void> _openStaffDetails(String staffMemberId) async {
    await widget.onOpenStaffDetails?.call(staffMemberId);
    if (mounted) await _reload();
  }

  /// The grid, active Shift codes, and the unannounced tray for an editor.
  Future<(MonthGrid, ChangeAnnouncement?, List<LegendCode>)> _read(
    DateTime month,
    EditableSections editable,
  ) => (
    widget.rules.monthGrid(month),
    editable.isEmpty
        ? Future<ChangeAnnouncement?>.value()
        : widget.rules.changeAnnouncement(month),
    widget.rules.shiftCodes(),
  ).wait;

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
      codes: _shiftCodes,
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

  Future<void> _manageSectionDay(ScheduleSection section, DateTime date) async {
    final rules = widget.openShiftRules;
    if (!_canEdit || rules == null) return;
    final staffing = _staffing
        .where(
          (item) =>
              item.sectionId == section.id &&
              item.date.year == date.year &&
              item.date.month == date.month &&
              item.date.day == date.day,
        )
        .firstOrNull;
    if (staffing == null) return;
    final changed = await showStaffingSheet(
      context,
      rules: rules,
      section: section,
      date: date,
      staffing: staffing,
    );
    if (changed == true) await _reload();
  }

  Future<void> _print(ValueChanged<String> printBookPage) async {
    try {
      final wording =
          await widget.printWordingGateway?.read() ?? const PrintWording();
      if (mounted) setState(() => _wording = wording);
      final grid = await widget.rules.monthGrid(_month);
      printBookPage(
        bookPageHtml(
          grid,
          wording: wording,
          codes: await widget.rules.shiftCodes(),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("The page couldn't be printed. Try again."),
        ),
      );
    }
  }

  Future<void> _loadWording() async {
    try {
      final wording =
          await widget.printWordingGateway?.read() ?? const PrintWording();
      if (mounted) setState(() => _wording = wording);
    } catch (_) {
      if (mounted) setState(() => _wording = null);
    }
  }

  Future<void> _changePrintWording() async {
    final gateway = widget.printWordingGateway;
    final current = _wording;
    if (gateway == null || current == null) return;
    final next = await showPrintWordingDialog(context, current);
    if (next == null) return;
    try {
      await gateway.save(next);
      if (mounted) setState(() => _wording = next);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("The print wording wasn't saved. Try again."),
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
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: page))
        .then((_) => _refreshRequestNotices());
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
          if (widget.openShiftRules != null)
            IconButton(
              tooltip: 'Open shifts',
              onPressed: () => _open(
                (context) => OpenShiftsPage(
                  rules: widget.openShiftRules!,
                  scheduleRules: widget.rules,
                  month: _month,
                  staffMemberId: widget.swapStaffMemberId,
                  isManager: _canEdit,
                ),
              ),
              icon: const Icon(Icons.add_circle_outline),
            ),
          if (widget.swapRules != null)
            IconButton(
              tooltip: 'Swaps',
              onPressed: () => _open(
                (context) => SwapsPage(
                  rules: widget.rules,
                  swapRules: widget.swapRules!,
                  month: _month,
                  staffMemberId: widget.swapStaffMemberId,
                  isManager: _canEdit,
                  messagesComposer: widget.messagesComposer,
                ),
              ),
              icon: Badge(
                isLabelVisible: _pendingSwaps > 0,
                label: Text('$_pendingSwaps'),
                child: const Icon(Icons.swap_horiz),
              ),
            ),
          if (widget.noticeGateway case final gateway?)
            IconButton(
              tooltip: 'Notices',
              onPressed: () =>
                  _open((context) => NoticesPage(gateway: gateway)),
              icon: const Icon(Icons.notifications_outlined),
            ),
          if (widget.onCalendarFeed != null)
            IconButton(
              tooltip: 'My Calendar feed',
              onPressed: widget.onCalendarFeed,
              icon: const Icon(Icons.calendar_month_outlined),
            ),
          IconButton(
            tooltip: _canEdit
                ? 'Request off approval queue'
                : 'My Requests off',
            onPressed: () => _open(
              (context) =>
                  RequestsOffPage(rules: widget.rules, isManager: _canEdit),
            ),
            icon: Badge(
              isLabelVisible: _unreadRequests > 0,
              label: Text('$_unreadRequests'),
              child: const Icon(Icons.event_busy_outlined),
            ),
          ),
          if (_canEdit) ...[
            IconButton(
              tooltip: 'Manage Shift codes',
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => ShiftCodesPage(rules: widget.rules),
                  ),
                );
                if (mounted) await _load();
              },
              icon: const Icon(Icons.schedule_outlined),
            ),
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
              tooltip: _wording?.tooltip.label ?? 'Loading print wording',
              onPressed: _wording == null ? null : () => _print(printBookPage),
              icon: const Icon(Icons.print_outlined),
            ),
          if (_canEdit && widget.printWordingGateway != null)
            IconButton(
              tooltip: 'Change print wording',
              onPressed: _wording == null ? null : _changePrintWording,
              icon: const Icon(Icons.text_fields_outlined),
            ),
          if (widget.onManageStaff != null)
            IconButton(
              tooltip: 'Manage Staff list',
              onPressed: () async {
                await widget.onManageStaff?.call();
                if (mounted) await _load();
              },
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
        ScheduleView.month => _MonthView(
          grid: grid,
          staffing: _staffing,
          onManageDay: _manageSectionDay,
          onEdit: _edit,
          onOpenStaffDetails: widget.onOpenStaffDetails == null
              ? null
              : _openStaffDetails,
          staffMemberId: widget.staffMemberId,
        ),
        ScheduleView.day => _DayView(
          grid: grid,
          staffing: _staffing,
          onManageDay: _manageSectionDay,
          day: _day,
          onDayChanged: (day) => setState(() => _day = day),
          onEdit: _edit,
          highlightStaffMemberId: widget.staffMemberId,
        ),
        ScheduleView.person => _PersonView(
          grid: grid,
          staffMemberId: _personId ?? grid.rows.firstOrNull?.staffMemberId,
          onPersonChanged: (id) => setState(() => _personId = id),
          onEdit: _edit,
          highlightStaffMemberId: widget.staffMemberId,
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
      color: _changeColor(context),
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
typedef _OnManageDay =
    Future<void> Function(ScheduleSection section, DateTime date);

SectionStaffing? _staffingOn(
  List<SectionStaffing> staffing,
  String sectionId,
  DateTime day,
) => staffing
    .where(
      (item) =>
          item.sectionId == sectionId &&
          item.date.year == day.year &&
          item.date.month == day.month &&
          item.date.day == day.day,
    )
    .firstOrNull;

class _MonthView extends StatelessWidget {
  const _MonthView({
    required this.grid,
    required this.staffing,
    required this.onManageDay,
    required this.onEdit,
    required this.onOpenStaffDetails,
    required this.staffMemberId,
  });

  final MonthGrid grid;
  final List<SectionStaffing> staffing;
  final _OnManageDay onManageDay;
  final _OnEdit onEdit;
  final Future<void> Function(String)? onOpenStaffDetails;
  final String? staffMemberId;

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
              _SectionBand(
                grid: grid,
                section: section,
                days: days,
                staffing: staffing,
                onManageDay: onManageDay,
              ),
              for (final row in grid.rowsIn(section.id))
                _StaffRow(
                  grid: grid,
                  row: row,
                  days: days,
                  onEdit: onEdit,
                  onOpenStaffDetails: onOpenStaffDetails,
                  staffMemberId: staffMemberId,
                ),
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
    required this.staffing,
    required this.onManageDay,
  });

  final MonthGrid grid;
  final ScheduleSection section;
  final List<DateTime> days;
  final List<SectionStaffing> staffing;
  final _OnManageDay onManageDay;

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
          InkWell(
            key: ValueKey(
              '${_isWeekend(day) ? 'weekend' : 'weekday'}-${_dateKey(day)}',
            ),
            onTap: () => onManageDay(section, day),
            child: Container(
              width: _dayWidth,
              height: _bandHeight,
              alignment: Alignment.center,
              decoration: _cellDecoration(day, context),
              child: _ShortMarker(
                key: ValueKey('short-${section.id}-${_dateKey(day)}'),
                count:
                    grid.shortShiftsOn(section.id, day).length >
                        (_staffingOn(staffing, section.id, day)?.shortCount ??
                            0)
                    ? grid.shortShiftsOn(section.id, day).length
                    : (_staffingOn(staffing, section.id, day)?.shortCount ?? 0),
              ),
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
    required this.onOpenStaffDetails,
    required this.staffMemberId,
  });

  final MonthGrid grid;
  final ScheduleRow row;
  final List<DateTime> days;
  final _OnEdit onEdit;
  final Future<void> Function(String)? onOpenStaffDetails;
  final String? staffMemberId;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InkWell(
          onTap: onOpenStaffDetails == null
              ? null
              : () => onOpenStaffDetails!(row.staffMemberId),
          onDoubleTap: onOpenStaffDetails == null
              ? null
              : () => onOpenStaffDetails!(row.staffMemberId),
          child: Container(
            width: _nameWidth,
            height: _cellHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Text(row.displayName, overflow: TextOverflow.ellipsis),
          ),
        ),
        for (final day in days)
          if (grid.isOnSchedule(row, day))
            _GridCell(
              key: ValueKey('cell-${row.staffMemberId}-${_dateKey(day)}'),
              day: day,
              code: grid.shiftCodeFor(row.staffMemberId, day) ?? '',
              unannounced: grid.isUnannounced(row.staffMemberId, day),
              changed: _isStaffChange(staffMemberId, grid, row, day),
              changedKey: ValueKey(
                'changed-${row.staffMemberId}-${_dateKey(day)}',
              ),
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
  const _ShortMarker({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Short: $count',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '−$count',
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
    required this.changed,
    required this.changedKey,
    required this.onTap,
  });

  final DateTime day;
  final String code;
  final bool unannounced;
  final Key unannouncedKey;
  final bool changed;
  final Key changedKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final decoration = _cellDecoration(day, context);
    return InkWell(
      onTap: onTap,
      child: Container(
        key: changed
            ? changedKey
            : unannounced
            ? unannouncedKey
            : null,
        width: _dayWidth,
        height: _cellHeight,
        alignment: Alignment.center,
        decoration: unannounced || changed
            ? decoration.copyWith(color: _changeColor(context))
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
    required this.staffing,
    required this.onManageDay,
    required this.day,
    required this.onDayChanged,
    required this.onEdit,
    required this.highlightStaffMemberId,
  });

  final MonthGrid grid;
  final List<SectionStaffing> staffing;
  final _OnManageDay onManageDay;
  final DateTime day;
  final ValueChanged<DateTime> onDayChanged;
  final _OnEdit onEdit;
  final String? highlightStaffMemberId;

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
                ListTile(
                  title: Text(
                    section.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  tileColor: Theme.of(context).colorScheme.primaryContainer,
                  trailing: const Icon(Icons.edit_calendar),
                  onTap: () => onManageDay(section, day),
                ),
                if ((_staffingOn(staffing, section.id, day)?.shortCount ?? 0) >
                    grid.shortShiftsOn(section.id, day).length)
                  ListTile(
                    leading: Icon(
                      Icons.warning_amber,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(
                      'Short ${_staffingOn(staffing, section.id, day)!.shortCount} against minimum',
                    ),
                    onTap: () => onManageDay(section, day),
                  ),
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
                    highlight: _isStaffChange(
                      highlightStaffMemberId,
                      grid,
                      entry.row,
                      entry.date,
                    ),
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
    required this.highlightStaffMemberId,
  });

  final MonthGrid grid;
  final String? staffMemberId;
  final ValueChanged<String> onPersonChanged;
  final _OnEdit onEdit;
  final String? highlightStaffMemberId;

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
                  highlight: _isStaffChange(
                    highlightStaffMemberId,
                    grid,
                    entry.row,
                    entry.date,
                  ),
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

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.title,
    required this.entry,
    required this.onTap,
    this.highlight = false,
    this.shaded = false,
  });

  final String title;
  final RowDay entry;
  final VoidCallback onTap;
  final bool shaded;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      key: highlight
          ? ValueKey(
              'changed-${entry.row.staffMemberId}-${_dateKey(entry.date)}',
            )
          : null,
      title: Text(title),
      trailing: Text(
        entry.shiftCode,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      tileColor: entry.unannounced || highlight
          ? _changeColor(context)
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

bool _isStaffChange(
  String? staffMemberId,
  MonthGrid grid,
  ScheduleRow row,
  DateTime date,
) =>
    staffMemberId == row.staffMemberId &&
    grid.isChanged(row.staffMemberId, date);

Color _changeColor(BuildContext context) {
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
