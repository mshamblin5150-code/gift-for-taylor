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
            sectionId: value['section_id'] as String,
            date: DateTime.parse(value['work_date'] as String),
            shiftCode: value['shift_code'] as String,
            originalStaffMemberId: value['original_staff_member_id'] as String,
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
