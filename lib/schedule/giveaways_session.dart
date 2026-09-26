// Public constructor names stay distinct from the private dependencies.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:schedule_rules/schedule_rules.dart';

@immutable
final class GiveawaysSessionState {
  const GiveawaysSessionState({
    this.grid,
    this.giveaways = const [],
    this.loadError,
    this.busy = false,
  });

  final MonthGrid? grid;
  final List<Giveaway> giveaways;
  final Object? loadError;
  final bool busy;
}

sealed class GiveawaysWriteOutcome {
  const GiveawaysWriteOutcome();
}

final class GiveawaysWriteSucceeded extends GiveawaysWriteOutcome {
  const GiveawaysWriteSucceeded();
}

final class GiveawaysWriteFailed extends GiveawaysWriteOutcome {
  const GiveawaysWriteFailed();
}

/// Owns the Giveaways page's data, liveness, and commands.
final class GiveawaysSession extends ChangeNotifier {
  GiveawaysSession({
    required ScheduleRules rules,
    required GiveawayStore giveawayStore,
    required DateTime month,
    VoidCallback? onAccessRejected,
  }) : _rules = rules,
       _giveawayStore = giveawayStore,
       month = DateTime(month.year, month.month),
       _onAccessRejected = onAccessRejected {
    _updates = _giveawayStore.updates().listen((_) => refresh());
    unawaited(refresh());
  }

  final ScheduleRules _rules;
  final GiveawayStore _giveawayStore;
  final DateTime month;
  final VoidCallback? _onAccessRejected;
  GiveawaysSessionState _state = const GiveawaysSessionState();
  GiveawaysSessionState get state => _state;
  StreamSubscription<void>? _updates;
  bool _disposed = false;
  int _read = 0;

  Future<void> refresh() async {
    final read = ++_read;
    try {
      final values = await Future.wait<Object>([
        _rules.monthGrid(month),
        _giveawayStore.giveaways(),
      ]);
      if (_disposed || read != _read) return;
      _replace(
        GiveawaysSessionState(
          grid: values[0] as MonthGrid,
          giveaways: List.unmodifiable(values[1] as List<Giveaway>),
          busy: _state.busy,
        ),
      );
    } catch (error) {
      if (_disposed || read != _read) return;
      _rejected(error);
      _replace(
        GiveawaysSessionState(
          grid: _state.grid,
          giveaways: _state.giveaways,
          loadError: error,
          busy: _state.busy,
        ),
      );
    }
  }

  Future<GiveawaysWriteOutcome> answer(
    String giveawayId, {
    required bool accept,
    String? reason,
  }) => _write(
    () => _giveawayStore.answerGiveaway(
      giveawayId,
      accept: accept,
      reason: reason,
    ),
  );

  Future<GiveawaysWriteOutcome> withdraw(String giveawayId) =>
      _write(() => _giveawayStore.withdrawGiveaway(giveawayId));

  Future<GiveawaysWriteOutcome> approve(String giveawayId) =>
      _write(() => _giveawayStore.approveGiveaway(giveawayId));

  Future<GiveawaysWriteOutcome> decline(String giveawayId, {String? reason}) =>
      _write(() => _giveawayStore.declineGiveaway(giveawayId, reason: reason));

  Future<GiveawaysWriteOutcome> _write(Future<void> Function() command) async {
    if (_state.busy) return const GiveawaysWriteFailed();
    _setBusy(true);
    try {
      await command();
      await refresh();
      return const GiveawaysWriteSucceeded();
    } catch (error) {
      _rejected(error);
      return const GiveawaysWriteFailed();
    } finally {
      _setBusy(false);
    }
  }

  void _rejected(Object error) {
    if (error is AccessRejected) _onAccessRejected?.call();
  }

  void _setBusy(bool busy) => _replace(
    GiveawaysSessionState(
      grid: _state.grid,
      giveaways: _state.giveaways,
      loadError: _state.loadError,
      busy: busy,
    ),
  );

  void _replace(GiveawaysSessionState state) {
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
