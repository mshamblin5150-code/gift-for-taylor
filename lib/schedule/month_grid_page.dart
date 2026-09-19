import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
    this.now,
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
  final DateTime Function()? now;

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
  Timer? _midnightTimer;
  late DateTime _today = _dateOnly(_now());
  MonthGrid? _grid;
  List<LegendCode> _shiftCodes = const [];
  List<SectionStaffing> _staffing = [];
  ChangeAnnouncement? _announcement;
  PrintWording? _wording;
  bool _savingDrop = false;

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
    _scheduleMidnight();
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
    _midnightTimer?.cancel();
    _updates?.cancel();
    _swapUpdates?.cancel();
    _openShiftUpdates?.cancel();
    _requestNoticeTimer?.cancel();
    super.dispose();
  }

  DateTime _defaultDay() {
    final now = _today;
    return now.year == _month.year && now.month == _month.month
        ? DateTime(now.year, now.month, now.day)
        : _month;
  }

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  void _scheduleMidnight() {
    _midnightTimer?.cancel();
    final now = _now();
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(nextDay.difference(now), () {
      if (!mounted) return;
      setState(() => _today = _dateOnly(_now()));
      _scheduleMidnight();
    });
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

  Future<void> _drop(
    _DraggedCell source,
    _DraggedCell target,
    bool copy,
  ) async {
    final grid = _grid;
    if (_savingDrop ||
        grid == null ||
        grid.status == MonthStatus.notStarted ||
        !_editable.contains(source.row.sectionId) ||
        !_editable.contains(target.row.sectionId) ||
        !grid.isOnSchedule(source.row, source.date) ||
        !grid.isOnSchedule(target.row, target.date)) {
      return;
    }
    final sourceCode =
        grid.shiftCodeFor(source.row.staffMemberId, source.date) ?? '';
    final targetCode =
        grid.shiftCodeFor(target.row.staffMemberId, target.date) ?? '';
    if (sourceCode.isEmpty || (sourceCode == targetCode)) return;
    if (!copy && targetCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Choose a cell with a Shift code to swap, or hold Ctrl or Option to copy here.',
          ),
        ),
      );
      return;
    }
    SaveCell cell(_DraggedCell location, String code) => SaveCell(
      staffMemberId: location.row.staffMemberId,
      sectionId: location.row.sectionId,
      date: location.date,
      shiftCode: code,
    );
    final action = SaveCellPair(
      first: cell(source, copy ? sourceCode : targetCode),
      second: cell(target, sourceCode),
      expectedFirstCode: sourceCode,
      expectedSecondCode: targetCode,
    );
    setState(() => _savingDrop = true);
    try {
      await widget.rules.saveCellPair(action);
      await _reload();
      if (!mounted) return;
      final undo = SaveCellPair(
        first: cell(source, sourceCode),
        second: cell(target, targetCode),
        expectedFirstCode: action.first.shiftCode,
        expectedSecondCode: action.second.shiftCode,
      );
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(copy ? 'Shift code copied.' : 'Shift codes swapped.'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              try {
                await widget.rules.saveCellPair(undo);
                await _reload();
              } catch (error) {
                if (mounted) _showDropError(error);
              }
            },
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        await _reload();
        if (mounted) _showDropError(error);
      }
    } finally {
      if (mounted) setState(() => _savingDrop = false);
    }
  }

  void _showDropError(Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('The drop was not saved: $error')));
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
          today: _today,
          staffing: _staffing,
          onManageDay: _manageSectionDay,
          onEdit: _edit,
          onDrop: _drop,
          editable: _editable,
          dragEnabled: grid.status != MonthStatus.notStarted && !_savingDrop,
          onOpenStaffDetails: widget.onOpenStaffDetails == null
              ? null
              : _openStaffDetails,
          staffMemberId: widget.staffMemberId,
        ),
        ScheduleView.day => _DayView(
          grid: grid,
          today: _today,
          staffing: _staffing,
          onManageDay: _manageSectionDay,
          day: _day,
          onDayChanged: (day) => setState(() => _day = day),
          onEdit: _edit,
          highlightStaffMemberId: widget.staffMemberId,
        ),
        ScheduleView.person => _PersonView(
          grid: grid,
          today: _today,
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
typedef _OnDrop = Future<void> Function(
  _DraggedCell source,
  _DraggedCell target,
  bool copy,
);

final class _DraggedCell {
  const _DraggedCell(this.row, this.date);
  final ScheduleRow row;
  final DateTime date;

  bool isSame(_DraggedCell other) =>
      row.staffMemberId == other.row.staffMemberId &&
      _dateOnly(date) == _dateOnly(other.date);
}

typedef _OnManageDay = Future<void> Function(
  ScheduleSection section,
  DateTime date,
);

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

class _MonthView extends StatefulWidget {
  const _MonthView({
    required this.grid,
    required this.today,
    required this.staffing,
    required this.onManageDay,
    required this.onEdit,
    required this.onDrop,
    required this.editable,
    required this.dragEnabled,
    required this.onOpenStaffDetails,
    required this.staffMemberId,
  });

  final MonthGrid grid;
  final DateTime today;
  final List<SectionStaffing> staffing;
  final _OnManageDay onManageDay;
  final _OnEdit onEdit;
  final _OnDrop onDrop;
  final EditableSections editable;
  final bool dragEnabled;
  final Future<void> Function(String)? onOpenStaffDetails;
  final String? staffMemberId;

  @override
  State<_MonthView> createState() => _MonthViewState();
}

class _MonthViewState extends State<_MonthView> {
  final _headerScroll = ScrollController();
  final _daysScroll = ScrollController();
  final _verticalScroll = ScrollController();
  Timer? _dragScrollTimer;
  Offset? _dragPointer;

  @override
  void initState() {
    super.initState();
    _headerScroll.addListener(() => _syncScroll(_headerScroll, _daysScroll));
    _daysScroll.addListener(() => _syncScroll(_daysScroll, _headerScroll));
    WidgetsBinding.instance.addPostFrameCallback((_) => _showToday());
  }

  void _syncScroll(ScrollController source, ScrollController target) {
    if (!target.hasClients) return;
    final offset = source.offset.clamp(
      target.position.minScrollExtent,
      target.position.maxScrollExtent,
    );
    if (target.offset != offset) target.jumpTo(offset);
  }

  void _showToday() {
    if (!mounted || !_daysScroll.hasClients) return;
    final today = widget.today;
    if (today.year != widget.grid.month.year ||
        today.month != widget.grid.month.month) {
      return;
    }
    final position = _daysScroll.position;
    final center = (today.day - 0.5) * _dayWidth;
    _daysScroll.jumpTo(
      (center - position.viewportDimension / 2).clamp(
        0.0,
        position.maxScrollExtent,
      ),
    );
  }

  @override
  void dispose() {
    _dragScrollTimer?.cancel();
    _headerScroll.dispose();
    _daysScroll.dispose();
    _verticalScroll.dispose();
    super.dispose();
  }

  void _scrollDuringDrag(Offset globalPosition) {
    _dragPointer = globalPosition;
    _dragScrollTimer ??= Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (_dragPointer case final pointer?) _scrollAt(pointer);
    });
    _scrollAt(globalPosition);
  }

  void _stopDragScroll() {
    _dragPointer = null;
    _dragScrollTimer?.cancel();
    _dragScrollTimer = null;
  }

  void _scrollAt(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final point = box.globalToLocal(globalPosition);
    void scroll(ScrollController controller, double direction) {
      if (!controller.hasClients || direction == 0) return;
      controller.jumpTo(
        (controller.offset + direction * 18).clamp(
          controller.position.minScrollExtent,
          controller.position.maxScrollExtent,
        ),
      );
    }

    final width = box.size.width;
    final height = box.size.height;
    scroll(
      _daysScroll,
      point.dx < _nameWidth + 36
          ? -1
          : point.dx > width - 36
          ? 1
          : 0,
    );
    scroll(
      _verticalScroll,
      point.dy < _cellHeight + 36
          ? -1
          : point.dy > height - 36
          ? 1
          : 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.grid.days;
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: _nameWidth, height: _cellHeight),
            Expanded(
              child: SingleChildScrollView(
                controller: _headerScroll,
                scrollDirection: Axis.horizontal,
                child: _DayHeader(days: days, today: widget.today),
              ),
            ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _verticalScroll,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _NameColumn(
                  grid: widget.grid,
                  onOpenStaffDetails: widget.onOpenStaffDetails,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    key: const ValueKey('month-horizontal-scroll'),
                    controller: _daysScroll,
                    scrollDirection: Axis.horizontal,
                    child: Column(
                      children: [
                        for (final section in widget.grid.sections) ...[
                          _SectionBand(
                            grid: widget.grid,
                            section: section,
                            days: days,
                            today: widget.today,
                            staffing: widget.staffing,
                            onManageDay: widget.onManageDay,
                          ),
                          for (final row in widget.grid.rowsIn(section.id))
                            _StaffRow(
                              grid: widget.grid,
                              row: row,
                              days: days,
                              today: widget.today,
                              onEdit: widget.onEdit,
                              onDrop: widget.onDrop,
                              onDragUpdate: _scrollDuringDrag,
                              onDragStop: _stopDragScroll,
                              editable: widget.editable,
                              dragEnabled: widget.dragEnabled,
                              staffMemberId: widget.staffMemberId,
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NameColumn extends StatelessWidget {
  const _NameColumn({required this.grid, required this.onOpenStaffDetails});

  final MonthGrid grid;
  final Future<void> Function(String)? onOpenStaffDetails;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final section in grid.sections) ...[
          Container(
            width: _nameWidth,
            height: _bandHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            color: Theme.of(context).colorScheme.primary,
            child: Text(
              section.name,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          for (final row in grid.rowsIn(section.id))
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
        ],
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.days, required this.today});

  final List<DateTime> days;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final day in days)
          Container(
            width: _dayWidth,
            height: _cellHeight,
            alignment: Alignment.center,
            decoration: _cellDecoration(day, context, today),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat.E().format(day).substring(0, 1),
                  style: _todayTextStyle(day, today, context),
                ),
                Text('${day.day}', style: _todayTextStyle(day, today, context)),
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
    required this.today,
    required this.staffing,
    required this.onManageDay,
  });

  final MonthGrid grid;
  final ScheduleSection section;
  final List<DateTime> days;
  final DateTime today;
  final List<SectionStaffing> staffing;
  final _OnManageDay onManageDay;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
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
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                border: _isToday(day, today)
                    ? Border.all(
                        color: Theme.of(context).colorScheme.tertiary,
                        width: 2,
                      )
                    : null,
              ),
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
    required this.today,
    required this.onEdit,
    required this.onDrop,
    required this.onDragUpdate,
    required this.onDragStop,
    required this.editable,
    required this.dragEnabled,
    required this.staffMemberId,
  });

  final MonthGrid grid;
  final ScheduleRow row;
  final List<DateTime> days;
  final DateTime today;
  final _OnEdit onEdit;
  final _OnDrop onDrop;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragStop;
  final EditableSections editable;
  final bool dragEnabled;
  final String? staffMemberId;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final day in days)
          if (grid.isOnSchedule(row, day))
            _GridCell(
              key: ValueKey('cell-${row.staffMemberId}-${_dateKey(day)}'),
              day: day,
              today: today,
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
              dragCell: _DraggedCell(row, day),
              canDrag:
                  dragEnabled &&
                  editable.contains(row.sectionId) &&
                  (grid.shiftCodeFor(row.staffMemberId, day) ?? '').isNotEmpty,
              canReceive: dragEnabled && editable.contains(row.sectionId),
              onDrop: onDrop,
              onDragUpdate: onDragUpdate,
              onDragStop: onDragStop,
            )
          else
            // After their Last day: no longer on the Schedule.
            Container(
              key: ValueKey('gone-${row.staffMemberId}-${_dateKey(day)}'),
              width: _dayWidth,
              height: _cellHeight,
              decoration: _isToday(day, today)
                  ? _cellDecoration(day, context, today)
                  : _cellDecoration(day, context, today).copyWith(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
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
    required this.today,
    required this.code,
    required this.unannounced,
    required this.unannouncedKey,
    required this.changed,
    required this.changedKey,
    required this.onTap,
    this.dragCell,
    this.canDrag = false,
    this.canReceive = false,
    this.onDrop,
    this.onDragUpdate,
    this.onDragStop,
  });

  final DateTime day;
  final DateTime today;
  final String code;
  final bool unannounced;
  final Key unannouncedKey;
  final bool changed;
  final Key changedKey;
  final VoidCallback onTap;
  final _DraggedCell? dragCell;
  final bool canDrag;
  final bool canReceive;
  final _OnDrop? onDrop;
  final ValueChanged<Offset>? onDragUpdate;
  final VoidCallback? onDragStop;

  @override
  Widget build(BuildContext context) {
    final decoration = _cellDecoration(day, context, today);
    final cell = InkWell(
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
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: unannounced || changed
                ? null
                : _todayTextStyle(day, today, context)?.color,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
    final location = dragCell;
    if (location == null) return cell;
    final feedback = Material(
      elevation: 4,
      child: SizedBox(
        width: _dayWidth,
        height: _cellHeight,
        child: Center(child: Text(code)),
      ),
    );
    final fadedCell = Opacity(opacity: 0.35, child: cell);
    void update(DragUpdateDetails details) =>
        onDragUpdate?.call(details.globalPosition);
    void end(DraggableDetails details) => onDragStop?.call();
    final draggable = canDrag
        ? switch (defaultTargetPlatform) {
            TargetPlatform.android ||
            TargetPlatform.iOS => LongPressDraggable<_DraggedCell>(
              data: location,
              feedback: feedback,
              childWhenDragging: fadedCell,
              onDragUpdate: update,
              onDragEnd: end,
              child: cell,
            ),
            _ => Draggable<_DraggedCell>(
              data: location,
              feedback: feedback,
              childWhenDragging: fadedCell,
              onDragUpdate: update,
              onDragEnd: end,
              child: cell,
            ),
          }
        : cell;
    return DragTarget<_DraggedCell>(
      onWillAcceptWithDetails: (details) =>
          canReceive && !details.data.isSame(location),
      onAcceptWithDetails: (details) {
        final keys = HardwareKeyboard.instance.logicalKeysPressed;
        final copy =
            keys.contains(LogicalKeyboardKey.controlLeft) ||
            keys.contains(LogicalKeyboardKey.controlRight) ||
            keys.contains(LogicalKeyboardKey.altLeft) ||
            keys.contains(LogicalKeyboardKey.altRight);
        onDrop?.call(details.data, location, copy);
      },
      builder: (context, candidates, rejected) => DecoratedBox(
        decoration: BoxDecoration(
          border: candidates.isEmpty
              ? null
              : Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 3,
                ),
        ),
        child: draggable,
      ),
    );
  }
}

