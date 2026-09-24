import 'package:flutter/foundation.dart';
import 'package:schedule_rules/schedule_rules.dart';

import '../staff/staff_gateway.dart';

final class ManagerHandoverState {
  const ManagerHandoverState({
    this.list,
    this.candidates,
    this.loadError,
    this.saving = false,
  });

  final StaffList? list;
  final List<ManagerHandoverCandidate>? candidates;
  final Object? loadError;
  final bool saving;

  bool get isLoading => list == null && loadError == null;

  ManagerHandoverState copyWith({
    StaffList? list,
    List<ManagerHandoverCandidate>? candidates,
    Object? loadError,
    bool clearLoadError = false,
    bool? saving,
  }) => ManagerHandoverState(
    list: list ?? this.list,
    candidates: candidates ?? this.candidates,
    loadError: clearLoadError ? null : loadError ?? this.loadError,
    saving: saving ?? this.saving,
  );
}

sealed class ManagerTransferOutcome {
  const ManagerTransferOutcome();
}

final class ManagerTransferred extends ManagerTransferOutcome {
  const ManagerTransferred();
}

final class ManagerTransferFailed extends ManagerTransferOutcome {
  const ManagerTransferFailed();
}

final class ManagerHandoverSession extends ChangeNotifier {
  ManagerHandoverSession(this._gateway, [this._onAccessRejected]);

  final StaffGateway _gateway;
  final VoidCallback? _onAccessRejected;
  ManagerHandoverState _state = const ManagerHandoverState();
  bool _disposed = false;

  ManagerHandoverState get state => _state;

  Future<void> load() async {
    try {
      final (list, candidates) = await (
        _gateway.loadStaffList(),
        _gateway.loadManagerHandoverCandidates(),
      ).wait;
      _replace(ManagerHandoverState(list: list, candidates: candidates));
    } catch (error) {
      _replace(ManagerHandoverState(loadError: error));
    }
  }

  Future<ManagerTransferOutcome> transfer({
    required String successorId,
    required bool formerAdministrator,
    required Set<String> formerSections,
  }) async {
    if (_state.saving) return const ManagerTransferFailed();
    _replace(_state.copyWith(saving: true));
    try {
      await _gateway.transferManagerWithAccess(
        successorId,
        formerAdministrator,
        formerSections,
      );
      return const ManagerTransferred();
    } catch (error) {
      if (error is AccessRejected) _onAccessRejected?.call();
      return const ManagerTransferFailed();
    } finally {
      _replace(_state.copyWith(saving: false));
    }
  }

  void _replace(ManagerHandoverState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
