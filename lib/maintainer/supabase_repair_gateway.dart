import 'package:schedule_rules/schedule_rules.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'repair_gateway.dart';

final class SupabaseRepairGateway implements RepairGateway {
  const SupabaseRepairGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<MaintainerRepair> open(
    RepairReasonCategory category,
    String? detail,
  ) async {
    final rows = await _client.rpc<List<dynamic>>(
      'open_maintainer_repair',
      params: {'p_reason_category': category.value, 'p_detail': detail},
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
    );
  }

  @override
  Future<void> close(String repairId) => _client.rpc<void>(
    'close_maintainer_repair',
    params: {'p_repair_id': repairId},
  );
}
