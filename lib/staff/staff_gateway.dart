import 'package:schedule_rules/schedule_rules.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../schedule/access_rejected_write.dart';
import 'staff_contacts.dart';
import 'access_row.dart';

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
    this.inviteCellMismatchAt,
  });

  final String id;
  final String displayName;

  /// Missing for people loaded from the printed page until one is added.
  final String? cellNumber;
  final String sectionId;
  final int displayOrder;
  final String? personalEmail;
  final DateTime? inviteCellMismatchAt;

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
      inviteCellMismatchAt: inviteCellMismatchAt,
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
    this.cellNumber,
  });

  final String id;
  final String displayName;
  final DateTime? lastDay;
  final String? cellNumber;

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

enum InviteAcceptanceResult { accepted, cellMismatch, throttled }

final class StaffInviteAlreadyLinkedException implements Exception {
  const StaffInviteAlreadyLinkedException();
}

final class InvalidInviteException implements Exception {
  const InvalidInviteException();
}

enum ManagerHandoverRefusal {
  managerAccessChanged,
  noActiveManager,
  sameStaffMember,
  retainedSectionMissing,
  successorNoAccount,
  successorInvitePending,
  successorAccountRevoked,
  successorInactive,
  successorAlreadyManager,
  successorNoCurrentSection,
}

final class ManagerHandoverRefused implements Exception {
  const ManagerHandoverRefused(this.reason);

  final ManagerHandoverRefusal reason;
}

enum InviteAcceptanceRefusal {
  staffAcceptancePending,
  staffAlreadyAccepted,
  emailAcceptancePending,
  accountMissingEmail,
}

final class InviteAcceptanceRefused implements Exception {
  const InviteAcceptanceRefused(this.reason);

  final InviteAcceptanceRefusal reason;
}

Future<T> mapManagerHandoverRefusal<T>(Future<T> Function() command) async {
  try {
    return await command();
  } on PostgrestException catch (error) {
    final reason = switch (error.code) {
      'P2797' => ManagerHandoverRefusal.managerAccessChanged,
      'P2798' => ManagerHandoverRefusal.noActiveManager,
      'P2799' => ManagerHandoverRefusal.sameStaffMember,
      'P2800' => ManagerHandoverRefusal.retainedSectionMissing,
      'P2801' => ManagerHandoverRefusal.successorNoAccount,
      'P2802' => ManagerHandoverRefusal.successorInvitePending,
      'P2803' => ManagerHandoverRefusal.successorAccountRevoked,
      'P2804' => ManagerHandoverRefusal.successorInactive,
      'P2805' => ManagerHandoverRefusal.successorAlreadyManager,
      'P2806' => ManagerHandoverRefusal.successorNoCurrentSection,
      _ => null,
    };
    if (reason != null) throw ManagerHandoverRefused(reason);
    rethrow;
  }
}

Future<T> mapInviteAcceptanceRefusal<T>(Future<T> Function() command) async {
  try {
    return await command();
  } on PostgrestException catch (error) {
    final reason = switch (error.code) {
      'P2807' => InviteAcceptanceRefusal.staffAcceptancePending,
      'P2808' => InviteAcceptanceRefusal.staffAlreadyAccepted,
      'P2809' => InviteAcceptanceRefusal.emailAcceptancePending,
      'P2810' => InviteAcceptanceRefusal.accountMissingEmail,
      _ => null,
    };
    if (reason != null) throw InviteAcceptanceRefused(reason);
    rethrow;
  }
}

final class SectionInUseException implements Exception {
  const SectionInUseException();
}

final class PendingInviteAcceptance {
  const PendingInviteAcceptance({
    required this.inviteId,
    required this.staffMemberName,
    required this.personalEmail,
    required this.acceptedAt,
  });

  final String inviteId;
  final String staffMemberName;
  final String personalEmail;
  final DateTime acceptedAt;
}

final class StaffMemberDetails {
  const StaffMemberDetails({
    required this.id,
    required this.displayName,
    required this.sectionId,
    required this.grants,
    this.cellNumber,
    this.personalEmail,
    this.jobRole,
    this.lastDay,
  });

  final String id;
  final String displayName;
  final String? cellNumber;
  final String? sectionId;
  final Grants grants;
  final String? personalEmail;
  final JobRole? jobRole;
  final DateTime? lastDay;
}

final class StaffAccessChange {
  const StaffAccessChange({
    required this.oldRole,
    required this.newRole,
    required this.changedAt,
  });
  final String oldRole;
  final String newRole;
  final DateTime changedAt;
}

enum ManagerHandoverBlocker {
  noStaffAccount,
  inviteAcceptancePending,
  accountRevoked,
  inactive,
  alreadyManager,
  noCurrentSection;

  static ManagerHandoverBlocker fromValue(String value) => switch (value) {
    'no_staff_account' => noStaffAccount,
    'invite_acceptance_pending' => inviteAcceptancePending,
    'account_revoked' => accountRevoked,
    'inactive' => inactive,
    'already_manager' => alreadyManager,
    'no_current_section' => noCurrentSection,
    _ => throw StateError('Unknown Manager handover blocker: $value'),
  };
}

