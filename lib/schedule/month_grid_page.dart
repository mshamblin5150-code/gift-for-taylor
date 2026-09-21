import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../help/help_page.dart';
import '../notifications/notice_gateway.dart';
import '../notifications/notices_page.dart';
import '../schedule_theme.dart';
import '../staff/staff_gateway.dart';
import '../settings/settings_page.dart';

import 'announce_sheet.dart';
import 'approval_queue_page.dart';
import 'cell_edit_sheet.dart';
import 'change_log_page.dart';
import 'messages_composer.dart';
import 'print_wording_dialog.dart';
import 'print_wording_gateway.dart';
import 'swaps_page.dart';
import 'open_shifts_page.dart';
import 'requests_off_page.dart';
import 'shift_codes_page.dart';
import 'staffing_sheet.dart';

enum ScheduleView { month, day, person }

final class _ScheduleAction {
  const _ScheduleAction({
    required this.label,
    required this.icon,
    this.onPressed,
    this.badgeCount = 0,
    this.children,
    this.secondary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final int badgeCount;
  final List<_ScheduleAction>? children;
  final bool secondary;

  String get menuLabel => badgeCount > 0 ? '$label ($badgeCount)' : label;
}

typedef _MonthRead = ({
  MonthGrid grid,
  ChangeAnnouncement? announcement,
  List<LegendCode> codes,
  List<SectionStaffing> staffing,
  ({int count, DateTime month})? unreached,
});

class MonthGridPage extends StatefulWidget {
  const MonthGridPage({
    super.key,
    required this.rules,
    required this.month,
    this.viewerId,
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
    this.staffGateway,
    this.printBookPage,
    this.printWordingGateway,
    this.now,
  });

  final ScheduleRules rules;
  final DateTime month;

  /// Stable signed-in account identity for device-local Schedule layout.
  final String? viewerId;
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
  final StaffGateway? staffGateway;

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
  int _pendingApprovals = 0;
  Timer? _requestNoticeTimer;
  Timer? _midnightTimer;
  late DateTime _today = _dateOnly(_now());
  MonthGrid? _grid;
  List<LegendCode> _shiftCodes = const [];
  List<SectionStaffing> _staffing = [];
  ChangeAnnouncement? _announcement;
  ({int count, DateTime month})? _unreached;
  PrintWording? _wording;
  bool _savingDrop = false;

  /// The Manager: may confirm the month and manage the Night scheduler.
  bool _isManager = false;
  String? _currentRole;
  bool _canManageUnit = false;
  EditableSections _editable = const EditableSections.only({});
  Object? _loadError;
  int _unreadRequests = 0;
  late ScheduleView _view = widget.staffMemberId == null
      ? ScheduleView.month
      : ScheduleView.person;
  late DateTime _day = _defaultDay();
  late String? _personId = _signedInStaffMemberId;

  // Night schedulers keep the full Month view, but are still Staff members.
  String? get _signedInStaffMemberId =>
      widget.staffMemberId ?? widget.swapStaffMemberId;

  @override
  void initState() {
    super.initState();
    _scheduleMidnight();
    _listen();
    if (widget.swapRules case final swapRules?) {
      _swapUpdates = swapRules.updates().listen((_) {
        _refreshSwaps();
        _refreshApprovals();
      });
    }
    if (widget.openShiftRules case final openShiftRules?) {
      _openShiftUpdates = openShiftRules.updates().listen((_) {
        _reload();
        _refreshApprovals();
      });
    }
    _load();
    _loadWording();
    _requestNoticeTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _refreshRequestNotices();
      _refreshApprovals();
    });
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
      _reload();
      _scheduleMidnight();
    });
  }

  Future<void> _load() {
    _refreshRequestNotices();
    return _readMonth(initial: true);
  }

  Future<void> _reload() => _readMonth(initial: false);

  Future<void> _readMonth({required bool initial}) async {
    try {
      final month = _month;
      var editable = _editable;
      var isManager = _isManager;
      var currentRole = _currentRole;
      var canManageUnit = _canManageUnit;
      if (initial) {
        (isManager, editable, currentRole) = await (
          widget.rules.canEditSchedule(),
          widget.rules.editableSections(),
          widget.staffGateway?.currentStaffRole() ??
              Future<String?>.value(null),
        ).wait;
        canManageUnit = isManager || currentRole == 'administrator';
      }
      final read = await _read(month, editable, isManager);
      if (!mounted || month != _month) return;
      setState(() {
        if (initial) {
          _isManager = isManager;
          _canManageUnit = canManageUnit;
          _editable = editable;
          _currentRole = currentRole;
          _loadError = null;
        }
        _grid = read.grid;
        _shiftCodes = read.codes;
        _staffing = read.staffing;
        _announcement = read.announcement;
        _unreached = read.unreached;
      });
      if (initial) {
        _refreshSwaps();
        _refreshApprovals();
      }
    } catch (error) {
      if (initial) {
        if (mounted) setState(() => _loadError = error);
      } else {
        // The next save or update reloads again.
      }
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
                  swap.status == SwapStatus.proposed &&
                  swap.colleagueId == widget.swapStaffMemberId,
            )
            .length,
      );
    } catch (_) {
      // Schedule access still works if the Swap inbox is temporarily unavailable.
    }
  }

  Future<void> _refreshApprovals() async {
    if (!_isManager ||
        widget.swapRules == null ||
        widget.openShiftRules == null) {
      return;
    }
    try {
      final pending = await readPendingApprovals(
        widget.rules,
        widget.swapRules!,
        widget.openShiftRules!,
        widget.staffGateway,
      );
      if (mounted) {
        setState(() => _pendingApprovals = pending.count);
      }
    } catch (_) {
      // A temporary queue read failure must not hide the Schedule.
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

  Future<void> _openStaffDetails(String staffMemberId) async {
    await widget.onOpenStaffDetails?.call(staffMemberId);
    if (mounted) await _reload();
  }

  /// The grid, the unannounced tray for an editor, active Shift codes, and
  /// Section staffing.
  ///
  /// The grid and the tray are the Schedule and the promise to announce its
  /// changes, so either failing stops the month from opening. Both read the
  /// same Schedule the grid does, so neither can fail on its own.
  ///
  /// The Shift code legend and Section staffing are adjuncts: each is a
  /// separate backend call a Schedule can be read without, and each has an
  /// honest empty state — no legend to pick from, no minimums to fall short
  /// of. An older database missing either must not take the month down with
  /// it. The tray is deliberately not among them: no tray reads as "everyone
  /// has been told", which is a claim, not an absence.
  Future<_MonthRead> _read(
    DateTime month,
    EditableSections editable,
    bool isManager,
  ) async {
    // Started together so nothing here costs an extra round trip.
    final gridRead = widget.rules.monthGrid(month);
    final announcementRead = editable.isEmpty
        ? Future<ChangeAnnouncement?>.value()
        : widget.rules.changeAnnouncement(month);
    final codesRead = _adjunct(widget.rules.shiftCodes, const <LegendCode>[]);
    final staffingRead = _adjunct(
      () async =>
          await widget.openShiftRules?.staffingForMonth(month) ??
          const <SectionStaffing>[],
      const <SectionStaffing>[],
    );
    final unreachedRead = isManager
        ? _readUnreachedThisWeek()
        : Future<({int count, DateTime month})?>.value();
    // Waits for both required reads whichever fails, so a failure on one side
    // leaves no unobserved error on the other, and reports the error itself
    // rather than a wrapper.
    final required = await Future.wait<Object?>([gridRead, announcementRead]);
    return (
      grid: required[0]! as MonthGrid,
      announcement: required[1] as ChangeAnnouncement?,
      codes: await codesRead,
      staffing: await staffingRead,
      unreached: await unreachedRead,
    );
  }

  Future<({int count, DateTime month})?> _readUnreachedThisWeek() async {
    final today = _today;
    final end = today.add(Duration(days: 7 - today.weekday));
    final month = DateTime(today.year, today.month);
    final lastMonth = DateTime(end.year, end.month);
    final logs = await Future.wait([
      widget.rules.changeLogView(month, unreachedOnly: true),
      if (lastMonth != month)
        widget.rules.changeLogView(lastMonth, unreachedOnly: true),
    ]);
    final changes = logs.expand((log) => log);
    final upcoming = changes.where((change) {
      final date = _dateOnly(change.date);
      return !date.isBefore(today) && !date.isAfter(end);
    }).toList();
    if (upcoming.isEmpty) return null;
    return (
      count: upcoming.map((change) => change.staffMemberId).toSet().length,
      month: month,
    );
  }

  Future<void> _announce(ChangeAnnouncement announcement) async {
    final draftOpenedStaffMemberIds = announcement.people.isEmpty
        ? <String>{}
        : await showAnnounceSheet(
            context,
            announcement: announcement,
            messagesComposer: widget.messagesComposer,
          );
    if (draftOpenedStaffMemberIds == null) return;
    try {
      await widget.rules.markAnnounced(
        announcement,
        draftOpenedStaffMemberIds: draftOpenedStaffMemberIds,
      );
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

  Future<void> _managePoolDay(
    RolePool pool,
    CoverageWindow window,
    DateTime date,
  ) async {
    final rules = widget.openShiftRules;
    if (!_isManager || rules == null) return;
    final staffing = _staffingOn(_staffing, pool, window, date);
    if (staffing == null) return;
    final changed = await showStaffingSheet(
      context,
      rules: rules,
      date: date,
      staffing: staffing,
      onStandingMinimums: () =>
          _open((context) => WeekdayMinimumsPage(rules: rules)),
    );
    if (changed == true) await _reload();
  }

  Future<void> _print(ValueChanged<String> printBookPage) async {
    try {
      final wording = await _wordingForMonth();
      if (mounted) setState(() => _wording = wording);
      final grid = await widget.rules.monthGrid(_month);
      final codes = await widget.rules.shiftCodes();
      if (!mounted) return;
      if (bookPageIsHardToRead(grid, wording: wording, codes: codes)) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Small print warning'),
            content: Text(
              'Fitting this Schedule, its title and legend on one sheet '
              'will make the text very small.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Print anyway'),
              ),
            ],
          ),
        );
        if (proceed != true || !mounted) return;
      }
      printBookPage(bookPageHtml(grid, wording: wording, codes: codes));
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
      final wording = await _wordingForMonth();
      if (mounted) setState(() => _wording = wording);
    } catch (_) {
      if (mounted) setState(() => _wording = null);
    }
  }

  Future<PrintWording> _wordingForMonth() async {
    final gateway = widget.printWordingGateway;
    if (gateway is MonthPrintWordingGateway) {
      return gateway.readForMonth(_month);
    }
    return await gateway?.read() ?? const PrintWording();
  }

  Future<void> _changePrintWording() async {
    final gateway = widget.printWordingGateway;
    if (gateway == null) return;
    try {
      final current = await gateway.read();
      if (!mounted) return;
      final next = await showPrintWordingDialog(context, current);
      if (next == null) return;
      await gateway.save(next);
      await _loadWording();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("The print wording wasn't saved. Try again."),
        ),
      );
    }
  }

  Future<void> _correctMonthPrintWording() async {
    final gateway = widget.printWordingGateway;
    if (gateway is! MonthPrintWordingGateway) return;
    final current = await gateway.readForMonth(_month);
    if (!mounted) return;
    final next = await showPrintWordingDialog(
      context,
      current,
      forReleasedMonth: true,
    );
    if (next == null) return;
    try {
      await gateway.correctMonth(_month, next);
      if (mounted) setState(() => _wording = next);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The month wording was not saved.')),
        );
      }
    }
  }

  Future<void> _confirmMonth() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm ${DateFormat.yMMMM().format(_month)}?'),
        content: const Text(
          'Confirming releases this month as the live Schedule.',
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
        .then((_) {
          _refreshRequestNotices();
          _refreshSwaps();
          _refreshApprovals();
        });
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
    if (!_isManager) return null;
    if (grid.awaitingConfirmation) {
      return _Banner(
        message:
            'Proofread this month against the printed Schedule page '
            'it was loaded from. '
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

  List<_ScheduleAction> _appBarActions(BuildContext context) => [
    _ScheduleAction(
      label: 'Settings',
      icon: Icons.settings_outlined,
      secondary: true,
      onPressed: () async {
        final role =
            await widget.staffGateway?.currentStaffRole() ??
            (_isManager ? 'manager' : 'staff_member');
        if (!context.mounted) return;
        _open(
          (context) => SettingsPage(
            scheduleRules: widget.rules,
            openShiftRules: widget.openShiftRules,
            noticeGateway: widget.noticeGateway,
            printWordingGateway: widget.printWordingGateway,
            onCalendarFeed: widget.onCalendarFeed,
            onManageStaff: widget.onManageStaff,
            role: role,
            auditClient: widget.staffGateway is SupabaseStaffGateway
                ? Supabase.instance.client
                : null,
          ),
        );
      },
    ),
    _ScheduleAction(
      label: 'Help',
      icon: Icons.help_outline,
      secondary: true,
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => HelpPage(
            role: helpRoleForAccess(
              _currentRole,
              canEditSchedule: _isManager,
              hasEditableSections: !_editable.isEmpty,
            ),
          ),
        ),
      ),
    if (_isManager && widget.swapRules != null && widget.openShiftRules != null)
      _ScheduleAction(
        label: 'Approval queue',
        icon: Icons.fact_check_outlined,
        badgeCount: _pendingApprovals,
        onPressed: () => _open(
          (context) => ApprovalQueuePage(
            rules: widget.rules,
            swapRules: widget.swapRules!,
            openShiftRules: widget.openShiftRules!,
            staffGateway: widget.staffGateway,
          ),
        ),
      ),
    if (!_isManager && widget.openShiftRules != null)
      _ScheduleAction(
        label: 'Open shifts',
        icon: Icons.add_circle_outline,
        onPressed: () => _open(
          (context) => OpenShiftsPage(
            rules: widget.openShiftRules!,
            scheduleRules: widget.rules,
            month: _month,
            staffMemberId: widget.swapStaffMemberId,
            isManager: _isManager,
          ),
        ),
      ),
    if (!_isManager && widget.swapRules != null)
      _ScheduleAction(
        label: 'Swaps',
        icon: Icons.swap_horiz,
        badgeCount: _pendingSwaps,
        onPressed: () => _open(
          (context) => SwapsPage(
            rules: widget.rules,
            swapRules: widget.swapRules!,
            month: _month,
            staffMemberId: widget.swapStaffMemberId,
            isManager: _isManager,
            messagesComposer: widget.messagesComposer,
          ),
        ),
      ),
    if (widget.noticeGateway case final gateway?)
      _ScheduleAction(
        label: 'Notices',
        icon: Icons.notifications_outlined,
        secondary: true,
        onPressed: () => _open((context) => NoticesPage(gateway: gateway)),
      ),
    if (widget.onCalendarFeed != null)
      _ScheduleAction(
        label: 'My calendar',
        icon: Icons.calendar_month_outlined,
        secondary: true,
        onPressed: widget.onCalendarFeed,
      ),
    if (!_isManager)
      _ScheduleAction(
        label: 'My Requests off',
        icon: Icons.event_busy_outlined,
        badgeCount: _unreadRequests,
        onPressed: () => _open(
          (context) =>
              RequestsOffPage(rules: widget.rules, isManager: _isManager),
        ),
      ),
    if (_isManager)
      _ScheduleAction(
        label: 'Browse requests',
        icon: Icons.more_horiz,
        children: [
          _ScheduleAction(
            label: 'Requests off',
            icon: Icons.event_busy_outlined,
            onPressed: () => _open(
              (context) =>
                  RequestsOffPage(rules: widget.rules, isManager: true),
            ),
          ),
          if (widget.swapRules != null)
            _ScheduleAction(
              label: 'Swaps',
              icon: Icons.swap_horiz,
              onPressed: () => _open(
                (context) => SwapsPage(
                  rules: widget.rules,
                  swapRules: widget.swapRules!,
                  month: _month,
                  staffMemberId: widget.swapStaffMemberId,
                  isManager: true,
                  messagesComposer: widget.messagesComposer,
                ),
              ),
            ),
          if (widget.openShiftRules != null)
            _ScheduleAction(
              label: 'Open shifts',
              icon: Icons.add_circle_outline,
              onPressed: () => _open(
                (context) => OpenShiftsPage(
                  rules: widget.openShiftRules!,
                  scheduleRules: widget.rules,
                  month: _month,
                  staffMemberId: widget.swapStaffMemberId,
                  isManager: true,
                  onApprovalSettings: () => _open(
                    (context) =>
                        ApprovalDefaultPage(rules: widget.openShiftRules!),
                  ),
                ),
              ),
            ),
        ],
      ),
    if (_isManager)
      _ScheduleAction(
        label: 'Manage Shift codes',
        icon: Icons.schedule_outlined,
        secondary: true,
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => ShiftCodesPage(rules: widget.rules),
            ),
          );
          if (mounted) await _load();
        },
      ),
    if (_isManager || _currentRole == 'administrator')
      _ScheduleAction(
        label: 'Change log',
        icon: Icons.history,
        secondary: true,
        onPressed: () => _open(
          (context) => ChangeLogPage(rules: widget.rules, month: _month),
        ),
      ),
    if (widget.printBookPage case final printBookPage?)
      _ScheduleAction(
        label: _wording?.tooltip ?? 'Loading print wording',
        icon: Icons.print_outlined,
        onPressed: _wording == null ? null : () => _print(printBookPage),
      ),
    if (_canManageUnit && widget.printWordingGateway != null)
      _ScheduleAction(
        label: 'Change print wording',
        icon: Icons.text_fields_outlined,
        onPressed: _wording == null ? null : _changePrintWording,
      ),
    if (_canManageUnit &&
        _grid?.status == MonthStatus.released &&
        widget.printWordingGateway is MonthPrintWordingGateway)
      _ScheduleAction(
        label: 'Correct this month’s print wording',
        icon: Icons.edit_note_outlined,
        secondary: true,
        onPressed: _correctMonthPrintWording,
      ),
    if (widget.onManageStaff != null)
      _ScheduleAction(
        label: 'Manage Staff list',
        icon: Icons.people_outline,
        secondary: true,
        onPressed: () async {
          await widget.onManageStaff?.call();
          if (mounted) await _load();
        },
      ),
    if (widget.onSignOut != null)
      _ScheduleAction(
        label: 'Sign out',
        icon: Icons.logout,
        secondary: true,
        onPressed: widget.onSignOut,
      ),
  ];

  PopupMenuItem<_ScheduleAction> _actionMenuItem(_ScheduleAction action) =>
      PopupMenuItem<_ScheduleAction>(
        value: action,
        enabled: action.onPressed != null,
        child: Row(
          children: [
            Icon(action.icon),
            const SizedBox(width: 12),
            Flexible(child: Text(action.menuLabel)),
          ],
        ),
      );

  Widget _desktopAction(_ScheduleAction action) {
    if (action.children case final children?) {
      return PopupMenuButton<_ScheduleAction>(
        tooltip: action.label,
        icon: Icon(action.icon),
        onSelected: (selected) => selected.onPressed?.call(),
        itemBuilder: (context) => [
          for (final child in children) _actionMenuItem(child),
        ],
      );
    }
    return IconButton(
      tooltip: action.label,
      onPressed: action.onPressed,
      icon: action.badgeCount > 0
          ? Badge(label: Text('${action.badgeCount}'), child: Icon(action.icon))
          : Icon(action.icon),
    );
  }

  Widget _compactActions(List<_ScheduleAction> actions) =>
      PopupMenuButton<_ScheduleAction>(
        tooltip: 'Schedule actions',
        icon: const Icon(Icons.more_vert),
        onSelected: (selected) => selected.onPressed?.call(),
        itemBuilder: (context) => [
          for (final action in actions)
            if (action.children case final children?) ...[
              PopupMenuItem<_ScheduleAction>(
                enabled: false,
                child: Text(action.label),
              ),
              for (final child in children) _actionMenuItem(child),
            ] else
              _actionMenuItem(action),
        ],
      );

  Widget _desktopActionsMenu(List<_ScheduleAction> actions) =>
      PopupMenuButton<_ScheduleAction>(
        tooltip: 'More destinations',
        icon: const Icon(Icons.more_vert),
        onSelected: (selected) => selected.onPressed?.call(),
        itemBuilder: (context) => [
          for (final action in actions) _actionMenuItem(action),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final appBarActions = _appBarActions(context);
    final secondaryActions = appBarActions
        .where((action) => action.secondary)
        .toList();
    final immediateActions = appBarActions
        .where((action) => !secondaryActions.contains(action))
        .toList();
    final compactActions =
        MediaQuery.sizeOf(context).width < 600 ||
        MediaQuery.sizeOf(context).width < 288 + immediateActions.length * 48;
    final grid = _grid;
    final announcement = _announcement;
    final unreached = _unreached;
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
            Flexible(
              child: Text(
                DateFormat.yMMMM().format(_month),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: () => _goToMonth(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        actions: compactActions
            ? [_compactActions(appBarActions)]
            : [
                for (final action in immediateActions) _desktopAction(action),
                _desktopActionsMenu(secondaryActions),
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
            else if (announcement != null && announcement.hasPendingChanges)
              _AnnounceTray(
                changeCount: announcement.changeCount,
                onlyReverted: announcement.people.isEmpty,
                onAnnounce: () => _announce(announcement),
              ),
            if (_isManager && unreached != null)
              ListTile(
                title: Text(
                  unreached.count == 1
                      ? "1 person wasn't reached about changes this week"
                      : "${unreached.count} people weren't reached about changes this week",
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(
                  (context) => ChangeLogPage(
                    rules: widget.rules,
                    month: unreached.month,
                    unreachedOnly: true,
                    weekStart: _today,
                  ),
                ),
              ),
            if (!_isManager)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _open(
                    (context) =>
                        ShiftCodesPage(rules: widget.rules, readOnly: true),
                  ),
                  icon: const Icon(Icons.schedule_outlined),
                  label: const Text('Shift code legend'),
                ),
              ),
            Expanded(child: _body(grid)),
          ],
        ),
      ),
    );
  }

  void _retry() {
    setState(() => _loadError = null);
    _load();
  }

  Widget _body(MonthGrid? grid) {
    return switch ((grid, _loadError)) {
      (null, null) => const Center(child: CircularProgressIndicator()),
      (null, final error?) => _LoadFailure(error: error, onRetry: _retry),
      (final MonthGrid grid, _)
          when _editable.isEmpty && grid.status != MonthStatus.released =>
        Center(
          child: Text(
            "${DateFormat.yMMMM().format(_month)} hasn't been released yet.",
          ),
        ),
      (final MonthGrid grid, _) => switch (_view) {
        ScheduleView.month => _MonthView(
          grid: grid,
          viewerId: widget.viewerId,
          today: _today,
          staffing: _staffing,
          onOpenDay: (day) => setState(() {
            _day = day;
            _view = ScheduleView.day;
          }),
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
          canEdit: !_editable.isEmpty,
          staffMemberId: _signedInStaffMemberId,
          shiftCodes: _shiftCodes,
          staffing: _staffing,
          onManageDay: _managePoolDay,
          day: _day,
          onDayChanged: (day) => setState(() => _day = day),
          onEdit: _edit,
          highlightStaffMemberId: _signedInStaffMemberId,
        ),
        ScheduleView.person => _PersonView(
          grid: grid,
          today: _today,
          canEdit: !_editable.isEmpty,
          shiftCodes: _shiftCodes,
          staffMemberId: _personId ?? grid.rows.firstOrNull?.staffMemberId,
          onPersonChanged: (id) => setState(() => _personId = id),
          onEdit: _edit,
          highlightStaffMemberId: _signedInStaffMemberId,
        ),
      },
    };
  }
}

