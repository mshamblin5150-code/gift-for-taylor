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
    final (sectionList, placements) = await (
      sections(),
      _client
          .from('schedule_row_assignments')
          .select(
            'staff_member_id, display_name, last_day, section_id, '
            'display_order, effective_from',
          )
          .lt('effective_from', _date(_nextMonthStart(month)))
          .or(
            'effective_through.is.null,'
            'effective_through.gte.${_date(_monthStart(month))}',
          )
          .order('effective_from'),
    ).wait;
    // Each person's latest placement in the month decides their row.
    final latest = <String, Map<String, dynamic>>{
      for (final placement in placements)
        placement['staff_member_id'] as String: placement,
    };
    final ordered = latest.values.toList()
      ..sort((left, right) {
        final byOrder = (left['display_order'] as int).compareTo(
          right['display_order'] as int,
        );
        return byOrder != 0
            ? byOrder
            : (left['display_name'] as String).compareTo(
                right['display_name'] as String,
              );
      });
    final rows = [
      for (final placement in ordered)
        ScheduleRow(
          staffMemberId: placement['staff_member_id'] as String,
          displayName: placement['display_name'] as String,
          sectionId: placement['section_id'] as String,
          lastDay: _parseDate(placement['last_day']),
        ),
    ];
    return [
      for (final section in sectionList)
        ...rows.where((row) => row.sectionId == section.id),
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
  Future<List<ShortShift>> shortShiftsForMonth(DateTime month) async {
    final rows = await _client
        .from('short_shifts')
        .select('section_id, work_date, shift_code, staff_member_id')
        .gte('work_date', _date(_monthStart(month)))
        .lt('work_date', _date(_nextMonthStart(month)))
        .order('work_date');
    return [
      for (final row in rows)
        ShortShift(
          sectionId: row['section_id'] as String,
          date: DateTime.parse(row['work_date'] as String),
          shiftCode: row['shift_code'] as String,
          staffMemberId: row['staff_member_id'] as String,
        ),
    ];
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
  Future<void> setLastDay(SetLastDay action) async {
    await _client.rpc<void>(
      'set_staff_last_day',
      params: {
        'p_staff_member_id': action.staffMemberId,
        'p_last_day': _date(action.lastDay),
      },
    );
  }

  @override
  Future<void> reactivate(Reactivate action) async {
    await _client.rpc<void>(
      'reactivate_staff_member',
      params: {
        'p_staff_member_id': action.staffMemberId,
        'p_section_id': action.sectionId,
        'p_first_day': _date(action.firstDay),
      },
    );
  }

  @override
  Future<void> changeSection(ChangeSection action) async {
    await _client.rpc<void>(
      'change_staff_section',
      params: {
        'p_staff_member_id': action.staffMemberId,
        'p_section_id': action.sectionId,
        'p_from': _date(action.from),
      },
    );
  }

  @override
  Future<void> changeJobRole(ChangeJobRole action) async {
    await _client.rpc<void>(
      'change_staff_job_role',
      params: {
        'p_staff_member_id': action.staffMemberId,
        'p_job_role': action.jobRole.value,
        'p_from': _date(action.from),
      },
    );
  }

  @override
  Future<List<DatedJobRole>> jobRoles(String staffMemberId) async {
    final rows = await _client
        .from('staff_job_roles')
        .select('job_role, effective_from, effective_through')
        .eq('staff_member_id', staffMemberId)
        .order('effective_from');
    return [
      for (final row in rows)
        DatedJobRole(
          jobRole: JobRole.fromValue(row['job_role'] as String),
          from: DateTime.parse(row['effective_from'] as String),
          through: _parseDate(row['effective_through']),
        ),
    ];
  }

  @override
  Future<List<StaffChange>> staffChanges() async {
    final rows = await _client
        .from('staff_changes')
        .select(
          'staff_member_id, kind, old_value, new_value, effective_from, '
          'changed_by_staff_member_id, changed_at',
        )
        .order('changed_at');
    return [
      for (final row in rows)
        StaffChange(
          staffMemberId: row['staff_member_id'] as String,
          kind: StaffChangeKind.fromValue(row['kind'] as String),
          oldValue: row['old_value'] as String?,
          newValue: row['new_value'] as String?,
          effectiveFrom: DateTime.parse(row['effective_from'] as String),
          changedBy: row['changed_by_staff_member_id'] as String,
          changedAt: DateTime.parse(row['changed_at'] as String).toLocal(),
        ),
    ];
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

DateTime? _parseDate(Object? value) =>
    value is String ? DateTime.parse(value) : null;

String _date(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
