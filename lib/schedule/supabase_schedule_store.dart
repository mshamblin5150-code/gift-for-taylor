import 'dart:async';

import 'package:intl/intl.dart';
import 'package:schedule_rules/schedule_rules.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class SupabaseScheduleStore implements ScheduleStore {
  SupabaseScheduleStore(this._client);

  final SupabaseClient _client;

  @override
  Future<List<LegendCode>> shiftCodes() async {
    final rows = await _client
        .from('shift_codes')
        .select(
          'code, meaning, start_time, end_time, is_working, coverage_window',
        )
        .eq('active', true)
        .order('display_order', ascending: true)
        .order('code', ascending: true);
    return [
      for (final row in rows)
        LegendCode(
          row['code'] as String,
          meaning: row['meaning'] as String?,
          startTime: (row['start_time'] as String?)?.substring(0, 5),
          endTime: (row['end_time'] as String?)?.substring(0, 5),
          hours: shiftCodeHours(
            row['start_time'] as String?,
            row['end_time'] as String?,
          ),
          isWorking: row['is_working'] as bool,
          coverageWindow: row['coverage_window'] as String?,
        ),
    ];
  }

  @override
  Future<void> saveShiftCode(LegendCode code, {String? originalCode}) =>
      _client.rpc<void>(
        'save_shift_code',
        params: {
          'p_code': code.code,
          'p_original_code': originalCode,
          'p_meaning': code.meaning,
          'p_start_time': code.startTime,
          'p_end_time': code.endTime,
          'p_is_working': code.isWorking,
          'p_coverage_window': code.coverageWindow,
        },
      );

  @override
  Future<void> deleteShiftCode(String code) =>
      _client.rpc<void>('delete_shift_code', params: {'p_code': code});

  @override
  Future<RequestOffEmail> createRequestOff(RequestOffDraft draft) async {
    final result = await _client.rpc<Map<String, dynamic>>(
      'submit_request_off',
      params: {
        'p_dates': draft.dates.map(_date).toList(),
        'p_reason': draft.reason,
      },
    );
    return RequestOffEmail.forRequest(
      requestId: result['request_id'] as String,
      to: result['manager_email'] as String,
      staffMemberName: result['staff_name'] as String,
      dates: draft.dates,
      reason: draft.reason,
    );
  }

  @override
  Future<void> confirmRequestOffEmail(String requestId) => _client.rpc<void>(
    'confirm_request_off_email',
    params: {'p_request_id': requestId},
  );

  @override
  Future<List<RequestOff>> requestsOff({required bool pendingOnly}) async {
    final rows = await _allPages((from, to) {
      var query = _client
          .from('requests_off')
          .select(
            'id, staff_member_id, reason, submitted_at, email_confirmed_at, '
            'decision, decision_reason, decided_at, '
            'staff_members!staff_member_id(display_name), request_off_dates(work_date)',
          );
      if (pendingOnly) query = query.eq('decision', 'pending');
      return query.order('submitted_at', ascending: false).range(from, to);
    });
    return [
      for (final row in rows)
        RequestOff(
          id: row['id'] as String,
          staffMemberId: row['staff_member_id'] as String,
          staffMemberName:
              (row['staff_members'] as Map<String, dynamic>)['display_name']
                  as String,
          dates: [
            for (final day in row['request_off_dates'] as List<dynamic>)
              DateTime.parse(
                (day as Map<String, dynamic>)['work_date'] as String,
              ),
          ]..sort(),
          reason: row['reason'] as String?,
          submittedAt: DateTime.parse(row['submitted_at'] as String).toLocal(),
          emailConfirmedAt: row['email_confirmed_at'] == null
              ? null
              : DateTime.parse(row['email_confirmed_at'] as String).toLocal(),
          decision: RequestOffDecision.values.byName(row['decision'] as String),
          decisionReason: row['decision_reason'] as String?,
          decidedAt: row['decided_at'] == null
              ? null
              : DateTime.parse(row['decided_at'] as String).toLocal(),
        ),
    ];
  }

  @override
  Future<void> decideRequestOff(
    String requestId,
    RequestOffDecision decision,
    String? reason,
  ) => _client.rpc<void>(
    'decide_request_off',
    params: {
      'p_request_id': requestId,
      'p_decision': decision.name,
      'p_reason': reason,
    },
  );

  @override
  Future<int> unreadRequestOffNotices() async {
    final rows = await _client
        .from('staff_notices')
        .select('id')
        .inFilter('kind', ['request_submitted', 'request_decided'])
        .filter('read_at', 'is', null);
    return rows.length;
  }

  @override
  Future<void> acknowledgeRequestOffNotices() =>
      _client.rpc<void>('acknowledge_request_off_notices');

  @override
  Future<List<ScheduleSection>> sections() async {
    final rows = await _client
        .from('sections')
        .select('id, name')
        .order('display_order', ascending: true);
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
          cellNumber: row['cell_number'] as String?,
          lastDay: _parseDate(row['last_day']),
          hasPushSubscription: row['has_push_subscription'] as bool? ?? false,
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
          .order('id', ascending: true)
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
            'id, staff_member_id, work_date, old_shift_code, new_shift_code, '
            'changed_by_staff_member_id, changed_at, announced_at, moot_at, reach, '
            'changed_by:staff_members!changed_by_staff_member_id(display_name)',
          )
          .gte('work_date', _date(_monthStart(month)))
          .lt('work_date', _date(_nextMonthStart(month)))
          .order('changed_at', ascending: true)
          .order('id', ascending: true)
          .range(from, to),
    );
    return rows
        .map(
          (row) => ScheduleChange(
            id: row['id'] as String,
            staffMemberId: row['staff_member_id'] as String,
            date: DateTime.parse(row['work_date'] as String),
            oldShiftCode: row['old_shift_code'] as String,
            newShiftCode: row['new_shift_code'] as String,
            changedBy: row['changed_by_staff_member_id'] as String,
            changedByName:
                (row['changed_by'] as Map<String, dynamic>?)?['display_name']
                    as String? ??
                '',
            changedAt: DateTime.parse(row['changed_at'] as String).toLocal(),
            announced: row['announced_at'] != null,
            moot: row['moot_at'] != null,
            reach: row['reach'] as String?,
          ),
        )
        .toList(growable: false);
  }

  JobRole? _roleForShort(
    Map<String, dynamic> short,
    List<Map<String, dynamic>> roles,
  ) {
    final postedRole = short['job_role'] as String?;
    if (postedRole != null) return JobRole.fromValue(postedRole);
    final staffId = short['staff_member_id'] as String?;
    if (staffId == null) return null;
    final date = DateTime.parse(short['work_date'] as String);
    final earlierRoles =
        roles
            .where(
              (role) =>
                  role['staff_member_id'] == staffId &&
                  !DateTime.parse(role['effective_from'] as String)
                      .isAfter(date),
            )
            .toList()
          ..sort(
            (a, b) => (a['effective_from'] as String).compareTo(
              b['effective_from'] as String,
            ),
          );
    final value = earlierRoles.lastOrNull?['job_role'] as String?;
    return value == null ? null : JobRole.fromValue(value);
  }

  CoverageWindow? _windowForShort(String shiftCode, List<LegendCode> codes) {
    final value = codes
        .where((code) => code.code == shiftCode.trim().toUpperCase())
        .firstOrNull
        ?.coverageWindow;
    return value == null ? null : CoverageWindow.fromValue(value);
  }

  @override
  Future<List<ShortShift>> shortShiftsForMonth(DateTime month) async {
    final rows = await _client
        .from('short_shifts')
        .select('section_id, work_date, shift_code, staff_member_id, job_role')
        .gte('work_date', _date(_monthStart(month)))
        .lt('work_date', _date(_nextMonthStart(month)))
        .filter('filled_at', 'is', null)
        .order('work_date', ascending: true);
    final codes = await shiftCodes();
    final staffIds = rows
        .map((row) => row['staff_member_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    final roles = staffIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await _client
                  .from('staff_job_roles')
                  .select('staff_member_id, job_role, effective_from')
                  .inFilter('staff_member_id', staffIds))
              .cast<Map<String, dynamic>>();
    return [
      for (final row in rows)
        ShortShift(
          sectionId: row['section_id'] as String?,
          date: DateTime.parse(row['work_date'] as String),
          shiftCode: row['shift_code'] as String,
          staffMemberId: row['staff_member_id'] as String?,
          jobRole: _roleForShort(row, roles),
          coverageWindow: _windowForShort(row['shift_code'] as String, codes),
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
  Future<void> writeCellPair(SaveCellPair action) async {
    await _client.rpc<void>(
      'save_schedule_cell_pair',
      params: {
        'p_first_staff_member_id': action.first.staffMemberId,
        'p_first_section_id': action.first.sectionId,
        'p_first_work_date': _date(action.first.date),
        'p_first_expected_code': action.expectedFirstCode,
        'p_first_new_code': action.first.shiftCode,
        'p_second_staff_member_id': action.second.staffMemberId,
        'p_second_section_id': action.second.sectionId,
        'p_second_work_date': _date(action.second.date),
        'p_second_expected_code': action.expectedSecondCode,
        'p_second_new_code': action.second.shiftCode,
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
  Future<EditableSections> editableSections() async {
    final ids = await _client.rpc<List<dynamic>>('editable_section_ids');
    return EditableSections.only({for (final id in ids) id as String});
  }

  @override
  Future<void> assignNightScheduler(
    String staffMemberId,
    Set<String> sectionIds,
  ) async {
    await _client.rpc<void>(
      'assign_night_scheduler',
      params: {
        'p_staff_member_id': staffMemberId,
        'p_section_ids': sectionIds.toList(),
      },
    );
  }

  @override
  Future<void> removeNightScheduler(String staffMemberId) async {
    await _client.rpc<void>(
      'remove_night_scheduler',
      params: {'p_staff_member_id': staffMemberId},
    );
  }

  @override
  Future<List<NightScheduler>> nightSchedulers() async {
    final rows = await _client
        .from('night_scheduler_sections')
        .select('staff_member_id, section_id')
        .order('created_at', ascending: true);
    final sections = <String, Set<String>>{};
    for (final row in rows) {
      sections
          .putIfAbsent(row['staff_member_id'] as String, () => {})
          .add(row['section_id'] as String);
    }
    return [
      for (final MapEntry(:key, :value) in sections.entries)
        NightScheduler(staffMemberId: key, sectionIds: value),
    ];
  }

  @override
  Future<List<DateTime>> monthsAwaitingConfirmation() async {
    final rows = await _client
        .from('schedule_months')
        .select('month_start')
        .not('loaded_from_page_at', 'is', null)
        .isFilter('confirmed_at', null)
        .order('month_start', ascending: true);
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
  Future<void> markChangesAnnounced(
    Set<String> changeIds,
    Set<String> draftOpenedStaffMemberIds,
  ) async {
    await _client.rpc<void>(
      'mark_changes_announced',
      params: {
        'p_change_ids': changeIds.toList(),
        'p_draft_opened_staff_member_ids': draftOpenedStaffMemberIds.toList(),
      },
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
  Future<void> releaseMonth(DateTime month) async {
    await _client.rpc<void>(
      'release_month',
      params: {'p_month_start': _date(_monthStart(month))},
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
        .order('effective_from', ascending: true);
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
        .order('changed_at', ascending: true);
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
