import 'package:flutter/foundation.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'staff_gateway.dart';

final class StaffDetailsState {
  StaffDetailsState({
    this.details,
    this.list,
    Access? access,
    this.accessChanges = const [],
    this.handoverCandidate,
    Grants? targetGrants,
    this.loadError,
  }) : access = access ?? Access(grants: Grants()),
       targetGrants = targetGrants ?? Grants();

  final StaffMemberDetails? details;
  final StaffList? list;
  final Access access;
  final List<StaffAccessChange> accessChanges;
  final ManagerHandoverCandidate? handoverCandidate;
  final Grants targetGrants;
  final Object? loadError;
}

sealed class StaffCommandOutcome {
  const StaffCommandOutcome();
}

final class StaffCommandSaved extends StaffCommandOutcome {
  const StaffCommandSaved();
}

final class StaffCommandFailed extends StaffCommandOutcome {
  const StaffCommandFailed([this.error]);

  final Object? error;
}

sealed class StaffInviteOutcome {
  const StaffInviteOutcome();
}

final class StaffInviteReady extends StaffInviteOutcome {
  const StaffInviteReady(this.invite);

  final StaffInvite invite;
}

final class StaffInviteFailed extends StaffInviteOutcome {
  const StaffInviteFailed();
}

final class StaffDetailsSession extends ChangeNotifier {
  StaffDetailsSession(
    this.staffMemberId,
    this._gateway,
    this._rules, [
    this._onAccessRejected,
  ]);

  final String staffMemberId;
  final StaffGateway _gateway;
  final ScheduleRules _rules;
  final VoidCallback? _onAccessRejected;
  StaffDetailsState _state = StaffDetailsState();
  bool _disposed = false;

  StaffDetailsState get state => _state;

  Future<void> load() async {
    try {
      final (
        details,
        list,
        access,
        accessChanges,
        handoverCandidates,
        targetGrants,
      ) = await (
        _gateway.loadStaffMemberDetails(staffMemberId),
        _gateway.loadStaffList(),
        _gateway.currentAccess(),
        _gateway.loadStaffAccessChanges(staffMemberId),
        _gateway.loadManagerHandoverCandidates(),
        _gateway.loadAccessGrants(staffMemberId),
      ).wait;
      _replace(
        StaffDetailsState(
          details: details,
          list: list,
          access: access,
          accessChanges: accessChanges,
          handoverCandidate: handoverCandidates
              .where((candidate) => candidate.id == staffMemberId)
              .firstOrNull,
          targetGrants: targetGrants,
        ),
      );
    } catch (error) {
      _replace(StaffDetailsState(loadError: error));
    }
  }

  Future<StaffCommandOutcome> updateContact(
    String displayName,
    String? cellNumber,
  ) => _write(
    () => _gateway.updateStaffContact(staffMemberId, displayName, cellNumber),
  );

  Future<StaffCommandOutcome> changeSectionOrRole({
    required DateTime from,
    String? sectionId,
    JobRole? jobRole,
  }) => _write(() async {
    if (sectionId != null) {
      await _rules.store.changeSection(
        ChangeSection(
          staffMemberId: staffMemberId,
          sectionId: sectionId,
          from: from,
        ),
      );
    }
    if (jobRole != null) {
      await _rules.store.changeJobRole(
        ChangeJobRole(
          staffMemberId: staffMemberId,
          jobRole: jobRole,
          from: from,
        ),
      );
    }
  });

  Future<StaffCommandOutcome> setLastDay(DateTime day) => _write(
    () => _rules.store.setLastDay(
      SetLastDay(staffMemberId: staffMemberId, lastDay: day),
    ),
    reloadOnFailure: false,
  );

  Future<StaffInviteOutcome> resendInvite() async {
    try {
      return StaffInviteReady(await _gateway.resendInvite(staffMemberId));
    } catch (error) {
      if (error is AccessRejected) _onAccessRejected?.call();
      return const StaffInviteFailed();
    }
  }

  Future<StaffCommandOutcome> saveAccess({
    required Grants grants,
    required bool transfer,
    required bool formerAdministrator,
    required Set<String> formerSections,
  }) => _write(() async {
    if (transfer) {
      await _gateway.transferManagerWithAccess(
        staffMemberId,
        formerAdministrator,
        formerSections,
      );
    } else {
      await _gateway.setAccessGrants(staffMemberId, grants);
    }
  }, reloadOnFailure: false);

  Future<StaffCommandOutcome> _write(
    Future<void> Function() command, {
    bool reloadOnFailure = true,
  }) async {
    try {
      await command();
      await load();
      return const StaffCommandSaved();
    } catch (error) {
      if (error is AccessRejected) _onAccessRejected?.call();
      if (reloadOnFailure) await load();
      return StaffCommandFailed(error);
    }
  }

  void _replace(StaffDetailsState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