/// The month itself could not be read. The reason is shown, quietly, because
/// the alternative is a dead end for whoever is asked to fix it.
class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("The Schedule couldn't be loaded."),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
            const SizedBox(height: 16),
            SelectableText(
              '$error',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
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
  const _AnnounceTray({
    required this.changeCount,
    required this.onlyReverted,
    required this.onAnnounce,
  });

  final int changeCount;
  final bool onlyReverted;
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
                onlyReverted
                    ? 'Changes reverted to their announced values'
                    : changeCount == 1
                    ? '1 unannounced change'
                    : '$changeCount unannounced changes',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: onAnnounce,
              child: Text(onlyReverted ? 'Clear reverted changes' : 'Announce'),
            ),
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
  RolePool pool,
  CoverageWindow window,
  DateTime date,
);

SectionStaffing? _staffingOn(
  List<SectionStaffing> staffing,
  RolePool pool,
  CoverageWindow window,
  DateTime day,
) => staffing
    .where(
      (item) =>
          item.pool == pool &&
          item.coverageWindow == window &&
          item.date.year == day.year &&
          item.date.month == day.month &&
          item.date.day == day.day,
    )
    .firstOrNull;

class _MonthView extends StatefulWidget {
  const _MonthView({
    required this.grid,
    required this.viewerId,
    required this.today,
    required this.staffing,
    required this.onOpenDay,
    required this.onEdit,
    required this.onDrop,
    required this.editable,
    required this.dragEnabled,
    required this.onOpenStaffDetails,
    required this.staffMemberId,
  });