class _DayView extends StatelessWidget {
  const _DayView({
    required this.grid,
    required this.today,
    required this.staffing,
    required this.onManageDay,
    required this.day,
    required this.onDayChanged,
    required this.onEdit,
    required this.highlightStaffMemberId,
  });

  final MonthGrid grid;
  final DateTime today;
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
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: _isToday(day, today)
                    ? BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      )
                    : null,
                child: Text(
                  DateFormat.MMMMEEEEd().format(day),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: _todayTextStyle(day, today, context)?.color,
                  ),
                ),
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
                    today: _isToday(entry.date, today),
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
    required this.today,
    required this.staffMemberId,
    required this.onPersonChanged,
    required this.onEdit,
    required this.highlightStaffMemberId,
  });

  final MonthGrid grid;
  final DateTime today;
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
                  today: _isToday(entry.date, today),
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
    required this.today,
    required this.onTap,
    this.highlight = false,
    this.shaded = false,
  });

  final String title;
  final RowDay entry;
  final bool today;
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
      leading: today
          ? Icon(Icons.today, color: colors.primary, semanticLabel: 'Today')
          : null,
      trailing: Text(
        entry.shiftCode,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      tileColor: entry.unannounced || highlight
          ? _changeColor(context)
          : today
          ? colors.secondaryContainer
          : shaded
          ? colors.surfaceContainerHighest
          : null,
      onTap: onTap,
    );
  }
}

BoxDecoration _cellDecoration(
  DateTime day,
  BuildContext context,
  DateTime today,
) {
  final colors = Theme.of(context).colorScheme;
  final isToday = _isToday(day, today);
  return BoxDecoration(
    color: isToday
        ? colors.secondaryContainer
        : _isWeekend(day)
        ? colors.surfaceContainerHighest
        : colors.surface,
    border: Border.all(
      color: isToday ? colors.primary : Theme.of(context).dividerColor,
      width: isToday ? 2 : 1,
    ),
  );
}

TextStyle? _todayTextStyle(
  DateTime day,
  DateTime today,
  BuildContext context,
) => _isToday(day, today)
    ? TextStyle(color: Theme.of(context).colorScheme.onSecondaryContainer)
    : null;

bool _isToday(DateTime day, DateTime today) =>
    day.year == today.year && day.month == today.month && day.day == today.day;

DateTime _dateOnly(DateTime day) => DateTime(day.year, day.month, day.day);

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
