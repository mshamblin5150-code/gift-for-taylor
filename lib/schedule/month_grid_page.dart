import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../help/help_page.dart';
import '../notifications/notice_gateway.dart';
import '../maintainer/maintainer_repair.dart';
import '../maintainer/repair_controller.dart';
import '../notifications/notices_page.dart';
import '../schedule_theme.dart';
import '../staff/staff_gateway.dart';
import '../settings/settings_page.dart';
import '../settings/settings_history.dart';

import 'announce_sheet.dart';
import 'approval_queue_page.dart';
import 'book_page_printing.dart';
import 'cell_edit_sheet.dart';
import 'change_log_page.dart';
import 'coverage_settings_page.dart';
import 'messages_composer.dart';
import 'month_session.dart';
import 'print_wording_dialog.dart';
import 'print_wording_gateway.dart';
import 'swaps_page.dart';
import 'open_shifts_page.dart';
import 'pending_work.dart';
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

class MonthGridPage extends StatefulWidget {
  const MonthGridPage({
    super.key,
    required this.rules,
    required this.access,
    required this.month,
    this.onAccessRejected,
    this.viewerId,
    this.staffMemberId,
    this.swapStaffMemberId,
    this.onSignOut,
    this.onCalendarFeed,
    this.onManageStaff,
    this.onOpenStaffDetails,
    this.onManagerTransferred,
    this.messagesComposer,
    this.swapStore,
    this.openShiftStore,
    required this.noticeGateway,
    this.staffGateway,
    this.bookPagePresenter,
    this.printWordingGateway,
    this.settingsHistory,
    required this.repairController,
    this.now,
  });

  final ScheduleRules rules;
  final Access access;
  final DateTime month;
  final VoidCallback? onAccessRejected;

  /// Stable signed-in account identity for device-local Schedule layout.
  final String? viewerId;
  final String? staffMemberId;
  final String? swapStaffMemberId;
  final VoidCallback? onSignOut;
  final VoidCallback? onCalendarFeed;
  final Future<void> Function()? onManageStaff;
  final Future<void> Function(String staffMemberId)? onOpenStaffDetails;
  final VoidCallback? onManagerTransferred;
  final MessagesComposer? messagesComposer;
  final SwapStore? swapStore;
  final OpenShiftStore? openShiftStore;
  final NoticeGateway noticeGateway;
  final StaffGateway? staffGateway;

  final BookPagePresenter? bookPagePresenter;
  final PrintWordingGateway? printWordingGateway;
  final SettingsHistory? settingsHistory;
  final RepairController repairController;
  final DateTime Function()? now;

  @override
  State<MonthGridPage> createState() => _MonthGridPageState();
}

class _MonthGridPageState extends State<MonthGridPage> {
  late DateTime _month = DateTime(widget.month.year, widget.month.month);
  late MonthSession _session;
  late final PendingWork _pendingWork;
  PrintWording? _wording;

  Access get _access => widget.access;

  late ScheduleView _view = widget.staffMemberId == null
      ? ScheduleView.month
      : ScheduleView.person;
  late DateTime _day;
  late String? _personId = _signedInStaffMemberId;

  // Night schedulers keep the full Month view, but are still Staff members.
  String? get _signedInStaffMemberId =>
      widget.staffMemberId ?? widget.swapStaffMemberId;

  @override
  void initState() {
    super.initState();
    _pendingWork = PendingWork(
      rules: widget.rules,
      access: widget.access,
      swapStore: widget.swapStore,
      openShiftStore: widget.openShiftStore,
      staffGateway: widget.staffGateway,
      swapStaffMemberId: widget.swapStaffMemberId,
    );
    _session = _createSession();
    _day = _defaultDay();
    _pendingWork.refresh();
    _session.load();
    _loadWording();
  }

  MonthSession _createSession() => MonthSession(
    rules: widget.rules,
    access: widget.access,
    openShiftStore: widget.openShiftStore,
    month: _month,
    now: widget.now,
    onAccessRejected: widget.onAccessRejected,
  );

