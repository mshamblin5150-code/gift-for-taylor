import 'package:schedule_rules/schedule_rules.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'staff_contacts.dart';

final class StaffSection {
  const StaffSection({required this.id, required this.name});

  final String id;
  final String name;
}

final class StaffListMember {
  const StaffListMember({
    required this.id,
    required this.displayName,
    required this.cellNumber,
    required this.sectionId,
    required this.displayOrder,
    this.personalEmail,
    this.jobRole,
  });

  final String id;
  final String displayName;

  /// Missing for people loaded from the printed page until one is added.
  final String? cellNumber;
  final String sectionId;
  final int displayOrder;
  final String? personalEmail;

  /// Null until the Manager sets one.
  final JobRole? jobRole;

  StaffListMember withDisplayOrder(int value) {
    return StaffListMember(
      id: id,
      displayName: displayName,
      cellNumber: cellNumber,
      sectionId: sectionId,
      displayOrder: value,
      personalEmail: personalEmail,
      jobRole: jobRole,
    );
  }
}

final class StaffList {
  const StaffList({required this.sections, required this.members});

  final List<StaffSection> sections;
  final List<StaffListMember> members;

  StaffList withSections(List<StaffSection> ordered) =>
      StaffList(sections: ordered, members: members);

  List<StaffListMember> membersInSection(String sectionId) {
    return members.where((member) => member.sectionId == sectionId).toList()
      ..sort((left, right) => left.displayOrder.compareTo(right.displayOrder));
  }

  StaffList withSectionOrder(
    String sectionId,
    List<StaffListMember> reordered,
  ) {
    return StaffList(
      sections: sections,
      members: [
        for (final member in members)
          if (member.sectionId != sectionId) member,
        ...reordered.indexed.map(
          (entry) => entry.$2.withDisplayOrder(entry.$1),
        ),
      ],
    );
  }
}

/// Someone who has left: deactivated, never deleted.
final class PastStaffMember {
  const PastStaffMember({
    required this.id,
    required this.displayName,
    required this.lastDay,
    required this.sectionId,
  });

  final String id;
  final String displayName;
  final DateTime? lastDay;

  /// The Section they were last in, if any.
  final String? sectionId;
}

final class StaffMemberDraft {
  const StaffMemberDraft({
    required this.displayName,
    required this.cellNumber,
    required this.sectionId,
  });

  final String displayName;
  final String cellNumber;
  final String sectionId;
}

final class StaffInvite {
  const StaffInvite({
    required this.staffMemberId,
    required this.cellNumber,
    required this.token,
  });

  final String staffMemberId;
  final String cellNumber;
  final String token;
}

final class StaffMemberDetails {
  const StaffMemberDetails({
    required this.id,
    required this.displayName,
    required this.sectionId,
    required this.role,
    this.cellNumber,
    this.personalEmail,
    this.jobRole,
    this.lastDay,
  });

  final String id;
  final String displayName;
  final String? cellNumber;
  final String? sectionId;
  final String role;
  final String? personalEmail;
  final JobRole? jobRole;
  final DateTime? lastDay;
}

abstract interface class StaffGateway {
  Future<bool> canManageStaff();
  Future<bool> canManageSections();
  Future<String?> currentStaffMemberId();
  Future<StaffList> loadStaffList();
  Future<StaffMemberDetails> loadStaffMemberDetails(String staffMemberId);
  Future<void> updateStaffContact(
    String staffMemberId,
    String displayName,
    String? cellNumber,
  );

  /// Everyone who has left, most recent Last day first.
  Future<List<PastStaffMember>> loadPastStaff();
  Future<StaffInvite> addStaffMember(StaffMemberDraft draft);
  Future<void> reorderSection(String sectionId, List<String> memberIds);
  Future<void> reorderSections(List<String> sectionIds);
  Future<void> addSection(String name);
  Future<void> renameSection(String sectionId, String name);
  Future<void> deleteEmptySection(String sectionId);
  Future<StaffInvite> resendInvite(String staffMemberId);
  Future<void> acceptInvite(String token);
}

final class SupabaseStaffGateway implements StaffGateway {
  SupabaseStaffGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<bool> canManageStaff() async {
    return await _client.rpc('can_manage_staff') as bool? ?? false;
  }

  @override
  Future<bool> canManageSections() async {
    return await _client.rpc('can_manage_sections') as bool? ?? false;
  }

  @override
  Future<String?> currentStaffMemberId() async {
    final authUserId = _client.auth.currentUser?.id;
    if (authUserId == null) return null;
    final row = await _client
        .from('staff_accounts')
        .select('staff_member_id')
        .eq('auth_user_id', authUserId)
        .maybeSingle();
    return row?['staff_member_id'] as String?;
  }