final class ManagerHandoverCandidate {
  const ManagerHandoverCandidate({
    required this.id,
    required this.displayName,
    this.blocker,
  });

  final String id;
  final String displayName;
  final ManagerHandoverBlocker? blocker;

  bool get isEligible => blocker == null;
}

abstract interface class StaffGateway {
  Future<Access> currentAccess();
  Future<List<ManagerHandoverCandidate>> loadManagerHandoverCandidates();
  Future<StaffList> loadStaffList();
  Future<StaffMemberDetails> loadStaffMemberDetails(String staffMemberId);
  Future<List<StaffAccessChange>> loadStaffAccessChanges(String staffMemberId);
  Future<Grants> loadAccessGrants(String staffMemberId);
  Future<void> setAccessGrants(String staffMemberId, Grants grants);
  Future<void> transferManagerWithAccess(
    String newManagerId,
    bool formerAdministrator,
    Set<String> formerSectionIds,
  );
  Future<void> updateStaffContact(
    String staffMemberId,
    String displayName,
    String? cellNumber,
  );

  /// Everyone who has left, most recent Last day first.
  Future<List<PastStaffMember>> loadPastStaff();
  Future<StaffInvite> addStaffMember(
    StaffMemberDraft draft, {
    bool allowRecycledCell = false,
  });
  Future<void> reorderSection(String sectionId, List<String> memberIds);
  Future<void> reorderSections(List<String> sectionIds);
  Future<void> addSection(String name);
  Future<void> renameSection(String sectionId, String name);
  Future<void> deleteEmptySection(String sectionId);
  Future<StaffInvite> resendInvite(String staffMemberId);
  Future<InviteAcceptanceResult> acceptInvite(String token, String cellNumber);
  Future<List<PendingInviteAcceptance>> pendingInviteAcceptances();
  Future<void> confirmInviteAcceptance(String inviteId);
  Future<void> rejectInviteAcceptance(String inviteId);
  Future<bool> isInviteAcceptancePending();
}

final class SupabaseStaffGateway implements StaffGateway {
  SupabaseStaffGateway(this._client, {this.onAccessLoaded});

  final SupabaseClient _client;
  final void Function(Access access)? onAccessLoaded;

  @override
  Future<Access> currentAccess() async {
    final row = await _client.rpc('current_access') as List<dynamic>;
    final access = accessFromRow(row.single as Map<String, dynamic>);
    onAccessLoaded?.call(access);
    return access;
  }

  @override
  Future<List<ManagerHandoverCandidate>> loadManagerHandoverCandidates() async {
    final rows = await _client.rpc<List<dynamic>>(
      'manager_handover_candidates',
    );
    return [
      for (final row in rows)
        ManagerHandoverCandidate(
          id: row['staff_member_id'] as String,
          displayName: row['display_name'] as String,
          blocker: switch (row['eligibility_code']) {
            final String value => ManagerHandoverBlocker.fromValue(value),
            _ => null,
          },
        ),
    ];
  }

  @override
  Future<void> transferManagerWithAccess(
    String newManagerId,
    bool formerAdministrator,
    Set<String> formerSectionIds,
  ) => mapManagerHandoverRefusal(
    () => mapAccessRejected(
      () => _client.rpc<void>(
        'transfer_manager_with_access',
        params: {
          'p_new_manager_id': newManagerId,
          'p_former_administrator': formerAdministrator,
          'p_former_section_ids': formerSectionIds.toList(),
        },
      ),
    ),
  );

  @override
  Future<Grants> loadAccessGrants(String staffMemberId) async {
    final details = await loadStaffMemberDetails(staffMemberId);
    final rows = await _client
        .from('night_scheduler_sections')
        .select('section_id')
        .eq('staff_member_id', staffMemberId);
    return details.grants.copyWith(
      nightSchedulerSectionIds: {
        for (final row in rows) row['section_id'] as String,
      },
    );
  }

  @override
  Future<void> setAccessGrants(String staffMemberId, Grants grants) =>
      mapAccessRejected(
        () => _client.rpc<void>(
          'set_staff_access_grants',
          params: {
            'p_staff_member_id': staffMemberId,
            'p_administrator': grants.administrator,
            'p_section_ids': grants.nightSchedulerSectionIds.toList(),
          },
        ),
      );

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
            'personal_email, job_role, invite_cell_mismatch_at',
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
              inviteCellMismatchAt: switch (row['invite_cell_mismatch_at']) {
                final String value => DateTime.parse(value),
                _ => null,
              },
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
      grants: Grants(
        manager: row['role'] == 'manager',
        administrator: row['role'] == 'administrator',
      ),
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
  Future<List<StaffAccessChange>> loadStaffAccessChanges(
    String staffMemberId,
  ) async {
    final rows = await _client
        .from('staff_changes')
        .select('old_value, new_value, changed_at')
        .eq('staff_member_id', staffMemberId)
        .eq('kind', 'access_role')
        .order('changed_at', ascending: false);
    return [
      for (final row in rows)
        StaffAccessChange(
          oldRole: row['old_value'] as String,
          newRole: row['new_value'] as String,
          changedAt: DateTime.parse(row['changed_at'] as String).toLocal(),
        ),
    ];
  }

