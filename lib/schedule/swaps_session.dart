// Public constructor names stay distinct from the private dependencies.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:schedule_rules/schedule_rules.dart';

@immutable
final class SwapsSessionState {
  const SwapsSessionState({
    this.grid,
    this.swaps = const [],
    this.loadError,
    this.busy = false,
  });

  final MonthGrid? grid;
  final List<Swap> swaps;
  final Object? loadError;
  final bool busy;
}

sealed class SwapsProposeOutcome {
  const SwapsProposeOutcome();
}

final class SwapsProposed extends SwapsProposeOutcome {
  const SwapsProposed(this.swap);
  final Swap swap;
}

final class SwapsProposalRejected extends SwapsProposeOutcome {
  const SwapsProposalRejected(this.reason);
  final SwapProposalRefusal reason;
}

final class SwapsProposeFailed extends SwapsProposeOutcome {
  const SwapsProposeFailed();
}

sealed class SwapsWriteOutcome {
  const SwapsWriteOutcome();
}

final class SwapsWriteSucceeded extends SwapsWriteOutcome {
  const SwapsWriteSucceeded();
}

final class SwapsWriteFailed extends SwapsWriteOutcome {
  const SwapsWriteFailed();
}

/// Owns the Swaps page's data, liveness and commands.
final class SwapsSession extends ChangeNotifier {
  SwapsSession({
    required ScheduleRules rules,
    required SwapStore swapStore,
    required DateTime month,
    VoidCallback? onAccessRejected,
  }) : _rules = rules,
       _swapStore = swapStore,
       month = DateTime(month.year, month.month),
       _onAccessRejected = onAccessRejected {
    _updates = _swapStore.updates().listen((_) => refresh());
    unawaited(refresh());
  }

  final ScheduleRules _rules;
  final SwapStore _swapStore;
  final DateTime month;
  final VoidCallback? _onAccessRejected;
  SwapsSessionState _state = const SwapsSessionState();
  SwapsSessionState get state => _state;
  StreamSubscription<void>? _updates;
  bool _disposed = false;
  int _read = 0;

  Future<void> refresh() async {
    final read = ++_read;
    try {
      final values = await Future.wait<Object>([
        _rules.monthGrid(month),
        _swapStore.swaps(),
      ]);
      if (_disposed || read != _read) return;
      _replace(
        SwapsSessionState(
          grid: values[0] as MonthGrid,
          swaps: List.unmodifiable(values[1] as List<Swap>),
          busy: _state.busy,
        ),
      );
    } catch (error) {
      if (_disposed || read != _read) return;
      _replace(
        SwapsSessionState(
          grid: _state.grid,
          swaps: _state.swaps,
          loadError: error,
          busy: _state.busy,
        ),
      );
    }
  }

  Future<SwapsProposeOutcome> propose(
    String colleagueId,
    List<DateTime> requesterDates,
    List<DateTime> colleagueDates,
  ) async {
    if (_state.busy) return const SwapsProposeFailed();
    _setBusy(true);
    try {
      final swap = await _swapStore.proposeSwap(
        colleagueId,
        requesterDates,
        colleagueDates,
      );
      await refresh();
      return SwapsProposed(swap);
    } on SwapProposalRefused catch (error) {
      return SwapsProposalRejected(error.reason);
    } catch (error) {
      _rejected(error);
      return const SwapsProposeFailed();
    } finally {
      _setBusy(false);
    }
  }

  Future<SwapsWriteOutcome> answer(
    String swapId, {
    required bool accept,
    String? reason,
  }) => _write(
    () => _swapStore.answerSwap(swapId, accept: accept, reason: reason),
  );

  Future<SwapsWriteOutcome> approve(String swapId) =>
      _write(() => _swapStore.approveSwap(swapId));

  Future<SwapsWriteOutcome> _write(Future<void> Function() command) async {
    if (_state.busy) return const SwapsWriteFailed();
    _setBusy(true);
    try {
      await command();
      await refresh();
      return const SwapsWriteSucceeded();
    } catch (error) {
      _rejected(error);
      return const SwapsWriteFailed();
    } finally {
      _setBusy(false);
    }
  }

  void _rejected(Object error) {
    if (error is AccessRejected) _onAccessRejected?.call();
  }

  void _setBusy(bool busy) => _replace(
    SwapsSessionState(
      grid: _state.grid,
      swaps: _state.swaps,
      loadError: _state.loadError,
      busy: busy,
    ),
  );

  void _replace(SwapsSessionState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _updates?.cancel();
    super.dispose();
  }
}
