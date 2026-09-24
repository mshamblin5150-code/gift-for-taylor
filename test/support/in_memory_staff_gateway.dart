import 'dart:async';

import 'package:er_schedule/staff/staff_gateway.dart';
import 'package:schedule_rules/schedule_rules.dart';

final class InMemoryStaffGateway implements StaffGateway {
  InMemoryStaffGateway({
    StaffList? list,
    this.pastStaff = const [],
    this.currentId,
    this.actorRole = 'staff_member',
    this.handoverCandidates = const [],
  }) : _list = list ?? const StaffList(sections: [], members: []);

  StaffList get list => _list;

  @override
  Future<Access> currentAccess() async => Access(
    grants: Grants(
      manager: actorRole == 'manager',
      administrator: actorRole == 'administrator',
      nightSchedulerSectionIds: currentId == null ? {} : nightSections,
    ),
    maintainer: actorRole == 'maintainer',
    ownStaffMemberId: currentId,
    activeRepair: activeRepair,
  );
  MaintainerRepair? activeRepair;
  List<ManagerHandoverCandidate> handoverCandidates;

  @override
  Future<List<ManagerHandoverCandidate>>
  loadManagerHandoverCandidates() async => handoverCandidates;
  @override
  Future<List<StaffAccessChange>> loadStaffAccessChanges(String id) async =>
      accessRole == null
      ? []
      : [
          StaffAccessChange(
            oldRole: 'staff_member',
            newRole: accessRole!,
            changedAt: DateTime(2026, 9, 19),
          ),
        ];
  @override
  Future<Grants> loadAccessGrants(String id) async =>
      grantsByStaff[id] ??
      (grantsByStaff.isEmpty
          ? Grants(
              manager: accessRole == 'manager',
              administrator: accessRole == 'administrator',
              nightSchedulerSectionIds: nightSections,
            )
          : Grants());

  @override
  Future<void> setAccessGrants(String id, Grants grants) async {
    grantsByStaff[id] = grants;
    accessRole = grants.manager
        ? 'manager'
        : grants.administrator
        ? 'administrator'
        : grants.nightSchedulerSectionIds.isNotEmpty
        ? 'night_scheduler'
        : 'staff_member';
    nightSections = {...grants.nightSchedulerSectionIds};
  }

  final Map<String, Grants> grantsByStaff = {};
  Set<String> nightSections = {};

  String actorRole;
  String? currentId;
  List<PendingInviteAcceptance> invites = [];
  String? confirmedInviteId;
  String? rejectedInviteId;

  @override
  Future<void> transferManagerWithAccess(
    String id,
    bool formerAdministrator,
    Set<String> formerSections,
  ) async {
    if (transferError case final error?) throw error;
    accessRole = 'manager';
    grantsByStaff[id] = (await loadAccessGrants(id)).copyWith(manager: true);
    actorRole = formerAdministrator
        ? 'administrator'
        : formerSections.isNotEmpty
        ? 'night_scheduler'
        : 'staff_member';
  }

  Object? transferError;

  String? accessRole;
  DateTime? accessLastDay;
  @override
  Future<StaffMemberDetails> loadStaffMemberDetails(String id) async {
    final member = _list.members.where((member) => member.id == id).firstOrNull;
    final past = pastStaff.where((member) => member.id == id).firstOrNull;
    return StaffMemberDetails(
      id: id,
      displayName: member?.displayName ?? past!.displayName,
      cellNumber: member?.cellNumber ?? past?.cellNumber,
      sectionId: member?.sectionId ?? past?.sectionId,
      personalEmail: member?.personalEmail,
      jobRole: member?.jobRole,
      grants: await loadAccessGrants(id),
      lastDay: accessLastDay ?? past?.lastDay,
    );
  }

  @override
  Future<void> updateStaffContact(String id, String name, String? cell) async {
    if (updateContactError case final error?) throw error;
    _list = StaffList(
      sections: _list.sections,
      members: [
        for (final member in _list.members)
          if (member.id == id)
            StaffListMember(
              id: id,
              displayName: name,
              cellNumber: cell,
              sectionId: member.sectionId,
              displayOrder: member.displayOrder,
              personalEmail: member.personalEmail,
              jobRole: member.jobRole,
            )
          else
            member,
      ],
    );
  }