  @override
  Future<void> updateStaffContact(
    String staffMemberId,
    String displayName,
    String? cellNumber,
  ) => mapAccessRejected(
    () => _client.rpc<void>(
      'update_staff_contact',
      params: {
        'p_staff_member_id': staffMemberId,
        'p_display_name': displayName,
        'p_cell_number': cellNumber == null
            ? ''
            : normalizeCellNumber(cellNumber),
      },
    ),
  );

  @override
  Future<List<PastStaffMember>> loadPastStaff() async {
    final rows = await _client
        .from('past_staff_entries')
        .select('id, display_name, cell_number, last_day, section_id')
        .order('last_day', ascending: false);
    return [
      for (final row in rows)
        PastStaffMember(
          id: row['id'] as String,
          displayName: row['display_name'] as String,
          cellNumber: row['cell_number'] as String?,
          lastDay: switch (row['last_day']) {
            final String value => DateTime.parse(value),
            _ => null,
          },
          sectionId: row['section_id'] as String?,
        ),
    ];
  }

  @override
  Future<StaffInvite> addStaffMember(
    StaffMemberDraft draft, {
    bool allowRecycledCell = false,
  }) async {
    final rows = await _client.rpc<List<dynamic>>(
      'create_staff_member_with_invite',
      params: {
        'p_display_name': draft.displayName,
        'p_cell_number': normalizeCellNumber(draft.cellNumber),
        'p_section_id': draft.sectionId,
        'p_allow_recycled_cell': allowRecycledCell,
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
  Future<void> deleteEmptySection(String sectionId) async {
    try {
      await _client.rpc<void>(
        'delete_empty_section',
        params: {'p_section_id': sectionId},
      );
    } on PostgrestException catch (error) {
      if (error.code == 'P2795') throw const SectionInUseException();
      rethrow;
    }
  }

  @override
  Future<StaffInvite> resendInvite(String staffMemberId) async {
    final rows = await mapAccessRejected(
      () => _client.rpc<List<dynamic>>(
        'resend_staff_invite',
        params: {'p_staff_member_id': staffMemberId},
      ),
    );
    return _inviteFromRow(rows.single as Map<String, dynamic>);
  }

  @override
  Future<InviteAcceptanceResult> acceptInvite(
    String token,
    String cellNumber,
  ) async {
    String result;
    try {
      result = await mapInviteAcceptanceRefusal(
        () => _client.rpc<String>(
          'accept_invite',
          params: {'p_token': token, 'p_cell_number': cellNumber},
        ),
      );
    } on PostgrestException catch (error) {
      if (error.code == 'P2793') {
        throw const StaffInviteAlreadyLinkedException();
      }
      if (error.code == 'P2794') throw const InvalidInviteException();
      rethrow;
    }
    return switch (result) {
      'accepted' => InviteAcceptanceResult.accepted,
      'cell_mismatch' => InviteAcceptanceResult.cellMismatch,
      'throttled' => InviteAcceptanceResult.throttled,
      _ => throw StateError('Unknown Invite acceptance result'),
    };
  }

  @override
  Future<List<PendingInviteAcceptance>> pendingInviteAcceptances() async {
    final rows = await _client
        .from('pending_invite_acceptances')
        .select(
          'invite_id, personal_email, accepted_at, '
          'staff_members!inner(display_name)',
        );
    return [
      for (final row in rows)
        PendingInviteAcceptance(
          inviteId: row['invite_id'] as String,
          staffMemberName:
              (row['staff_members'] as Map<String, dynamic>)['display_name']
                  as String,
          personalEmail: row['personal_email'] as String,
          acceptedAt: DateTime.parse(row['accepted_at'] as String).toLocal(),
        ),
    ];
  }

  @override
  Future<void> confirmInviteAcceptance(String inviteId) => _client.rpc<void>(
    'confirm_invite_acceptance',
    params: {'p_invite_id': inviteId},
  );

  @override
  Future<void> rejectInviteAcceptance(String inviteId) => _client.rpc<void>(
    'reject_invite_acceptance',
    params: {'p_invite_id': inviteId},
  );

  @override
  Future<bool> isInviteAcceptancePending() async =>
      await _client.rpc<bool>('my_invite_acceptance_pending');

  StaffInvite _inviteFromRow(Map<String, dynamic> row) {
    return StaffInvite(
      staffMemberId: row['staff_member_id'] as String,
      cellNumber: row['cell_number'] as String,
      token: row['token'] as String,
    );
  }
}