  final MonthGrid grid;
  final String? viewerId;
  final DateTime today;
  final List<SectionStaffing> staffing;
  final ValueChanged<DateTime> onOpenDay;
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
  Future<void> _pendingPreferenceWrites = Future<void>.value();
  Set<String> _collapsedSections = {};
  bool _collapseStateReady = false;
  int _preferenceLoad = 0;
  final _headerScroll = ScrollController();
  final _poolScroll = ScrollController();
  final _daysScroll = ScrollController();
  final _verticalScroll = ScrollController();
  Timer? _dragScrollTimer;
  Offset? _dragPointer;

  @override
  void didUpdateWidget(_MonthView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewerId != widget.viewerId) _loadCollapsedSections();
  }

  Future<void> _loadCollapsedSections() async {
    final load = ++_preferenceLoad;
    final viewerId = widget.viewerId;
    if (viewerId == null) {
      setState(() {
        _collapsedSections = {};
        _collapseStateReady = true;
      });
      return;
    }
    setState(() => _collapseStateReady = false);
    Set<String> collapsedSections = {};
    try {
      final preferences = await SharedPreferences.getInstance();
      final prefix = _collapseKeyPrefix(viewerId);
      collapsedSections = {
        for (final key in preferences.getKeys())
          if (key.startsWith(prefix) && preferences.getBool(key) == true)
            key.substring(prefix.length),
      };
    } catch (_) {
      // A failed local preference read must not prevent the Schedule opening.
    }
    if (!mounted || load != _preferenceLoad) return;
    setState(() {
      _collapsedSections = collapsedSections;
      _collapseStateReady = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _showToday());
  }

  void _toggleSection(String sectionId) {
    final viewerId = widget.viewerId;
    final collapsed = !_collapsedSections.contains(sectionId);
    setState(() {
      if (collapsed) {
        _collapsedSections.add(sectionId);
      } else {
        _collapsedSections.remove(sectionId);
      }
    });
    if (viewerId != null) {
      _pendingPreferenceWrites = _pendingPreferenceWrites.then(
        (_) => _saveCollapsedSection(viewerId, sectionId, collapsed),
      );
      unawaited(_pendingPreferenceWrites);
    }
  }

  Future<void> _saveCollapsedSection(
    String viewerId,
    String sectionId,
    bool collapsed,
  ) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(
        '${_collapseKeyPrefix(viewerId)}$sectionId',
        collapsed,
      );
    } catch (_) {
      // The current layout still works if device storage is unavailable.
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCollapsedSections();
    _headerScroll.addListener(() => _syncHorizontalScroll(_headerScroll));
    _poolScroll.addListener(() => _syncHorizontalScroll(_poolScroll));
    _daysScroll.addListener(() => _syncHorizontalScroll(_daysScroll));
    WidgetsBinding.instance.addPostFrameCallback((_) => _showToday());
  }

  void _syncHorizontalScroll(ScrollController source) {
    for (final target in [_headerScroll, _poolScroll, _daysScroll]) {
      if (identical(source, target) || !target.hasClients) continue;
      final offset = source.offset.clamp(
        target.position.minScrollExtent,
        target.position.maxScrollExtent,
      );
      if (target.offset != offset) target.jumpTo(offset);
    }
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
    _poolScroll.dispose();
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
      point.dy < _cellHeight + _visiblePools.length * _bandHeight + 36
          ? -1
          : point.dy > height - 36
          ? 1
          : 0,
    );
  }

  List<RolePool> get _visiblePools {
    final days = widget.grid.days;
    return [
      for (final pool in RolePool.values)
        if (days.any(
          (day) => CoverageWindow.values.any(
            (window) =>
                _staffingOn(widget.staffing, pool, window, day)?.minimum !=
                    null ||
                widget.grid.shortShiftsOn(pool, window, day).isNotEmpty,
          ),
        ))
          pool,
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!_collapseStateReady) {
      return const Center(child: CircularProgressIndicator());
    }
    final days = widget.grid.days;
    final visiblePools = _visiblePools;
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
        if (visiblePools.isNotEmpty)
          Row(
            children: [
              _PoolNames(visiblePools: visiblePools),
              Expanded(
                child: SingleChildScrollView(
                  key: const ValueKey('month-pool-horizontal-scroll'),
                  controller: _poolScroll,
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    children: [
                      for (final pool in visiblePools)
                        _PoolBand(
                          grid: widget.grid,
                          pool: pool,
                          days: days,
                          today: widget.today,
                          staffing: widget.staffing,
                          onOpenDay: widget.onOpenDay,
                        ),
                    ],
                  ),
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
                  collapsedSections: _collapsedSections,
                  onToggleSection: _toggleSection,
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
                          Container(
                            key: ValueKey('section-days-${section.id}'),
                            width: days.length * _dayWidth,
                            height: _sectionBandHeight,
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                  color: ScheduleGridColors.of(context)
                                      .rosterRule,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                          if (!_collapsedSections.contains(section.id))
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

class _PoolNames extends StatelessWidget {
  const _PoolNames({required this.visiblePools});

  final List<RolePool> visiblePools;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final pool in visiblePools)
          Container(
            width: _nameWidth,
            height: _bandHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pool.label,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '− = short by',
                    style: Theme.of(context).textTheme.labelSmall,
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
  const _NameColumn({
    required this.grid,
    required this.collapsedSections,
    required this.onToggleSection,
    required this.onOpenStaffDetails,
  });

  final MonthGrid grid;
  final Set<String> collapsedSections;
  final ValueChanged<String> onToggleSection;
  final Future<void> Function(String)? onOpenStaffDetails;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final section in grid.sections) ...[
          Semantics(
            value: grid.rowsIn(section.id).isEmpty
                ? null
                : collapsedSections.contains(section.id)
                ? 'Collapsed'
                : 'Expanded',
            hint: grid.rowsIn(section.id).isEmpty
                ? null
                : collapsedSections.contains(section.id)
                ? 'Expand Section'
                : 'Collapse Section',
            button: grid.rowsIn(section.id).isNotEmpty,
            child: InkWell(
              onTap: grid.rowsIn(section.id).isEmpty
                  ? null
                  : () => onToggleSection(section.id),
              child: Container(
                key: ValueKey('section-name-${section.id}'),
                width: _nameWidth,
                height: _sectionBandHeight,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: ScheduleGridColors.of(context).rosterRule,
                      width: 2,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    if (grid.rowsIn(section.id).isNotEmpty)
                      Icon(
                        collapsedSections.contains(section.id)
                            ? Icons.arrow_right
                            : Icons.arrow_drop_down,
                        size: 24,
                      ),
                    Expanded(
                      child: Text(
                        section.name,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: ScheduleGridColors.of(context).rosterText,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!collapsedSections.contains(section.id))
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

class _PoolBand extends StatelessWidget {
  const _PoolBand({
    required this.grid,
    required this.pool,
    required this.days,
    required this.today,
    required this.staffing,
    required this.onOpenDay,
  });

  final MonthGrid grid;
  final RolePool pool;
  final List<DateTime> days;
  final DateTime today;
  final List<SectionStaffing> staffing;
  final ValueChanged<DateTime> onOpenDay;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final day in days)
        Builder(
          builder: (context) {
            final windows = [
              for (final window in CoverageWindow.values)
                _staffingOn(staffing, pool, window, day),
            ];
            final shortfall = windows.fold<int>(
              0,
              (sum, item) => sum + (item?.shortCount ?? 0),
            );
            final posted = CoverageWindow.values.fold<int>(
              0,
              (sum, window) =>
                  sum + grid.shortShiftsOn(pool, window, day).length,
            );
            final count = shortfall > posted ? shortfall : posted;
            final notSet =
                windows.every((item) => item?.minimum == null) && posted == 0;
            final gridColors = ScheduleGridColors.of(context);
            final (fill, foreground) = switch ((notSet, count)) {
              (true, _) => (
                Theme.of(context).colorScheme.surfaceContainerHighest,
                Theme.of(context).colorScheme.onSurface,
              ),
              (false, 0) => (gridColors.covered, gridColors.onCovered),
              (false, 1) => (gridColors.shortOne, gridColors.onShortOne),
              _ => (gridColors.shortSeveral, gridColors.onShortSeveral),
            };
            return InkWell(
              key: ValueKey('pool-${pool.value}-${_dateKey(day)}'),
              onTap: () => onOpenDay(day),
              child: Container(
                width: _dayWidth,
                height: _bandHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: fill,
                  border: _isToday(day, today)
                      ? Border.all(color: gridColors.todayOutline, width: 2)
                      : null,
                ),
                child: notSet
                    ? const SizedBox.shrink()
                    : _ShortMarker(
                        key: ValueKey('short-${pool.value}-${_dateKey(day)}'),
                        count: count,
                        color: foreground,
                      ),
              ),
            );
          },
        ),
    ],
  );
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
  const _ShortMarker({super.key, required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Tooltip(
      message: 'Short: $count',
      child: Text(
        '−$count',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
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
    required this.canEdit,
    required this.staffMemberId,
    required this.shiftCodes,
    required this.staffing,
    required this.onManageDay,
    required this.day,
    required this.onDayChanged,
    required this.onEdit,
    required this.highlightStaffMemberId,
  });

  final MonthGrid grid;
  final DateTime today;
  final bool canEdit;
  final String? staffMemberId;
  final List<LegendCode> shiftCodes;
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
    final staffDay = !canEdit && staffMemberId != null;
    final myEntry = staffDay
        ? entries
              .where((entry) => entry.row.staffMemberId == staffMemberId)
              .firstOrNull
        : null;
    final myInterval = myEntry == null
        ? null
        : _shiftInterval(myEntry.shiftCode, shiftCodes);
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
              if (staffDay) ...[
                if (myEntry == null ||
                    !isWorkingShift(myEntry.shiftCode, codes: shiftCodes))
                  const ListTile(title: Text('You are not working'))
                else ...[
                  ListTile(
                    title: Text('Your shift: ${myEntry.shiftCode}'),
                    subtitle: Text(
                      _shiftHours(myEntry.shiftCode, shiftCodes) ??
                          'Hours unavailable',
                    ),
                  ),
                  for (final entry in entries)
                    if (entry.row.staffMemberId != staffMemberId &&
                        isWorkingShift(entry.shiftCode, codes: shiftCodes))
                      if (_overlapMinutes(
                            myInterval,
                            _shiftInterval(entry.shiftCode, shiftCodes),
                          )
                          case final overlap when overlap > 0)
                        ListTile(
                          title: Text(entry.row.displayName),
                          subtitle: Text(
                            '${entry.shiftCode} (${_shiftHours(entry.shiftCode, shiftCodes)}) · ${_overlapLabel(overlap)} together',
                          ),
                          tileColor:
                              _isStaffChange(
                                highlightStaffMemberId,
                                grid,
                                entry.row,
                                entry.date,
                              )
                              ? _changeColor(context)
                              : null,
                        ),
                ],
              ] else ...[
                for (final pool in RolePool.values) ...[
                  _dayGroupHeader(
                    context,
                    pool == RolePool.nurses ? 'Nursing pool' : pool.label,
                    Theme.of(context).colorScheme.primary,
                  ),
                  for (final window in CoverageWindow.values)
                    Builder(
                      builder: (context) {
                        final item = _staffingOn(staffing, pool, window, day);
                        final short = item?.shortCount ?? 0;
                        final rnShort = item?.rnShortCount ?? 0;
                        final summary = item?.minimum == null
                            ? 'not set'
                            : short == 0
                            ? 'Covered'
                            : rnShort == short
                            ? 'Short $short RN'
                            : rnShort > 0
                            ? 'Short $short ${pool.label.toLowerCase()}, $rnShort an RN'
                            : 'Short $short ${pool.label.toLowerCase()}';
                        return ListTile(
                          title: Text('${window.label}: $summary'),
                          subtitle: (item?.openCount ?? 0) == 0
                              ? null
                              : Text('${item?.openCount} posted Open'),
                          leading: short > 0
                              ? Icon(
                                  Icons.warning_amber,
                                  color: Theme.of(context).colorScheme.error,
                                )
                              : null,
                          onTap: () => onManageDay(pool, window, day),
                        );
                      },
                    ),
                ],
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 24),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                  child: Text(
                    'Schedule by Section',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                for (final section in grid.sections) ...[
                  _dayGroupHeader(
                    context,
                    section.name,
                    Theme.of(context).colorScheme.onSurfaceVariant,
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
            ],
          ),
        ),
      ],
    );
  }

  Widget _dayGroupHeader(BuildContext context, String label, Color color) =>
      ListTile(
        shape: Border(top: BorderSide(color: color, width: 2)),
        title: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      );
}

class _PersonView extends StatelessWidget {
  const _PersonView({
    required this.grid,
    required this.today,
    required this.canEdit,
    required this.shiftCodes,
    required this.staffMemberId,
    required this.onPersonChanged,
    required this.onEdit,
    required this.highlightStaffMemberId,
  });

  final MonthGrid grid;
  final DateTime today;
  final bool canEdit;
  final List<LegendCode> shiftCodes;
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
                if (canEdit ||
                    isWorkingShift(entry.shiftCode, codes: shiftCodes))
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

/// Minutes since the Schedule date's midnight, extending into the next day.
(int, int)? _shiftInterval(String shiftCode, List<LegendCode> codes) {
  final legend = _legendFor(shiftCode, codes);
  if (legend?.startTime == null || legend?.endTime == null) return null;
  final start = _clockMinutes(legend!.startTime!);
  var end = _clockMinutes(legend.endTime!);
  if (end <= start) end += 24 * 60;
  return (start, end);
}

int _clockMinutes(String time) =>
    int.parse(time.substring(0, 2)) * 60 + int.parse(time.substring(3, 5));

int _overlapMinutes((int, int)? first, (int, int)? second) {
  if (first == null || second == null) return 0;
  final start = first.$1 > second.$1 ? first.$1 : second.$1;
  final end = first.$2 < second.$2 ? first.$2 : second.$2;
  return end > start ? end - start : 0;
}

String? _shiftHours(String shiftCode, List<LegendCode> codes) {
  final legend = _legendFor(shiftCode, codes);
  return shiftCodeHours(legend?.startTime, legend?.endTime) ?? legend?.hours;
}

LegendCode? _legendFor(String shiftCode, List<LegendCode> codes) {
  final code = shiftCode.trim().toUpperCase();
  return codes.where((item) => item.code == code).firstOrNull;
}

String _overlapLabel(int minutes) {
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (hours == 0) return '$remainder ${remainder == 1 ? 'minute' : 'minutes'}';
  final hourLabel = '$hours ${hours == 1 ? 'hour' : 'hours'}';
  return remainder == 0 ? hourLabel : '$hourLabel $remainder minutes';
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
    ? TextStyle(
        color: Theme.of(context).colorScheme.onSecondaryContainer,
        fontWeight: FontWeight.bold,
      )
    : null;

bool _isToday(DateTime day, DateTime today) =>
    day.year == today.year && day.month == today.month && day.day == today.day;

DateTime _dateOnly(DateTime day) => DateTime(day.year, day.month, day.day);

/// Reads data the Schedule is better with but still readable without, falling
/// back to [orElse] rather than failing the whole month.
///
/// Only for reads whose [orElse] is an honest empty state. Where absence would
/// instead assert something — that there is nothing left to announce, say —
/// the read belongs in the month's required set.
Future<T> _adjunct<T>(Future<T> Function() read, T orElse) async {
  try {
    return await read();
  } catch (_) {
    return orElse;
  }
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
const _bandHeight = 44.0;
const _sectionBandHeight = 48.0;

String _collapseKeyPrefix(String viewerId) =>
    'section-collapse.v1.${Uri.encodeComponent(viewerId)}.';
