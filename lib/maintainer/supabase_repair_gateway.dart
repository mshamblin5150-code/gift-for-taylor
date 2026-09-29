import 'package:schedule_rules/schedule_rules.dart';

import '../database.dart';
import 'repair_gateway.dart';

final class SupabaseRepairGateway implements RepairGateway {
  const SupabaseRepairGateway(this._database);

  final Database _database;

  @override
  Future<MaintainerRepair> open(
    RepairReasonCategory category,
    String? detail, {
    String? ticketId,
  }) async {
    final rows = await _database.run(
      (client) => client.rpc<List<dynamic>>(
        'open_maintainer_repair',
        params: {
          'p_reason_category': category.value,
          'p_detail': detail,
          'p_ticket_id': ticketId,
        },
      ),
    );
    final repair = maintainerRepairFromRow(
      rows.single as Map<String, dynamic>,
    )!;
    return MaintainerRepair(
      id: repair.id,
      category: repair.category,
      detail: repair.detail,
      openedAt: repair.openedAt,
      expiresAt: repair.expiresAt,
      remaining: repair.expiresAt.difference(repair.openedAt),
      ticketId: repair.ticketId,
    );
  }

  @override
  Future<void> close(String repairId) => _database.run(
    (client) => client.rpc<void>(
      'close_maintainer_repair',
      params: {'p_repair_id': repairId},
    ),
  );
}
