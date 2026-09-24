import 'package:schedule_rules/schedule_rules.dart';

abstract interface class RepairGateway {
  Future<MaintainerRepair> open(RepairReasonCategory category, String? detail);
  Future<void> close(String repairId);
}

MaintainerRepair? maintainerRepairFromRow(Map<String, dynamic> row) {
  final id = row['repair_id'] ?? row['id'];
  final category = row['repair_reason_category'] ?? row['reason_category'];
  final openedAt = row['repair_opened_at'] ?? row['opened_at'];
  final expiresAt = row['repair_expires_at'] ?? row['expires_at'];
  final remainingSeconds = row['repair_seconds_remaining'];
  if (id == null || category == null || openedAt == null || expiresAt == null) {
    return null;
  }
  return MaintainerRepair(
    id: id as String,
    category: RepairReasonCategory.fromValue(category as String),
    detail: (row['repair_detail'] ?? row['detail']) as String?,
    openedAt: DateTime.parse(openedAt as String),
    expiresAt: DateTime.parse(expiresAt as String),
    remaining: remainingSeconds is num
        ? Duration(
            microseconds: (remainingSeconds.toDouble() * 1000000).round(),
          )
        : null,
  );
}
