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
            requiresApproval: value['requires_approval'] as bool,
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

  @override
  Future<bool> approvalDefault() =>
      client.rpc<bool>('open_shift_approval_default');

  @override
  Future<void> setApprovalDefault(bool requiresApproval) => client.rpc<void>(
    'set_open_shift_approval_default',
    params: {'p_requires_approval': requiresApproval},
  );

  @override
  Future<void> setShiftApproval(String openShiftId, bool requiresApproval) =>
      client.rpc<void>(
        'set_open_shift_approval',
        params: {
          'p_short_shift_id': openShiftId,
          'p_requires_approval': requiresApproval,
        },
      );

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  @override
  Future<List<CoveragePoolConfig>> coveragePoolsOn(DateTime date) async {
    final versions =
        (await client
                .from('coverage_pool_versions')
                .select(
                  'pool, effective_from, name, sort_order, retired, floor_role',
                ))
            .cast<Map<String, dynamic>>();
    final memberships =
        (await client
                .from('coverage_pool_memberships')
                .select('job_role, effective_from, pool'))
            .cast<Map<String, dynamic>>();
    final dateKey = _date(date);
    final current = <String, Map<String, dynamic>>{};
    for (final row in versions) {
      if ((row['effective_from'] as String).compareTo(dateKey) > 0) continue;
      final id = row['pool'] as String;
      if (current[id] == null ||
          (current[id]!['effective_from'] as String).compareTo(
                row['effective_from'] as String,
              ) <
              0) {
        current[id] = row;
      }
    }
    final roles = <String, String>{};
    for (final role in JobRole.values) {
      final history =
          memberships
              .where(
                (row) =>
                    row['job_role'] == role.value &&
                    (row['effective_from'] as String).compareTo(dateKey) <= 0,
              )
              .toList()
            ..sort(
              (a, b) => (a['effective_from'] as String).compareTo(
                b['effective_from'] as String,
              ),
            );
      final pool = history.lastOrNull?['pool'] as String?;
      if (pool != null) roles[role.value] = pool;
    }
    final result = [
      for (final row in current.values)
        CoveragePoolConfig(
          id: row['pool'] as String,
          name: row['name'] as String,
          sortOrder: row['sort_order'] as int,
          retired: row['retired'] as bool,
          floorRole: row['floor_role'] == null
              ? null
              : JobRole.fromValue(row['floor_role'] as String),
          jobRoles: {
            for (final role in JobRole.values)
              if (roles[role.value] == row['pool']) role,
          },
        ),
    ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return result;
  }

  @override
  Future<List<Map<String, dynamic>>> coverageRuleHistory() async {
    final rows =
        (await client
                .from('coverage_rule_audit')
                .select(
                  'actor, changed_at, effective_from, action, before_value, after_value',
                )
                .order('changed_at', ascending: false)
                .limit(50))
            .cast<Map<String, dynamic>>();
    final ids = rows.map((row) => row['actor'] as String).toSet().toList();
    final names = ids.isEmpty
        ? <Map<String, dynamic>>[]
        : (await client
                  .from('staff_members')
                  .select('id, display_name')
                  .inFilter('id', ids))
              .cast<Map<String, dynamic>>();
    final byId = {
      for (final row in names)
        row['id'] as String: row['display_name'] as String,
    };
    return [
      for (final row in rows)
        {...row, 'actor_name': byId[row['actor']] ?? 'Former Staff member'},
    ];
  }

  Map<String, dynamic> _poolParams(
    DateTime effectiveFrom,
    List<CoveragePoolConfig> pools,
  ) => {
    'p_effective_from': _date(effectiveFrom),
    'p_pools': [
      for (final pool in pools)
        {
          'id': pool.id,
          'name': pool.name,
          'sort_order': pool.sortOrder,
          'retired': pool.retired,
          'floor_role': pool.floorRole?.value,
        },
    ],
    'p_memberships': [
      for (final pool in pools)
        for (final role in pool.jobRoles)
          {'job_role': role.value, 'pool': pool.id},
    ],
  };

  Future<List<Map<String, dynamic>>> _preview(
    String rpc,
    Map<String, dynamic> params,
  ) async {
    final result = await client.rpc<List<dynamic>>(rpc, params: params);
    return result.cast<Map<String, dynamic>>();
  }

  @override
  Future<List<Map<String, dynamic>>> previewCoveragePools(
    DateTime effectiveFrom,
    List<CoveragePoolConfig> pools,
  ) => _preview('preview_coverage_pools', _poolParams(effectiveFrom, pools));

  @override
  Future<void> commitCoveragePools(
    DateTime effectiveFrom,
    List<CoveragePoolConfig> pools,
    List<Map<String, dynamic>> plan,
    List<Map<String, dynamic>> choices,
  ) async {
    await client.rpc<dynamic>(
      'commit_coverage_pools',
      params: {
        ..._poolParams(effectiveFrom, pools),
        'p_expected_plan': plan,
        'p_choices': choices,
      },
    );
  }

  Map<String, dynamic> _standingParams(
    CoveragePool pool,
    CoverageWindow window,
    int weekday,
    DateTime effectiveFrom,
    int minimum,
    JobRole? floorRole,
    int floor,
  ) => {
    'p_pool': pool.value,
    'p_window': window.value,
    'p_weekday': weekday,
    'p_effective_from': _date(effectiveFrom),
    'p_minimum': minimum,
    'p_floor_role': floorRole?.value,
    'p_floor': floor,
  };

  @override
  Future<List<Map<String, dynamic>>> previewStandingMinimum(
    CoveragePool pool,
    CoverageWindow window,
    int weekday,
    DateTime effectiveFrom,
    int minimum,
    JobRole? floorRole,
    int floor,
  ) => _preview(
    'preview_coverage_weekday_rule',
    _standingParams(
      pool,
      window,
      weekday,
      effectiveFrom,
      minimum,
      floorRole,
      floor,
    ),
  );

  @override
  Future<void> commitStandingMinimum(
    CoveragePool pool,
    CoverageWindow window,
    int weekday,
    DateTime effectiveFrom,
    int minimum,
    JobRole? floorRole,
    int floor,
    List<Map<String, dynamic>> plan,
    List<Map<String, dynamic>> choices,
  ) async {
    await client.rpc<dynamic>(
      'commit_coverage_weekday_rule',
      params: {
        ..._standingParams(
          pool,
          window,
          weekday,
          effectiveFrom,
          minimum,
          floorRole,
          floor,
        ),
        'p_expected_plan': plan,
        'p_choices': choices,
      },
    );
  }

  Map<String, dynamic> _dateParams(
    CoveragePool pool,
    CoverageWindow window,
    DateTime date,
    int? minimum,
    JobRole? floorRole,
    int floor,
  ) => {
    'p_pool': pool.value,
    'p_window': window.value,
    'p_date': _date(date),
    'p_minimum': minimum,
    'p_floor_role': floorRole?.value,
    'p_floor': floor,
  };

  @override
  Future<List<Map<String, dynamic>>> previewDateMinimum(
    CoveragePool pool,
    CoverageWindow window,
    DateTime date,
    int? minimum,
    JobRole? floorRole,
    int floor,
  ) => _preview(
    'preview_coverage_date_rule',
    _dateParams(pool, window, date, minimum, floorRole, floor),
  );

  @override
  Future<void> commitDateMinimum(
    CoveragePool pool,
    CoverageWindow window,
    DateTime date,
    int? minimum,
    JobRole? floorRole,
    int floor,
    List<Map<String, dynamic>> plan,
    List<Map<String, dynamic>> choices,
  ) async {
    await client.rpc<dynamic>(
      'commit_coverage_date_rule',
      params: {
        ..._dateParams(pool, window, date, minimum, floorRole, floor),
        'p_expected_plan': plan,
        'p_choices': choices,
      },
    );
  }

  @override
  Future<List<SectionStaffing>> staffingForMonth(DateTime month) async {
    final rows = await client.rpc<List<dynamic>>(
      'section_staffing_for_month',
      params: {'p_month': _date(month)},
    );
    final versions =
        (await client
                .from('coverage_pool_versions')
                .select(
                  'pool, effective_from, name, sort_order, retired, floor_role',
                ))
            .cast<Map<String, dynamic>>();
    Map<String, dynamic>? latest(
      List<Map<String, dynamic>> history,
      String date,
      String field,
    ) {
      final matching =
          history
              .where((entry) => (entry[field] as String).compareTo(date) <= 0)
              .toList()
            ..sort(
              (a, b) => (a[field] as String).compareTo(b[field] as String),
            );
      return matching.lastOrNull;
    }

    return [
      for (final row in rows.cast<Map<String, dynamic>>())
        SectionStaffing(
          pool: CoveragePool(
            row['pool'] as String,
            latest(
                      versions
                          .where((entry) => entry['pool'] == row['pool'])
                          .toList(),
                      row['work_date'] as String,
                      'effective_from',
                    )?['name']
                    as String? ??
                row['pool'] as String,
            sortOrder:
                latest(
                      versions
                          .where((entry) => entry['pool'] == row['pool'])
                          .toList(),
                      row['work_date'] as String,
                      'effective_from',
                    )?['sort_order']
                    as int? ??
                0,
          ),
          coverageWindow: CoverageWindow.fromValue(
            row['coverage_window'] as String,
          ),
          date: DateTime.parse(row['work_date'] as String),
          minimum: row['minimum'] as int?,
          rnFloor: row['rn_floor'] as int?,
          workingCount: row['working_count'] as int,
          rnCount: row['rn_count'] as int,
          openCount: row['open_count'] as int,
          rnOpenCount: row['rn_open_count'] as int,
          weekdayMinimum: row['weekday_minimum'] as int?,
          dateMinimum: row['date_minimum'] as int?,
          floorRole: (() {
            final version = latest(
              versions.where((entry) => entry['pool'] == row['pool']).toList(),
              row['work_date'] as String,
              'effective_from',
            );
            final role = version?['floor_role'] as String?;
            return role == null ? null : JobRole.fromValue(role);
          })(),
        ),
    ];
  }

  @override
  Future<void> setWeekdayMinimum(
    CoveragePool pool,
    CoverageWindow window,
    int weekday,
    int minimum,
    int rnFloor,
  ) => client.rpc<void>(
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
  Future<void> setDateMinimum(
    CoveragePool pool,
    CoverageWindow window,
    DateTime date,
    int? minimum,
    int? rnFloor,
  ) => client.rpc<void>(
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
    CoveragePool pool,
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
      'p_requires_approval': null,
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
