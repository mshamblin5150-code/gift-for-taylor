import '../database.dart';

/// One recorded change to a Unit setting.
final class SettingsHistoryEntry {
  const SettingsHistoryEntry({
    required this.kind,
    required this.actor,
    required this.changedAt,
    required this.before,
    required this.after,
    this.repairReason,
  });

  final String kind;
  final String actor;
  final DateTime changedAt;
  final Object? before;
  final Object? after;
  final String? repairReason;
}

abstract interface class SettingsHistory {
  /// Returns the 200 most recent changes, newest first.
  Future<List<SettingsHistoryEntry>> read();
}

final class SupabaseSettingsHistory implements SettingsHistory {
  SupabaseSettingsHistory(this._database);

  final Database _database;

  @override
  Future<List<SettingsHistoryEntry>> read() async {
    final rows = await _database.run(
      (client) => client
          .from('unit_setting_audit')
          .select(
            'kind, actor_name, changed_at, repair_reason, before_value, after_value',
          )
          .order('changed_at', ascending: false)
          .limit(200),
    );
    return [
      for (final row in rows)
        SettingsHistoryEntry(
          kind: row['kind'] as String,
          actor: row['actor_name'] as String,
          changedAt: DateTime.parse(row['changed_at'] as String),
          before: row['before_value'],
          after: row['after_value'],
          repairReason: row['repair_reason'] as String?,
        ),
    ];
  }
}
