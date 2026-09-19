import 'package:schedule_rules/schedule_rules.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class SectionGateway {
  Future<List<ScheduleSection>> loadSections();
}

final class SupabaseSectionGateway implements SectionGateway {
  SupabaseSectionGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<List<ScheduleSection>> loadSections() async {
    final rows = await _client
        .from('sections')
        .select('id, name')
        .order('display_order');

    return rows
        .map(
          (row) => ScheduleSection(
            id: row['id'] as String,
            name: row['name'] as String,
          ),
        )
        .toList(growable: false);
  }
}