  Object? updateContactError;

  StaffList _list;
  final List<PastStaffMember> pastStaff;
  StaffMemberDraft? added;
  bool allowedRecycledCell = false;
  String? resentStaffMemberId;
  int loads = 0;
  List<String>? orderedSections;
  Completer<void>? orderGate;
  String? deletedSection;

  @override
  Future<StaffList> loadStaffList() async {
    loads++;
    return _list;
  }

  @override
  Future<List<PastStaffMember>> loadPastStaff() async => pastStaff;

  @override
  Future<StaffInvite> addStaffMember(
    StaffMemberDraft draft, {
    bool allowRecycledCell = false,
  }) async {
    added = draft;
    allowedRecycledCell = allowRecycledCell;
    final member = StaffListMember(
      id: 'new-staff',
      displayName: draft.displayName,
      cellNumber: draft.cellNumber,
      sectionId: draft.sectionId,
      displayOrder: 0,
    );
    _list = StaffList(
      sections: _list.sections,
      members: [..._list.members, member],
    );
    return const StaffInvite(
      staffMemberId: 'new-staff',
      cellNumber: '5558675309',
      token: 'new-token',
    );
  }

  @override
  Future<InviteAcceptanceResult> acceptInvite(
    String token,
    String cellNumber,
  ) async {
    if (acceptanceError case final error?) {
      acceptanceError = null;
      throw error;
    }
    acceptedToken = token;
    acceptedCellNumber = cellNumber;
    _inviteAcceptancePending =
        acceptanceResult == InviteAcceptanceResult.accepted;
    return acceptanceResult;
  }

  Object? acceptanceError;
  InviteAcceptanceResult acceptanceResult = InviteAcceptanceResult.accepted;
  String? acceptedToken;
  String? acceptedCellNumber;
  bool _inviteAcceptancePending = false;

  @override
  Future<bool> isInviteAcceptancePending() async => _inviteAcceptancePending;

  @override
  Future<List<PendingInviteAcceptance>> pendingInviteAcceptances() async =>
      invites;

  @override
  Future<void> confirmInviteAcceptance(String inviteId) async {
    confirmedInviteId = inviteId;
    invites.removeWhere((invite) => invite.inviteId == inviteId);
  }

  @override
  Future<void> rejectInviteAcceptance(String inviteId) async {
    rejectedInviteId = inviteId;
    invites.removeWhere((invite) => invite.inviteId == inviteId);
  }

  @override
  Future<void> addSection(String name) async {
    _list = _list.withSections([
      ..._list.sections,
      StaffSection(id: 'new-section', name: name),
    ]);
  }

  @override
  Future<void> renameSection(String sectionId, String name) async {
    _list = _list.withSections([
      for (final section in _list.sections)
        section.id == sectionId
            ? StaffSection(id: sectionId, name: name)
            : section,
    ]);
  }

  @override
  Future<void> deleteEmptySection(String sectionId) async {
    deletedSection = sectionId;
    _list = _list.withSections([
      for (final section in _list.sections)
        if (section.id != sectionId) section,
    ]);
  }

  @override
  Future<void> reorderSections(List<String> sectionIds) async {
    await orderGate?.future;
    orderedSections = sectionIds;
    _list = _list.withSections([
      for (final id in sectionIds)
        _list.sections.singleWhere((section) => section.id == id),
    ]);
  }

  @override
  Future<void> reorderSection(String sectionId, List<String> memberIds) async {
    _list = _list.withSectionOrder(sectionId, [
      for (final id in memberIds)
        _list.members.singleWhere((member) => member.id == id),
    ]);
  }

  @override
  Future<StaffInvite> resendInvite(String staffMemberId) async {
    if (resendInviteError case final error?) throw error;
    resentStaffMemberId = staffMemberId;
    return const StaffInvite(
      staffMemberId: 'staff-1',
      cellNumber: '5551112222',
      token: 'fresh-token',
    );
  }

  Object? resendInviteError;
}
