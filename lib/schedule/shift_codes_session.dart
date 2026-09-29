import 'package:flutter/foundation.dart';
import 'package:schedule_rules/schedule_rules.dart';

final class ShiftCodesState {
  const ShiftCodesState({this.codes, this.loadError});

  final List<LegendCode>? codes;
  final Object? loadError;
}

sealed class ShiftCodeReviewOutcome {
  const ShiftCodeReviewOutcome();
}

final class ShiftCodeReviewReady extends ShiftCodeReviewOutcome {
  const ShiftCodeReviewReady(this.plan);
  final List<ShiftCodeChangePlan> plan;
}

final class ShiftCodeReviewFailed extends ShiftCodeReviewOutcome {
  const ShiftCodeReviewFailed();
}

sealed class ShiftCodeWriteOutcome {
  const ShiftCodeWriteOutcome();
}

final class ShiftCodeSaved extends ShiftCodeWriteOutcome {
  const ShiftCodeSaved();
}

final class ShiftCodeDeleted extends ShiftCodeWriteOutcome {
  const ShiftCodeDeleted();
}

final class ShiftCodeDeleteRefused extends ShiftCodeWriteOutcome {
  const ShiftCodeDeleteRefused(this.reason);
  final ShiftCodeRefusal reason;
}

final class ShiftCodeWriteFailed extends ShiftCodeWriteOutcome {
  const ShiftCodeWriteFailed();
}

final class ShiftCodesSession extends ChangeNotifier {
  ShiftCodesSession(this._store, [this._onAccessRejected]) {
    load();
  }

  final ScheduleStore _store;
  final VoidCallback? _onAccessRejected;
  ShiftCodesState _state = const ShiftCodesState();
  bool _disposed = false;

  ShiftCodesState get state => _state;

  Future<void> load() async {
    try {
      final codes = await _store.shiftCodes();
      _replace(ShiftCodesState(codes: List.unmodifiable(codes)));
    } catch (error) {
      _replace(ShiftCodesState(loadError: error));
    }
  }

  Future<ShiftCodeReviewOutcome> review(
    LegendCode code, {
    String? originalCode,
  }) async {
    try {
      return ShiftCodeReviewReady(
        await _store.previewShiftCodeChange(code, originalCode: originalCode),
      );
    } catch (error) {
      _rejected(error);
      return const ShiftCodeReviewFailed();
    }
  }

  Future<ShiftCodeWriteOutcome> save(
    LegendCode code,
    List<ShiftCodeChangePlan> plan, {
    String? originalCode,
  }) async {
    try {
      await _store.commitShiftCodeChange(
        code,
        plan,
        originalCode: originalCode,
      );
      await load();
      return const ShiftCodeSaved();
    } catch (error) {
      _rejected(error);
      return const ShiftCodeWriteFailed();
    }
  }

  Future<ShiftCodeWriteOutcome> delete(String code) async {
    try {
      await _store.deleteShiftCode(code);
      await load();
      return const ShiftCodeDeleted();
    } on Refused catch (error) {
      if (error.refusal case final ShiftCodeRefusal reason) {
        return ShiftCodeDeleteRefused(reason);
      }
      assert(false, 'Unexpected Refusal family: ${error.refusal.runtimeType}');
      return const ShiftCodeWriteFailed();
    } catch (error) {
      _rejected(error);
      return const ShiftCodeWriteFailed();
    }
  }

  void _rejected(Object error) {
    if (error is AccessRejected) _onAccessRejected?.call();
  }

  void _replace(ShiftCodesState next) {
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
