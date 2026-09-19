import 'package:supabase_flutter/supabase_flutter.dart';

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
  });

  final String id;
  final String displayName;
  final String cellNumber;
  final String sectionId;
  final int displayOrder;
  final String? personalEmail;

  StaffListMember withDisplayOrder(int value) {
    return StaffListMember(
      id: id,
      displayName: displayName,
      cellNumber: cellNumber,
      sectionId: sectionId,
      displayOrder: value,
      personalEmail: personalEmail,
    );
  }
}

final class StaffList {
  const StaffList({required this.sections, required this.members});

  final List<StaffSection> sections;
  final List<StaffListMember> members;

  List<StaffListMember> membersInSection(String sectionId) {
    return members.where((member) => member.sectionId == sectionId).toList()
      ..sort(
        (left, right) => left.displayOrder.compareTo(right.displayOrder),
      );
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

abstract interface class StaffGateway {
  Future<bool> canManageStaff();
  Future<StaffList> loadStaffList();
  Future<StaffInvite> addStaffMember(StaffMemberDraft draft);
  Future<void> reorderSection(String sectionId, List<String> memberIds);
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
  Future<StaffList> loadStaffList() async {
    final results = await Future.wait([
      _client.from('sections').select('id, name').order('display_order'),
      _client
          .from('staff_list_entries')
          .select(
            'id, display_name, cell_number, section_id, display_order, personal_email',
          )
          .order('display_order'),
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
              cellNumber: row['cell_number'] as String,
              sectionId: row['section_id'] as String,
              displayOrder: row['display_order'] as int,
              personalEmail: row['personal_email'] as String?,
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<StaffInvite> addStaffMember(StaffMemberDraft draft) async {
    final rows = await _client.rpc<List<dynamic>>(
      'create_staff_member_with_invite',
      params: {
        'p_display_name': draft.displayName,
        'p_cell_number': draft.cellNumber,
        'p_section_id': draft.sectionId,
      },
    );
    return _inviteFromRow(rows.single as Map<String, dynamic>);
  }

  @override
  Future<void> reorderSection(
    String sectionId,
    List<String> memberIds,
  ) async {
    await _client.rpc<void>(
      'reorder_staff_section',
      params: {
        'p_section_id': sectionId,
        'p_staff_member_ids': memberIds,
      },
    );
  }

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
