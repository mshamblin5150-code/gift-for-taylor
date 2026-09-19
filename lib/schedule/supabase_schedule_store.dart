import 'dart:async';

import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class SupabaseScheduleStore implements ScheduleStore {
  SupabaseScheduleStore(this._client);

  final SupabaseClient _client;

  @override
  Future<List<ScheduleSection>> sections() async {
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

  @override
  Future<List<ScheduleRow>> rows(DateTime month) async {
    final rows = await _client.rpc<List<dynamic>>(
      'schedule_rows',
      params: {'p_month_start': _date(_monthStart(month))},
    );
    return [
      for (final row in rows.cast<Map<String, dynamic>>())
        ScheduleRow(
          staffMemberId: row['staff_member_id'] as String,
          displayName: row['display_name'] as String,
          sectionId: row['section_id'] as String,
        ),
    ];
  }

  @override
  Future<List<ScheduleCell>> cellsForMonth(DateTime month) async {
    final rows = await _allPages(
      (from, to) => _client
          .from('schedule_cells')
          .select('staff_member_id, section_id, work_date, shift_code')
          .gte('work_date', _date(_monthStart(month)))
          .lt('work_date', _date(_nextMonthStart(month)))
          .order('id')
          .range(from, to),
    );
    return rows
        .map(
          (row) => ScheduleCell(
            staffMemberId: row['staff_member_id'] as String,
            sectionId: row['section_id'] as String,
            date: DateTime.parse(row['work_date'] as String),
            shiftCode: row['shift_code'] as String,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<ScheduleChange>> changesForMonth(DateTime month) async {
    final rows = await _allPages(
      (from, to) => _client
          .from('schedule_changes')
          .select(
            'staff_member_id, work_date, old_shift_code, new_shift_code, '
            'changed_by_staff_member_id, changed_at, announced_at',
          )
          .gte('work_date', _date(_monthStart(month)))
          .lt('work_date', _date(_nextMonthStart(month)))
          .order('changed_at')
          .order('id')
          .range(from, to),
    );
    return rows
        .map(
          (row) => ScheduleChange(
            staffMemberId: row['staff_member_id'] as String,
            date: DateTime.parse(row['work_date'] as String),
            oldShiftCode: row['old_shift_code'] as String,
            newShiftCode: row['new_shift_code'] as String,
            changedBy: row['changed_by_staff_member_id'] as String,
            changedAt: DateTime.parse(row['changed_at'] as String).toLocal(),
            announced: row['announced_at'] != null,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> writeCell(ScheduleCell cell) async {
    await _client.rpc<void>(
      'save_schedule_cell',
      params: {
        'p_staff_member_id': cell.staffMemberId,
        'p_section_id': cell.sectionId,
        'p_work_date': _date(cell.date),
        'p_shift_code': cell.shiftCode,
      },
    );
  }

  @override
  Stream<void> monthUpdates(DateTime month) {
    late final StreamController<void> controller;
    RealtimeChannel? channel;
    controller = StreamController<void>(
      onListen: () {
        channel = _client
            .channel('schedule-changes-${_date(_monthStart(month))}')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'schedule_changes',
              callback: (payload) {
                final workDate = payload.newRecord['work_date'];
                if (workDate is! String) return;
                final date = DateTime.parse(workDate);
                if (date.year == month.year && date.month == month.month) {
                  controller.add(null);
                }
              },
            )
            .subscribe();
      },
      onCancel: () async {
        final subscribed = channel;
        if (subscribed != null) await _client.removeChannel(subscribed);
      },
    );
    return controller.stream;
  }

  @override
  Future<bool> canEditSchedule() async {
    return await _client.rpc('can_edit_schedule') as bool? ?? false;
  }

  @override
  Future<List<DateTime>> monthsAwaitingConfirmation() async {
    final rows = await _client
        .from('schedule_months')
        .select('month_start')
        .not('loaded_from_page_at', 'is', null)
        .isFilter('confirmed_at', null)
        .order('month_start');
    return [
      for (final row in rows) DateTime.parse(row['month_start'] as String),
    ];
  }

  @override
  Future<void> confirmLoadedMonth(DateTime month) async {
    await _client.rpc<void>(
      'confirm_loaded_month',
      params: {'p_month_start': _date(_monthStart(month))},
    );
  }

  @override
  Future<MonthStatus> monthStatus(DateTime month) async {
    final row = await _client
        .from('schedule_months')
        .select('release_state')
        .eq('month_start', _date(_monthStart(month)))
        .maybeSingle();
    return switch (row?['release_state']) {
      'released' => MonthStatus.released,
      'unpublished' => MonthStatus.unpublished,
      _ => MonthStatus.notStarted,
    };
  }

  @override
  Future<void> startMonth(DateTime month, List<ScheduleCell> cells) async {
    await _client.rpc<void>(
      'start_month',
      params: {
        'p_month_start': _date(_monthStart(month)),
        'p_cells': [
          for (final cell in cells)
            {
              'staff_member_id': cell.staffMemberId,
              'section_id': cell.sectionId,
              'work_date': _date(cell.date),
              'shift_code': cell.shiftCode,
            },
        ],
      },
    );
  }

  @override
  Future<void> releaseMonth(DateTime month) async {
    await _client.rpc<void>(
      'release_month',
      params: {'p_month_start': _date(_monthStart(month))},
    );
  }

  /// A full month has more cells than the API returns in one response.
  Future<List<Map<String, dynamic>>> _allPages(
    Future<List<Map<String, dynamic>>> Function(int from, int to) page,
  ) async {
    const pageSize = 1000;
    final rows = <Map<String, dynamic>>[];
    for (var from = 0; ; from += pageSize) {
      final batch = await page(from, from + pageSize - 1);
      rows.addAll(batch);
      if (batch.length < pageSize) return rows;
    }
  }
}

DateTime _monthStart(DateTime month) => DateTime(month.year, month.month);

DateTime _nextMonthStart(DateTime month) =>
    DateTime(month.year, month.month + 1);

String _date(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
