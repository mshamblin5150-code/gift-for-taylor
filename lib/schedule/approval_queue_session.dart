// Public constructor names stay distinct from the private dependencies.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:schedule_rules/schedule_rules.dart';

import '../staff/staff_gateway.dart';
import 'pending_approvals.dart';

typedef ApprovalQueueTimerFactory = Timer Function(
  Duration interval,
  void Function(Timer) callback,
);

@immutable
final class ApprovalQueueState {
  const ApprovalQueueState({
    this.pending,
    this.openShifts = const [],
    this.grids = const {},
    this.loadError,
    this.busy = false,
  });

  final PendingApprovals? pending;
  final List<OpenShift> openShifts;
  final Map<DateTime, MonthGrid> grids;
  final Object? loadError;
  final bool busy;
}

sealed class ApprovalDecisionOutcome {
  const ApprovalDecisionOutcome();
}

final class ApprovalDecisionSucceeded extends ApprovalDecisionOutcome {
  const ApprovalDecisionSucceeded();
}

final class ApprovalDecisionFailed extends ApprovalDecisionOutcome {
  const ApprovalDecisionFailed();
}

/// Owns the approval queue's reads, polling, and decision commands.
final class ApprovalQueueSession extends ChangeNotifier {
  ApprovalQueueSession({
    required ScheduleRules rules,
    required SwapStore swapStore,
    required GiveawayStore giveawayStore,
    required OpenShiftStore openShiftStore,
    StaffGateway? staffGateway,
    VoidCallback? onAccessRejected,
    ApprovalQueueTimerFactory? timerFactory,
  }) : _rules = rules,
       _swapStore = swapStore,
       _giveawayStore = giveawayStore,
       _openShiftStore = openShiftStore,
       _staffGateway = staffGateway,
       _onAccessRejected = onAccessRejected {
    _timer = (timerFactory ?? Timer.periodic)(const Duration(seconds: 15), (_) {
      unawaited(refresh());
    });
    unawaited(refresh());
  }

  final ScheduleRules _rules;
  final SwapStore _swapStore;
  final GiveawayStore _giveawayStore;
  final OpenShiftStore _openShiftStore;
  final StaffGateway? _staffGateway;
  final VoidCallback? _onAccessRejected;
  ApprovalQueueState _state = const ApprovalQueueState();
  ApprovalQueueState get state => _state;
  Timer? _timer;
  bool _disposed = false;
  int _read = 0;

  Future<void> refresh() async {
    if (_state.busy) return;
    final read = ++_read;
    try {
      final values = await (
        readPendingApprovals(
          _rules,
          _swapStore,
          _openShiftStore,
          _giveawayStore,
          _staffGateway,
        ),
        _openShiftStore.openShifts(),
      ).wait;
      final pending = values.$1;
      final openShifts = values.$2;
      final shiftById = {for (final shift in openShifts) shift.id: shift};
      final months = <DateTime>{
        for (final swap in pending.swaps)
          for (final shift in swap.requesterShifts) _month(shift.date),
        for (final swap in pending.swaps)
          for (final shift in swap.colleagueShifts) _month(shift.date),
        for (final pickup in pending.pickups)
          if (shiftById[pickup.openShiftId] case final shift?)
            _month(shift.date),
        for (final giveaway in pending.giveaways)
          for (final shift in giveaway.shifts) _month(shift.date),
      };
      final grids = <DateTime, MonthGrid>{};
      await Future.wait(
        months.map((month) async {
          grids[month] = await _rules.monthGrid(month);
        }),
      );
      if (_disposed || read != _read) return;
      _replace(
        ApprovalQueueState(
          pending: pending,
          openShifts: List.unmodifiable(openShifts),
          grids: Map.unmodifiable(grids),
        ),
      );
    } catch (error) {
      if (_disposed || read != _read) return;
      _rejected(error);
      _replace(
        ApprovalQueueState(
          pending: _state.pending,
          openShifts: _state.openShifts,
          grids: _state.grids,
          loadError: error,
          busy: _state.busy,
        ),
      );
    }
  }

  Future<ApprovalDecisionOutcome> decideRequestOff(
    String requestId,
    RequestOffDecision decision,
    String? reason,
  ) => _write(() => _rules.store.decideRequestOff(requestId, decision, reason));

  Future<ApprovalDecisionOutcome> decideSwap(
    String swapId, {
    required bool approve,
    String? reason,
  }) => _write(
    () => approve
        ? _swapStore.approveSwap(swapId)
        : _swapStore.declineSwap(swapId, reason: reason),
  );

  Future<ApprovalDecisionOutcome> decideGiveaway(
    String giveawayId, {
    required bool approve,
    String? reason,
  }) => _write(
    () => approve
        ? _giveawayStore.approveGiveaway(giveawayId)
        : _giveawayStore.declineGiveaway(giveawayId, reason: reason),
  );

  Future<ApprovalDecisionOutcome> decidePickup(
    String pickupId, {
    required bool approve,
    String? reason,
  }) => _write(
    () => approve
        ? _openShiftStore.approvePickup(pickupId)
        : _openShiftStore.declinePickup(pickupId, reason: reason),
  );

  Future<ApprovalDecisionOutcome> decideInvite(
    String inviteId, {
    required bool confirm,
  }) => _write(() {
    final gateway = _staffGateway;
    if (gateway == null) throw StateError('Staff access is unavailable.');
    return confirm
        ? gateway.confirmInviteAcceptance(inviteId)
        : gateway.rejectInviteAcceptance(inviteId);
  });

  Future<ApprovalDecisionOutcome> _write(
    Future<void> Function() command,
  ) async {
    if (_state.busy) return const ApprovalDecisionFailed();
    _setBusy(true);
    try {
      await command();
      _setBusy(false);
      await refresh();
      return const ApprovalDecisionSucceeded();
    } catch (error) {
      _rejected(error);
      return const ApprovalDecisionFailed();
    } finally {
      _setBusy(false);
    }
  }

  void _rejected(Object error) {
    if (error is AccessRejected) _onAccessRejected?.call();
  }

  void _setBusy(bool busy) => _replace(
    ApprovalQueueState(
      pending: _state.pending,
      openShifts: _state.openShifts,
      grids: _state.grids,
      loadError: _state.loadError,
      busy: busy,
    ),
  );

  void _replace(ApprovalQueueState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

DateTime _month(DateTime date) => DateTime(date.year, date.month);
