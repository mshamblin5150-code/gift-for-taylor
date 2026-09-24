import 'package:er_schedule/maintainer/repair_controller.dart';
import 'package:er_schedule/maintainer/repair_gateway.dart';
import 'package:schedule_rules/schedule_rules.dart';

RepairController noopRepairController() =>
    RepairController(const NoopRepairGateway());

final class NoopRepairGateway implements RepairGateway {
  const NoopRepairGateway();

  @override
  Future<MaintainerRepair> open(
    RepairReasonCategory category,
    String? detail,
  ) => throw UnsupportedError('No Repair gateway configured');

  @override
  Future<void> close(String repairId) async {}
}
