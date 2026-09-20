import 'dart:convert';

import 'package:er_schedule/schedule/supabase_schedule_store.dart';
import 'package:er_schedule/staff/staff_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('the Schedule reads Sections in printed-page order', () async {
    final client = _client();
    addTearDown(client.dispose);

    final sections = await SupabaseScheduleStore(client).sections();

    expect(sections.map((section) => section.name), [
      'State dayshift RN',
      'Unit clerks',
    ]);
  });

  test('the Staff list reads Sections and people in page order', () async {
    final client = _client();
    addTearDown(client.dispose);

    final staffList = await SupabaseStaffGateway(client).loadStaffList();

    expect(staffList.sections.map((section) => section.name), [
      'State dayshift RN',
      'Unit clerks',
    ]);
    expect(staffList.members.map((member) => member.displayName), [
      'First RN',
      'Second RN',
    ]);
  });
}

SupabaseClient _client() => SupabaseClient(
  'https://example.test',
  'test-key',
  accessToken: () async => 'test-token',
  httpClient: MockClient((request) async {
    final rows = switch (request.url.path) {
      '/rest/v1/sections' => [
        {'id': 'days', 'name': 'State dayshift RN'},
        {'id': 'clerks', 'name': 'Unit clerks'},
      ],
      '/rest/v1/staff_list_entries' => [
        {
          'id': 'first',
          'display_name': 'First RN',
          'cell_number': null,
          'section_id': 'days',
          'display_order': 0,
          'personal_email': null,
          'job_role': null,
        },
        {
          'id': 'second',
          'display_name': 'Second RN',
          'cell_number': null,
          'section_id': 'days',
          'display_order': 1,
          'personal_email': null,
          'job_role': null,
        },
      ],
      _ => throw StateError('Unexpected request: ${request.url.path}'),
    };
    final order = request.url.queryParameters['order'];
    if (order != 'display_order.asc.nullslast' &&
        order != 'display_order.desc.nullslast') {
      throw StateError('Unexpected Section order: $order');
    }
    return http.Response(
      jsonEncode(
        order == 'display_order.asc.nullslast' ? rows : rows.reversed.toList(),
      ),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }),
);