  @override
  Future<StaffList> loadStaffList() async {
    final results = await Future.wait([
      _client
          .from('sections')
          .select('id, name')
          .order('display_order', ascending: true),
      _client
          .from('staff_list_entries')
          .select(
            'id, display_name, cell_number, section_id, display_order, '
            'personal_email, job_role',
          )
          .order('display_order', ascending: true),
    ]);
    final sectionRows = results[0];
    final memberRows = results[1];
    return StaffList(
      sections: sectionRows
          .map(
            (row) => StaffSection(
              id: row['id'] as String,
              name: row['name'] as String,
            ),
          )
          .toList(growable: false),
      members: memberRows
          .map(
            (row) => StaffListMember(
              id: row['id'] as String,
              displayName: row['display_name'] as String,
              cellNumber: row['cell_number'] as String?,
              sectionId: row['section_id'] as String,
              displayOrder: row['display_order'] as int,
              personalEmail: row['personal_email'] as String?,
              jobRole: switch (row['job_role']) {
                final String value => JobRole.fromValue(value),
                _ => null,
              },
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<StaffMemberDetails> loadStaffMemberDetails(
    String staffMemberId,
  ) async {
    final rows = await _client.rpc<List<dynamic>>(
      'staff_member_details',
      params: {'p_staff_member_id': staffMemberId},
    );
    final row = rows.single as Map<String, dynamic>;
    return StaffMemberDetails(
      id: row['id'] as String,
      displayName: row['display_name'] as String,
      cellNumber: row['cell_number'] as String?,
      sectionId: row['section_id'] as String?,
      role: row['role'] as String,
      personalEmail: row['personal_email'] as String?,
      jobRole: switch (row['job_role']) {
        final String value => JobRole.fromValue(value),
        _ => null,
      },
      lastDay: switch (row['last_day']) {
        final String value => DateTime.parse(value),
        _ => null,
      },
    );
  }

  @override
  Future<void> updateStaffContact(
    String staffMemberId,
    String displayName,
    String? cellNumber,
  ) => _client.rpc<void>(
    'update_staff_contact',
    params: {
      'p_staff_member_id': staffMemberId,
      'p_display_name': displayName,
      'p_cell_number': cellNumber == null
          ? ''
          : normalizeCellNumber(cellNumber),
    },
  );

  @override
  Future<List<PastStaffMember>> loadPastStaff() async {
    final rows = await _client
        .from('past_staff_entries')
        .select('id, display_name, last_day, section_id')
        .order('last_day', ascending: false);
    return [
      for (final row in rows)
        PastStaffMember(
          id: row['id'] as String,
          displayName: row['display_name'] as String,
          lastDay: switch (row['last_day']) {
            final String value => DateTime.parse(value),
            _ => null,
          },
          sectionId: row['section_id'] as String?,
        ),
    ];
  }

  @override
  Future<StaffInvite> addStaffMember(StaffMemberDraft draft) async {
    final rows = await _client.rpc<List<dynamic>>(
      'create_staff_member_with_invite',
      params: {
        'p_display_name': draft.displayName,
        'p_cell_number': normalizeCellNumber(draft.cellNumber),
        'p_section_id': draft.sectionId,
      },
    );
    return _inviteFromRow(rows.single as Map<String, dynamic>);
  }

  @override
  Future<void> reorderSection(String sectionId, List<String> memberIds) async {
    await _client.rpc<void>(
      'reorder_staff_section',
      params: {'p_section_id': sectionId, 'p_staff_member_ids': memberIds},
    );
  }

  @override
  Future<void> reorderSections(List<String> sectionIds) => _client.rpc<void>(
    'reorder_sections',
    params: {'p_section_ids': sectionIds},
  );

  @override
  Future<void> addSection(String name) async {
    await _client.rpc<String>('add_section', params: {'p_name': name});
  }

  @override
  Future<void> renameSection(String sectionId, String name) =>
      _client.rpc<void>(
        'rename_section',
        params: {'p_section_id': sectionId, 'p_name': name},
      );

  @override
  Future<void> deleteEmptySection(String sectionId) => _client.rpc<void>(
    'delete_empty_section',
    params: {'p_section_id': sectionId},
  );

  @override
  Future<StaffInvite> resendInvite(String staffMemberId) async {
    final rows = await _client.rpc<List<dynamic>>(
      'resend_staff_invite',
      params: {'p_staff_member_id': staffMemberId},
    );
    return _inviteFromRow(rows.single as Map<String, dynamic>);
  }

  @override
  Future<void> acceptInvite(String token) async {
    await _client.rpc<void>('accept_invite', params: {'p_token': token});
  }

  StaffInvite _inviteFromRow(Map<String, dynamic> row) {
    return StaffInvite(
      staffMemberId: row['staff_member_id'] as String,
      cellNumber: row['cell_number'] as String,
      token: row['token'] as String,
    );
  }
}
