import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class ScheduleGateway {
  Future<bool> canEditSchedule();
  Future<MonthGrid> loadMonth(DateTime month);
  Future<void> saveCell({
    required String staffMemberId,
    required DateTime date,
    required String shiftCode,
  });
  Future<void> confirmMonth(DateTime month);
}

final class SupabaseScheduleGateway implements ScheduleGateway {
  SupabaseScheduleGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<bool> canEditSchedule() async {
    return await _client.rpc('current_staff_role') == 'manager';
  }

  @override
  Future<MonthGrid> loadMonth(DateTime month) async {
    final monthStart = DateTime(month.year, month.month);
    final results = await Future.wait([
      _client
          .from('schedule_months')
          .select('id, loaded_from_page_at, confirmed_at')
          .eq('month_start', _date(monthStart)),
      _client.from('sections').select('id, name').order('display_order'),
      _client.from('staff_members').select('id, display_name'),
      _client
          .from('staff_section_assignments')
          .select('staff_member_id, section_id, display_order, effective_from')
          .isFilter('effective_through', null),
    ]);
    final monthRow = results[0].firstOrNull;
    final names = {
      for (final row in results[2])
        row['id'] as String: row['display_name'] as String,
    };

    return MonthGrid.arrange(
      month: monthStart,
      sections: [
        for (final row in results[1])
          ScheduleSection(id: row['id'] as String, name: row['name'] as String),
      ],
      cells: monthRow == null
          ? const []
          : await _cellsForMonth(monthRow['id'] as String),
      staff: [
        for (final row in results[3])
          if (names[row['staff_member_id']] case final name?)
            StaffPlacement(
              staffMemberId: row['staff_member_id'] as String,
              displayName: name,
              sectionId: row['section_id'] as String,
              displayOrder: row['display_order'] as int,
              effectiveFrom: DateTime.parse(row['effective_from'] as String),
            ),
      ],
      displayNames: names,
      started: monthRow != null,
      awaitingConfirmation:
          monthRow != null &&
          monthRow['loaded_from_page_at'] != null &&
          monthRow['confirmed_at'] == null,
    );
  }

  /// A full month is over a thousand cells, past the API's page size.
  Future<List<ScheduleCell>> _cellsForMonth(String monthId) async {
    const pageSize = 1000;
    final cells = <ScheduleCell>[];
    for (var start = 0; ; start += pageSize) {
      final rows = await _client
          .from('schedule_cells')
          .select('staff_member_id, section_id, work_date, shift_code')
          .eq('schedule_month_id', monthId)
          .order('id')
          .range(start, start + pageSize - 1);
      cells.addAll(
        rows.map(
          (row) => ScheduleCell(
            staffMemberId: row['staff_member_id'] as String,
            sectionId: row['section_id'] as String,
            date: DateTime.parse(row['work_date'] as String),
            shiftCode: row['shift_code'] as String,
          ),
        ),
      );
      if (rows.length < pageSize) return cells;
    }
  }

  @override
  Future<void> saveCell({
    required String staffMemberId,
    required DateTime date,
    required String shiftCode,
  }) async {
    await _client.rpc<void>(
      'save_schedule_cell',
      params: {
        'p_staff_member_id': staffMemberId,
        'p_work_date': _date(date),
        'p_shift_code': shiftCode,
      },
    );
  }

  @override
  Future<void> confirmMonth(DateTime month) async {
    await _client.rpc<void>(
      'confirm_loaded_month',
      params: {'p_month_start': _date(DateTime(month.year, month.month))},
    );
  }
}

String _date(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
