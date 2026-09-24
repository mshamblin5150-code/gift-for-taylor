import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'repair_gateway.dart';

final class RepairController extends ChangeNotifier {
  RepairController(this.gateway);

  final RepairGateway gateway;
  final ValueNotifier<int> accessRevision = ValueNotifier(0);
  MaintainerRepair? _repair;
  Timer? _expiryTimer;

  MaintainerRepair? get repair => _repair;

  void synchronize(MaintainerRepair? repair) {
    if (_repair == repair) return;
    _setRepair(repair);
  }

  Future<void> open(RepairReasonCategory category, String? detail) async {
    _setRepair(await gateway.open(category, detail));
    accessRevision.value += 1;
  }

  Future<void> close() async {
    final repair = _repair;
    if (repair == null) return;
    await gateway.close(repair.id);
    if (_repair?.id != repair.id) return;
    _setRepair(null);
    accessRevision.value += 1;
  }

  void _setRepair(MaintainerRepair? repair) {
    _expiryTimer?.cancel();
    _repair = repair;
    if (repair != null) {
      final remaining =
          repair.remaining ?? repair.expiresAt.difference(DateTime.now());
      _expiryTimer = Timer(
        remaining.isNegative ? Duration.zero : remaining,
        () {
          if (_repair?.id != repair.id) return;
          _setRepair(null);
          accessRevision.value += 1;
        },
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    accessRevision.dispose();
    super.dispose();
  }
}