  void _goToMonth(int offset) {
    _session.dispose();
    setState(() {
      _month = DateTime(_month.year, _month.month + offset);
      _session = _createSession();
      _day = _defaultDay();
    });
    _session.load();
    _loadWording();
  }

  @override
  void dispose() {
    _session.dispose();
    _pendingWork.dispose();
    super.dispose();
  }

  DateTime _defaultDay() {
    final now = _session.state.today;
    return now.year == _month.year && now.month == _month.month
        ? DateTime(now.year, now.month, now.day)
        : _month;
  }

  Future<void> _openStaffDetails(String staffMemberId) async {
    await widget.onOpenStaffDetails?.call(staffMemberId);
    if (mounted) await _session.refresh();
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
    final outcome = await _session.announce(
      announcement,
      draftOpenedStaffMemberIds,
    );
    if (!mounted) return;
    switch (outcome) {
      case Announced():
        break;
      case AnnounceFailed():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("The changes weren't marked announced. Try again."),
          ),
        );
    }
  }

  Future<void> _edit(ScheduleRow row, DateTime date) async {
    final editable = _session.editableCell(row, date);
    switch (editable) {
      case NotEditable():
        return;
      case MonthNotStarted():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Start ${DateFormat.MMMM().format(_month)} first.'),
          ),
        );
        return;
      case Editable():
        break;
    }
    final edit = await showCellEditSheet(
      context,
      row: row,
      date: date,
      currentCode: editable.currentCode,
      publishedCode: editable.publishedCode,
      codes: _session.state.shiftCodes,
    );
    if (edit == null) return;
    final outcome = await _session.edit(row, date, edit);
    if (!mounted) return;
    switch (outcome) {
      case EditSaved():
        break;
      case EditFailed():
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
    final outcome = await _session.drop(
      CellLocation(source.row, source.date),
      CellLocation(target.row, target.date),
      copy: copy,
    );
    if (!mounted) return;
    switch (outcome) {
      case DropIgnored():
        break;
      case NothingToSwap():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Choose a cell with a Shift code to swap, or hold Ctrl or Option to copy here.',
            ),
          ),
        );
      case DropFailed():
        _showDropError();
      case Swapped(:final undo):
      case Copied(:final undo):
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              outcome is Copied ? 'Shift code copied.' : 'Shift codes swapped.',
            ),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () async {
                final undone = await _session.undoDrop(undo);
                if (!mounted) return;
                switch (undone) {
                  case DropUndone():
                    break;
                  case UndoDropFailed():
                    _showDropError();
                }
              },
            ),
          ),
        );
    }
  }

  void _showDropError() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("The drop wasn't saved. Try again.")),
    );
  }

  Future<void> _managePoolDay(
    CoveragePool pool,
    CoverageWindow window,
    DateTime date,
  ) async {
    final rules = widget.openShiftStore;
    if (!_access.canRunSchedule || rules == null) return;
    final staffing = _staffingOn(_session.state.staffing, pool, window, date);
    if (staffing == null) return;
    final changed = await showStaffingSheet(
      context,
      rules: rules,
      shiftCodes: _session.state.shiftCodes,
      date: date,
      staffing: staffing,
      reading: _session.state.coverage!.day(pool, date).window(window),
      onStandingMinimums: () => _open(
        (context) =>
            CoverageSettingsPage(rules: rules, scheduleRules: widget.rules),
        refreshMonth: true,
      ),
    );
    if (changed == true) await _session.refresh();
  }

  Future<void> _print(BookPagePresenter presenter) async {
    try {
      final page = await BookPagePrinting(
        widget.rules,
        widget.printWordingGateway,
      ).prepare(_month);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Print the book page'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (page.isHardToRead) ...[
                    const Text('Some text will be hard to read:'),
                    for (final cause in page.causes)
                      Text(
                        '• ${cause.description}; prints at '
                        '${cause.effectiveSize.toStringAsFixed(1)}pt',
                      ),
                    const SizedBox(height: 12),
                  ],
                  const Text(
                    'Open the landscape PDF, then print it from your browser’s controls.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  presenter.present(page);
                  Navigator.pop(context);
                } catch (_) {
                  Navigator.pop(context);
                  if (!mounted) return;
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(
                      content: Text("The PDF couldn't be opened. Try again."),
                    ),
                  );
                }
              },
              child: const Text('Open PDF'),
            ),
          ],
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
      final wording = await _wordingForMonth();
      if (mounted) setState(() => _wording = wording);
    } catch (_) {
      if (mounted) setState(() => _wording = null);
    }
  }

  Future<PrintWording> _wordingForMonth() async {
    final gateway = widget.printWordingGateway;
    return await gateway?.readForMonth(_month) ?? const PrintWording();
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
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("The print wording wasn't saved. Try again."),
        ),
      );
      if (error is AccessRejected) widget.onAccessRejected?.call();
    }
  }

  Future<void> _correctMonthPrintWording() async {
    final gateway = widget.printWordingGateway;
    if (gateway == null) return;
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
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The month wording was not saved.')),
        );
        if (error is AccessRejected) widget.onAccessRejected?.call();
      }
    }
  }

  void _open(
    Widget Function(BuildContext context) page, {
    bool refreshMonth = false,
  }) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: page))
        .then((_) {
          _pendingWork.refresh();
          if (mounted && refreshMonth) _session.refresh();
        });
  }

  Future<void> _startMonth({bool empty = false}) async {
    final outcome = await _session.startMonth(empty: empty);
    if (!mounted) return;
    switch (outcome) {
      case Started():
        break;
      case AlreadyStarted():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This month has already been started.')),
        );
      case NoPreviousMonth():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${DateFormat.MMMM().format(_previousMonth)} has no Schedule to start from.',
            ),
          ),
        );
      case StartMonthFailed():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("The month wasn't started. Try again.")),
        );
    }
  }

  Future<void> _reviewMonthRelease() async {
    final outcome = await _session.reviewMonthRelease();
    if (!mounted) return;
    if (outcome is ReviewMonthReleaseFailed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Staffing could not be checked. Try again.'),
        ),
      );
      return;
    }
    final review = (outcome as ReleaseReady).review;
    final shortDays = review.shortfallDays;
    final openDays = review.openShiftDays;
    final verb = review.kind == MonthReleaseKind.loadedMonth
        ? 'Confirm'
        : 'Release';
    String dates(List<DateTime> days) =>
        days.map((day) => DateFormat.MMMd().format(day)).join(', ');
    final lines = [
      if (shortDays.isNotEmpty)
        '${shortDays.length} day${shortDays.length == 1 ? '' : 's'} '
            '${shortDays.length == 1 ? 'is' : 'are'} below a Staffing minimum: '
            '${dates(shortDays)}. I acknowledge these short days.',
      if (openDays.isNotEmpty)
        '${openDays.length}${shortDays.isEmpty ? '' : ' more'} day${openDays.length == 1 ? '' : 's'} '
            '${openDays.length == 1 ? 'has' : 'have'} an Open shift: '
            '${dates(openDays)}.',
      if (shortDays.isEmpty && openDays.isEmpty)
        review.kind == MonthReleaseKind.loadedMonth
            ? 'Confirming releases this month as the live Schedule.'
            : 'This month then becomes the live Schedule that staff can see.',
    ];
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$verb ${DateFormat.yMMMM().format(_month)}?'),
        content: Text(lines.join('\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              shortDays.isEmpty
                  ? verb
                  : 'Acknowledge and ${verb.toLowerCase()}',
            ),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    final released = await _session.releaseMonth(review);
    if (!mounted) return;
    switch (released) {
      case Released():
        break;
      case ReleaseMonthFailed():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "The month wasn't ${review.kind == MonthReleaseKind.loadedMonth ? 'confirmed' : 'released'}. Try again.",
            ),
          ),
        );
    }
  }

  DateTime get _previousMonth => DateTime(_month.year, _month.month - 1);

  Widget? _banner(MonthGrid grid) {
    if (!_access.canRunSchedule) return null;
    final startInstructions = _session.state.previousMonthStarted
        ? 'Start empty or copy last month, lined up by weekday.'
        : 'Start an empty month to enter Shift codes.';
    if (grid.awaitingConfirmation) {
      return _Banner(
        message:
            'Proofread this month against the printed Schedule page '
            'it was loaded from. '
            'Tap any cell to correct it.',
        actionLabel: 'Confirm month',
        onPressed: _reviewMonthRelease,
      );
    }
    return switch (grid.status) {
      MonthStatus.notStarted => _Banner(
        message:
            "${DateFormat.MMMM().format(_month)} hasn't been started. "
            '$startInstructions',
        actionLabel: 'Start empty month',
        onPressed: () => _startMonth(empty: true),
        secondaryActionLabel: _session.state.previousMonthStarted
            ? 'Start from ${DateFormat.MMMM().format(_previousMonth)}'
            : null,
        onSecondaryPressed: _session.state.previousMonthStarted
            ? () => _startMonth()
            : null,
      ),
      MonthStatus.unpublished => _Banner(
        message: "Unpublished: staff can't see this month yet.",
        actionLabel: 'Release month',
        onPressed: _reviewMonthRelease,
      ),
      MonthStatus.released => null,
    };
  }

  List<_ScheduleAction> _appBarActions(
    BuildContext context,
    PendingWorkState pending,
  ) => [
    _ScheduleAction(
      label: 'Settings',
      icon: Icons.settings_outlined,
      secondary: true,
      onPressed: () async {
        if (!context.mounted) return;
        _open(
          (context) => SettingsPage(
            scheduleRules: widget.rules,
            openShiftStore: widget.openShiftStore,
            noticeGateway: widget.noticeGateway,
            printWordingGateway: widget.printWordingGateway,
            onCalendarFeed: widget.onCalendarFeed,
            onManageStaff: widget.onManageStaff,
            staffGateway: widget.staffGateway,
            onManagerTransferred: widget.onManagerTransferred,
            access: _access,
            settingsHistory: widget.settingsHistory,
            maintainerRepairController: widget.repairController,
          ),
        );
      },
    ),
    if (_access.maintainer && !_access.isRepairAccess)
      _ScheduleAction(
        label: 'Maintainer repairs (break glass)',
        icon: Icons.build_outlined,
        secondary: true,
        onPressed: () => _open(
          (context) =>
              MaintainerRepairPage(controller: widget.repairController),
        ),
      ),
    if (_access.maintainer && !_access.isRepairAccess) ...[
      _ScheduleAction(
        label: 'Schedule and Month controls (requires Repair)',
        icon: Icons.lock_outline,
        secondary: true,
        onPressed: () => _open(
          (context) =>
              MaintainerRepairPage(controller: widget.repairController),
        ),
      ),
      _ScheduleAction(
        label: 'Approvals (requires Repair)',
        icon: Icons.lock_outline,
        secondary: true,
        onPressed: () => _open(
          (context) =>
              MaintainerRepairPage(controller: widget.repairController),
        ),
      ),
      _ScheduleAction(
        label: 'Staff and Invite changes (requires Repair)',
        icon: Icons.lock_outline,
        secondary: true,
        onPressed: () => _open(
          (context) =>
              MaintainerRepairPage(controller: widget.repairController),
        ),
      ),
    ],
    _ScheduleAction(
      label: 'Help',
      icon: Icons.help_outline,
      secondary: true,
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => HelpPage(roles: helpRolesFor(_access)),
        ),
      ),
    ),
    if (_access.canRunSchedule &&
        widget.swapStore != null &&
        widget.openShiftStore != null)
      _ScheduleAction(
        label: 'Approval queue',
        icon: Icons.fact_check_outlined,
        badgeCount: pending.pendingApprovals,
        onPressed: () => _open(
          (context) => ApprovalQueuePage(
            rules: widget.rules,
            swapStore: widget.swapStore!,
            openShiftStore: widget.openShiftStore!,
            staffGateway: widget.staffGateway,
          ),
        ),
      ),
    if (!_access.canRunSchedule &&
        _access.ownStaffMemberId != null &&
        widget.openShiftStore != null)
      _ScheduleAction(
        label: 'Open shifts',
        icon: Icons.add_circle_outline,
        onPressed: () => _open(
          (context) => OpenShiftsPage(
            rules: widget.openShiftStore!,
            scheduleRules: widget.rules,
            month: _month,
            staffMemberId: widget.swapStaffMemberId,
            isManager: _access.canRunSchedule,
          ),
        ),
      ),
    if (!_access.canRunSchedule &&
        _access.ownStaffMemberId != null &&
        widget.swapStore != null)
      _ScheduleAction(
        label: 'Swaps',
        icon: Icons.swap_horiz,
        badgeCount: pending.pendingSwaps,
        onPressed: () => _open(
          (context) => SwapsPage(
            rules: widget.rules,
            swapStore: widget.swapStore!,
            month: _month,
            staffMemberId: widget.swapStaffMemberId,
            isManager: _access.canRunSchedule,
            messagesComposer: widget.messagesComposer,
          ),
        ),
      ),
    if (_access.ownStaffMemberId != null)
      _ScheduleAction(
        label: 'Notices',
        icon: Icons.notifications_outlined,
        secondary: true,
        onPressed: () =>
            _open((context) => NoticesPage(gateway: widget.noticeGateway)),
      ),
    if (_access.ownStaffMemberId != null && widget.onCalendarFeed != null)
      _ScheduleAction(
        label: 'My calendar',
        icon: Icons.calendar_month_outlined,
        secondary: true,
        onPressed: widget.onCalendarFeed,
      ),
    if (!_access.canRunSchedule && _access.ownStaffMemberId != null)
      _ScheduleAction(
        label: 'My Requests off',
        icon: Icons.event_busy_outlined,
        badgeCount: pending.unreadRequestsOff,
        onPressed: () => _open(
          (context) => RequestsOffPage(
            rules: widget.rules,
            isManager: _access.canRunSchedule,
          ),
        ),
      ),
    if (_access.canRunSchedule)
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
          if (widget.swapStore != null)
            _ScheduleAction(
              label: 'Swaps',
              icon: Icons.swap_horiz,
              onPressed: () => _open(
                (context) => SwapsPage(
                  rules: widget.rules,
                  swapStore: widget.swapStore!,
                  month: _month,
                  staffMemberId: widget.swapStaffMemberId,
                  isManager: true,
                  messagesComposer: widget.messagesComposer,
                ),
              ),
            ),
          if (widget.openShiftStore != null)
            _ScheduleAction(
              label: 'Open shifts',
              icon: Icons.add_circle_outline,
              onPressed: () => _open(
                (context) => OpenShiftsPage(
                  rules: widget.openShiftStore!,
                  scheduleRules: widget.rules,
                  month: _month,
                  staffMemberId: widget.swapStaffMemberId,
                  isManager: true,
                  onApprovalSettings: () => _open(
                    (context) =>
                        ApprovalDefaultPage(rules: widget.openShiftStore!),
                  ),
                ),
              ),
            ),
        ],
      ),
    if (_access.canManageUnit && widget.openShiftStore != null)
      _ScheduleAction(
        label: 'Unit coverage settings',
        icon: Icons.tune,
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => CoverageSettingsPage(
                rules: widget.openShiftStore!,
                scheduleRules: widget.rules,
              ),
            ),
          );
          if (mounted) await _session.refresh();
        },
      ),
    if (_access.canRunSchedule)
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
          if (mounted) await _session.refresh();
        },
      ),
    if (_access.canReadChangeLog)
      _ScheduleAction(
        label: 'Change log',
        icon: Icons.history,
        secondary: true,
        onPressed: () => _open(
          (context) => ChangeLogPage(rules: widget.rules, month: _month),
        ),
      ),
    if (widget.bookPagePresenter case final presenter?)
      _ScheduleAction(
        label: _wording?.tooltip ?? 'Loading print wording',
        icon: Icons.print_outlined,
        onPressed: _wording == null ? null : () => _print(presenter),
      ),
    if (_access.canManageUnit && widget.printWordingGateway != null)
      _ScheduleAction(
        label: 'Change print wording',
        icon: Icons.text_fields_outlined,
        onPressed: _wording == null ? null : _changePrintWording,
      ),
    if (_access.canManageUnit &&
        _session.state.grid?.status == MonthStatus.released &&
        widget.printWordingGateway != null)
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
          if (mounted) await _session.refresh();
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_pendingWork, _session]),
    builder: (context, _) => _buildPage(context),
  );

  Widget _buildPage(BuildContext context) {
    final appBarActions = _appBarActions(context, _pendingWork.state);
    final secondaryActions = appBarActions
        .where((action) => action.secondary)
        .toList();
    final immediateActions = appBarActions
        .where((action) => !secondaryActions.contains(action))
        .toList();
    final compactActions =
        MediaQuery.sizeOf(context).width < 600 ||
        MediaQuery.sizeOf(context).width < 288 + immediateActions.length * 48;
    final grid = _session.state.grid;
    final announcement = _session.state.announcement;
    final unreached = _session.state.unreached;
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
            if (_access.canRunSchedule && unreached != null)
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
                    weekStart: _session.state.today,
                  ),
                ),
              ),
            if (!_access.canRunSchedule)
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
    _session.retry();
  }

  Widget _body(MonthGrid? grid) {
    return switch ((grid, _session.state.loadError)) {
      (null, null) => const Center(child: CircularProgressIndicator()),
      (null, final error?) => _LoadFailure(error: error, onRetry: _retry),
      (final MonthGrid grid, _)
          when !_access.canReadUnreleased &&
              grid.status != MonthStatus.released =>
        Center(
          child: Text(
            "${DateFormat.yMMMM().format(_month)} hasn't been released yet.",
          ),
        ),
      (final MonthGrid grid, _) => switch (_view) {
        ScheduleView.month => _MonthView(
          grid: grid,
          coverage: _session.state.coverage!,
          viewerId: widget.viewerId,
          today: _session.state.today,
          onOpenDay: (day) => setState(() {
            _day = day;
            _view = ScheduleView.day;
          }),
          onEdit: _edit,
          onDrop: _drop,
          access: _access,
          dragEnabled:
              grid.status != MonthStatus.notStarted &&
              !_session.state.savingDrop,
          onOpenStaffDetails: widget.onOpenStaffDetails == null
              ? null
              : _openStaffDetails,
          staffMemberId: widget.staffMemberId,
        ),
        ScheduleView.day => _DayView(
          grid: grid,
          coverage: _session.state.coverage!,
          today: _session.state.today,
          canEdit: !_access.editableSections.isEmpty,
          staffMemberId: _signedInStaffMemberId,
          shiftCodes: _session.state.shiftCodes,
          onManageDay: _managePoolDay,
          day: _day,
          onDayChanged: (day) => setState(() => _day = day),
          onEdit: _edit,
          highlightStaffMemberId: _signedInStaffMemberId,
        ),
        ScheduleView.person => _PersonView(
          grid: grid,
          today: _session.state.today,
          canEdit: !_access.editableSections.isEmpty,
          shiftCodes: _session.state.shiftCodes,
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
    this.secondaryActionLabel,
    this.onSecondaryPressed,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onPressed;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryPressed;

  @override
  Widget build(BuildContext context) {
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (secondaryActionLabel case final label?)
          OutlinedButton(onPressed: onSecondaryPressed, child: Text(label)),
        FilledButton(onPressed: onPressed, child: Text(actionLabel)),
      ],
    );
    return ColoredBox(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth < 600
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text(message), const SizedBox(height: 8), actions],
                )
              : Row(
                  children: [
                    Expanded(child: Text(message)),
                    const SizedBox(width: 12),
                    actions,
                  ],
                ),
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
  CoveragePool pool,
  CoverageWindow window,
  DateTime date,
);

SectionStaffing? _staffingOn(
  List<SectionStaffing> staffing,
  CoveragePool pool,
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
    required this.coverage,
    required this.viewerId,
    required this.today,
    required this.onOpenDay,
    required this.onEdit,
    required this.onDrop,
    required this.access,
    required this.dragEnabled,
    required this.onOpenStaffDetails,
    required this.staffMemberId,
  });

  final MonthGrid grid;
  final CoverageReading coverage;
  final String? viewerId;
  final DateTime today;
  final ValueChanged<DateTime> onOpenDay;
  final _OnEdit onEdit;
  final _OnDrop onDrop;
  final Access access;
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

  List<CoveragePool> get _visiblePools => widget.coverage.visiblePools;

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
                          coverage: widget.coverage,
                          pool: pool,
                          days: days,
                          today: widget.today,
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
                                access: widget.access,
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

  final List<CoveragePool> visiblePools;

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
    required this.coverage,
    required this.pool,
    required this.days,
    required this.today,
    required this.onOpenDay,
  });

  final CoverageReading coverage;
  final CoveragePool pool;
  final List<DateTime> days;
  final DateTime today;
  final ValueChanged<DateTime> onOpenDay;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final day in days)
        Builder(
          builder: (context) {
            final reading = coverage.day(pool, day);
            final count = reading.bandNumber;
            final gridColors = ScheduleGridColors.of(context);
            final (fill, foreground) = switch ((reading.state, count)) {
              (CoverageState.notSet, _) => (
                Theme.of(context).colorScheme.surfaceContainerHighest,
                Theme.of(context).colorScheme.onSurface,
              ),
              (CoverageState.covered, _) => (
                gridColors.covered,
                gridColors.onCovered,
              ),
              (_, 1) => (gridColors.shortOne, gridColors.onShortOne),
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
                child: reading.state == CoverageState.notSet
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
    required this.access,
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
  final Access access;
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
                  access.canEditSection(row.sectionId) &&
                  (grid.shiftCodeFor(row.staffMemberId, day) ?? '').isNotEmpty,
              canReceive: dragEnabled && access.canEditSection(row.sectionId),
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
    required this.coverage,
    required this.today,
    required this.canEdit,
    required this.staffMemberId,
    required this.shiftCodes,
    required this.onManageDay,
    required this.day,
    required this.onDayChanged,
    required this.onEdit,
    required this.highlightStaffMemberId,
  });

  final MonthGrid grid;
  final CoverageReading coverage;
  final DateTime today;
  final bool canEdit;
  final String? staffMemberId;
  final List<LegendCode> shiftCodes;
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
                for (final pool in coverage.dayPools(day)) ...[
                  _dayGroupHeader(
                    context,
                    pool.label,
                    Theme.of(context).colorScheme.primary,
                  ),
                  for (final window in CoverageWindow.values)
                    Builder(
                      builder: (context) {
                        final reading = coverage.day(pool, day).window(window);
                        return ListTile(
                          title: Text('${window.label}: ${reading.summary}'),
                          subtitle: reading.openCount == 0
                              ? null
                              : Text('${reading.openCount} posted Open'),
                          leading: reading.shortfall > 0
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
