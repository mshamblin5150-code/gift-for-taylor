// Public constructor names stay distinct from the private dependencies.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:schedule_rules/schedule_rules.dart';

import '../staff/staff_gateway.dart';
import 'pending_approvals.dart';

@immutable
final class PendingWorkState {
  const PendingWorkState({
    this.pendingSwaps = 0,
    this.pendingApprovals = 0,
    this.unreadRequestsOff = 0,
  });

  final int pendingSwaps;
  final int pendingApprovals;
  final int unreadRequestsOff;

  PendingWorkState copyWith({
    int? pendingSwaps,
    int? pendingApprovals,
    int? unreadRequestsOff,
  }) => PendingWorkState(
    pendingSwaps: pendingSwaps ?? this.pendingSwaps,
    pendingApprovals: pendingApprovals ?? this.pendingApprovals,
    unreadRequestsOff: unreadRequestsOff ?? this.unreadRequestsOff,
  );

  @override
  bool operator ==(Object other) =>
      other is PendingWorkState &&
      other.pendingSwaps == pendingSwaps &&
      other.pendingApprovals == pendingApprovals &&
      other.unreadRequestsOff == unreadRequestsOff;

  @override
  int get hashCode =>
      Object.hash(pendingSwaps, pendingApprovals, unreadRequestsOff);
}

typedef PendingWorkTimerFactory = Timer Function(
  Duration interval,
  void Function(Timer) callback,
);

/// Viewer-wide work that remains live while the page changes months.
final class PendingWork extends ChangeNotifier {
  PendingWork({
    required ScheduleRules rules,
    required Access access,
    required String? swapStaffMemberId,
    required GiveawayStore giveawayStore,
    SwapStore? swapStore,
    OpenShiftStore? openShiftStore,
    StaffGateway? staffGateway,
    PendingWorkTimerFactory? timerFactory,
  }) : _rules = rules,
       _access = access,
       _swapStaffMemberId = swapStaffMemberId,
       _swapStore = swapStore,
       _giveawayStore = giveawayStore,
       _openShiftStore = openShiftStore,
       _staffGateway = staffGateway {
    if (swapStore != null) {
      _swapUpdates = swapStore.updates().listen((_) {
        _refreshSwaps();
        _refreshApprovals();
      });
    }
    if (openShiftStore != null) {
      _openShiftUpdates = openShiftStore.updates().listen(
        (_) => _refreshApprovals(),
      );
    }
    _giveawayUpdates = giveawayStore.updates().listen((_) {
      _refreshApprovals();
    });
    _timer = (timerFactory ?? Timer.periodic)(const Duration(seconds: 15), (_) {
      _refreshRequestsOff();
      _refreshApprovals();
    });
  }

  final ScheduleRules _rules;
  final Access _access;
  final String? _swapStaffMemberId;
  final SwapStore? _swapStore;
  final GiveawayStore _giveawayStore;
  final OpenShiftStore? _openShiftStore;
  final StaffGateway? _staffGateway;
  StreamSubscription<void>? _swapUpdates;
  StreamSubscription<void>? _openShiftUpdates;
  StreamSubscription<void>? _giveawayUpdates;
  Timer? _timer;
  bool _disposed = false;

  PendingWorkState _state = const PendingWorkState();
  PendingWorkState get state => _state;

  void _replace(PendingWorkState next) {
    if (_disposed || next == _state) return;
    _state = next;
    notifyListeners();
  }

  Future<void> refresh() async {
    await Future.wait([
      _refreshSwaps(),
      _refreshApprovals(),
      _refreshRequestsOff(),
    ]);
  }

  Future<void> _refreshSwaps() async {
    final swapStore = _swapStore;
    if (swapStore == null) return;
    try {
      final swaps = await swapStore.swaps();
      _replace(
        _state.copyWith(
          pendingSwaps: swaps
              .where(
                (swap) =>
                    swap.status == SwapStatus.proposed &&
                    swap.colleagueId == _swapStaffMemberId,
              )
              .length,
        ),
      );
    } catch (_) {
      // Keep the last count when the Swap inbox is unavailable.
    }
  }

  Future<void> _refreshApprovals() async {
    final swapStore = _swapStore;
    final openShiftStore = _openShiftStore;
    if (!_access.canRunSchedule ||
        swapStore == null ||
        openShiftStore == null) {
      return;
    }
    try {
      final pending = await readPendingApprovals(
        _rules,
        swapStore,
        openShiftStore,
        _giveawayStore,
        _staffGateway,
      );
      _replace(_state.copyWith(pendingApprovals: pending.count));
    } catch (_) {
      // Keep the last count when the approval queue is unavailable.
    }
  }

  Future<void> _refreshRequestsOff() async {
    try {
      final count = await _rules.store.unreadRequestOffNotices();
      _replace(_state.copyWith(unreadRequestsOff: count));
    } catch (_) {
      // Keep the last count when Request off notices are unavailable.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _swapUpdates?.cancel();
    _openShiftUpdates?.cancel();
    _giveawayUpdates?.cancel();
    _timer?.cancel();
    super.dispose();
  }
}
