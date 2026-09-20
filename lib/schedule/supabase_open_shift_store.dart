import 'dart:async';

import 'package:schedule_rules/schedule_rules.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class SupabaseOpenShiftStore implements OpenShiftStore {
  const SupabaseOpenShiftStore(this.client);
  final SupabaseClient client;

  @override
  Future<List<OpenShift>> openShifts() async {
    final rows = await client.rpc<List<dynamic>>('visible_open_shifts');
    final seen = <String>{};
    return [
      for (final value in rows.cast<Map<String, dynamic>>())
        if (seen.add(value['id'] as String))
          OpenShift(
            id: value['id'] as String,
            sectionId: value['section_id'] as String?,
            date: DateTime.parse(value['work_date'] as String),
            shiftCode: value['shift_code'] as String,
            originalStaffMemberId: value['original_staff_member_id'] as String?,
            jobRole: JobRole.fromValue(value['job_role'] as String),
          ),
    ];
  }

  @override
  Future<List<OpenShiftPickup>> pickups() async {
    final rows = await client
        .from('open_shift_pickups')
        .select('id, short_shift_id, staff_member_id, status')
        .order('requested_at', ascending: false);
    return [
      for (final row in rows)
        OpenShiftPickup(
          id: row['id'] as String,
          openShiftId: row['short_shift_id'] as String,
          staffMemberId: row['staff_member_id'] as String,
          status: PickupStatus.values.byName(row['status'] as String),
        ),
    ];
  }

  @override
  Future<void> requestPickup(String openShiftId) => client.rpc<void>(
    'request_open_shift_pickup',
    params: {'p_short_shift_id': openShiftId},
  );

  @override
  Future<void> approvePickup(String pickupId) => client.rpc<void>(
    'approve_open_shift_pickup',
    params: {'p_pickup_id': pickupId},
  );

  @override
  Future<void> declinePickup(String pickupId, {String? reason}) =>
      client.rpc<void>(
        'decline_open_shift_pickup',
        params: {'p_pickup_id': pickupId, 'p_reason': reason},
      );

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  @override
  Future<List<SectionStaffing>> staffingForMonth(DateTime month) async {
    final rows = await client.rpc<List<dynamic>>(
      'section_staffing_for_month',
      params: {'p_month': _date(month)},
    );
    return [
      for (final row in rows.cast<Map<String, dynamic>>())
        SectionStaffing(
          pool: RolePool.fromValue(row['pool'] as String),
          coverageWindow: CoverageWindow.fromValue(row['coverage_window'] as String),
          date: DateTime.parse(row['work_date'] as String),
          minimum: row['minimum'] as int?,
          rnFloor: row['rn_floor'] as int?,
          workingCount: row['working_count'] as int,
          rnCount: row['rn_count'] as int,
          openCount: row['open_count'] as int,
          rnOpenCount: row['rn_open_count'] as int,
          weekdayMinimum: row['weekday_minimum'] as int?,
          dateMinimum: row['date_minimum'] as int?,
        ),
    ];
  }

  @override
  Future<void> setWeekdayMinimum(RolePool pool, CoverageWindow window,
      int weekday, int minimum, int rnFloor) =>
      client.rpc<void>(
        'set_pool_weekday_minimum',
        params: {
          'p_pool': pool.value,
          'p_window': window.value,
          'p_weekday': weekday,
          'p_minimum': minimum,
          'p_rn_floor': rnFloor,
        },
      );

  @override
  Future<void> setDateMinimum(RolePool pool, CoverageWindow window,
      DateTime date, int? minimum, int? rnFloor) =>
      client.rpc<void>(
        'set_pool_date_minimum',
        params: {
          'p_pool': pool.value,
          'p_window': window.value,
          'p_date': _date(date),
          'p_minimum': minimum,
          'p_rn_floor': rnFloor,
        },
      );

  @override
  Future<int> postOpenShifts(
    DateTime date,
    String shiftCode,
    RolePool pool,
    int count, {
    bool fillGap = false,
  }) async => await client.rpc<int>(
    'post_open_shifts',
    params: {
      'p_date': _date(date),
      'p_shift_code': shiftCode,
      'p_pool': pool.value,
      'p_count': count,
      'p_fill_gap': fillGap,
    },
  );

  @override
  Stream<void> updates() {
    late final StreamController<void> controller;
    RealtimeChannel? channel;
    controller = StreamController<void>(
      onListen: () {
        channel = client
            .channel('open-shifts-${DateTime.now().microsecondsSinceEpoch}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'open_shift_pickups',
              callback: (_) => controller.add(null),
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'short_shifts',
              callback: (_) => controller.add(null),
            )
            .subscribe();
      },
      onCancel: () async {
        final subscribed = channel;
        if (subscribed != null) await client.removeChannel(subscribed);
      },
    );
    return controller.stream;
  }
}
