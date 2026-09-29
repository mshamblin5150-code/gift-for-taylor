import 'package:flutter/foundation.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'staff_gateway.dart';

final class StaffListState {
  StaffListState({
    this.list,
    this.pendingInvites = const [],
    Access? access,
    this.loadError,
    this.savingSectionOrder = false,
  }) : access = access ?? Access(grants: Grants());

  final StaffList? list;
  final List<PendingInviteAcceptance> pendingInvites;
  final Access access;
  final Object? loadError;
  final bool savingSectionOrder;
}

sealed class DeleteSectionOutcome {
  const DeleteSectionOutcome();
}

final class SectionDeleted extends DeleteSectionOutcome {
  const SectionDeleted();
}

final class SectionDeleteRefused extends DeleteSectionOutcome {
  const SectionDeleteRefused(this.code);
  final String code;
}

final class SectionDeleteFailed extends DeleteSectionOutcome {
  const SectionDeleteFailed();
}

sealed class ReorderStaffOutcome {
  const ReorderStaffOutcome();
}

final class StaffReordered extends ReorderStaffOutcome {
  const StaffReordered();
}

final class StaffReorderFailed extends ReorderStaffOutcome {
  const StaffReorderFailed();
}

sealed class StaffListWriteOutcome {
  const StaffListWriteOutcome();
}

final class StaffListWriteSaved extends StaffListWriteOutcome {
  const StaffListWriteSaved();
}

final class StaffListWriteFailed extends StaffListWriteOutcome {
  const StaffListWriteFailed([this.error]);
  final Object? error;
}

sealed class StaffListInviteOutcome {
  const StaffListInviteOutcome();
}

final class StaffListInviteReady extends StaffListInviteOutcome {
  const StaffListInviteReady(this.invite);
  final StaffInvite invite;
}

final class StaffListInviteFailed extends StaffListInviteOutcome {
  const StaffListInviteFailed([this.error]);
  final Object? error;
}

sealed class PastStaffOutcome {
  const PastStaffOutcome();
}

final class PastStaffLoaded extends PastStaffOutcome {
  const PastStaffLoaded(this.staff);
  final List<PastStaffMember> staff;
}

final class PastStaffLoadFailed extends PastStaffOutcome {
  const PastStaffLoadFailed();
}

final class StaffListSession extends ChangeNotifier {
  StaffListSession(this._gateway, this._rules, [this._onAccessRejected]) {
    load();
  }

  final StaffGateway _gateway;
  final ScheduleRules _rules;
  final VoidCallback? _onAccessRejected;
  StaffListState _state = StaffListState();
  bool _disposed = false;

  StaffListState get state => _state;

  Future<void> load() async {
    try {
      final (list, access, pendingInvites) = await (
        _gateway.loadStaffList(),
        _gateway.currentAccess(),
        _gateway.pendingInviteAcceptances(),
      ).wait;
      _replace(
        StaffListState(
          list: list,
          access: access,
          pendingInvites: List.unmodifiable(pendingInvites),
          savingSectionOrder: _state.savingSectionOrder,
        ),
      );
    } catch (error) {
      _replace(
        StaffListState(
          list: _state.list,
          access: _state.access,
          pendingInvites: _state.pendingInvites,
          loadError: error,
          savingSectionOrder: _state.savingSectionOrder,
        ),
      );
    }
  }

  Future<DeleteSectionOutcome> deleteSection(String sectionId) async {
    try {
      await _gateway.deleteEmptySection(sectionId);
      await load();
      return const SectionDeleted();
    } on SectionInUseException catch (error) {
      return SectionDeleteRefused(error.refusalCode);
    } on SectionHasScheduleHistoryException catch (error) {
      return SectionDeleteRefused(error.refusalCode);
    } catch (error) {
      _rejected(error);
      return const SectionDeleteFailed();
    }
  }

  Future<PastStaffOutcome> loadPastStaff() async {
    try {
      return PastStaffLoaded(await _gateway.loadPastStaff());
    } catch (error) {
      _rejected(error);
      return const PastStaffLoadFailed();
    }
  }

  Future<StaffListInviteOutcome> addStaffMember(
    StaffMemberDraft draft, {
    required bool allowRecycledCell,
  }) async {
    try {
      final invite = await _gateway.addStaffMember(
        draft,
        allowRecycledCell: allowRecycledCell,
      );
      await load();
      return StaffListInviteReady(invite);
    } catch (error) {
      _rejected(error);
      return StaffListInviteFailed(error);
    }
  }

  Future<StaffListInviteOutcome> resendInvite(String staffMemberId) async {
    try {
      return StaffListInviteReady(await _gateway.resendInvite(staffMemberId));
    } catch (error) {
      _rejected(error);
      return StaffListInviteFailed(error);
    }
  }

  Future<StaffListWriteOutcome> reactivate(Reactivate reactivation) =>
      _write(() => _rules.store.reactivate(reactivation));

  Future<StaffListWriteOutcome> setLastDay(SetLastDay change) =>
      _write(() => _rules.store.setLastDay(change));

  Future<StaffListWriteOutcome> changeSectionOrRole({
    ChangeSection? section,
    ChangeJobRole? jobRole,
  }) => _write(() async {
    if (section != null) await _rules.store.changeSection(section);
    if (jobRole != null) await _rules.store.changeJobRole(jobRole);
  });

  Future<StaffListWriteOutcome> addSection(String name) =>
      _write(() => _gateway.addSection(name));

  Future<StaffListWriteOutcome> renameSection(String sectionId, String name) =>
      _write(() => _gateway.renameSection(sectionId, name));

  Future<StaffListWriteOutcome> decideInvite(
    String inviteId, {
    required bool confirm,
  }) => _write(
    () => confirm
        ? _gateway.confirmInviteAcceptance(inviteId)
        : _gateway.rejectInviteAcceptance(inviteId),
  );

  Future<StaffListWriteOutcome> _write(Future<void> Function() command) async {
    try {
      await command();
      await load();
      return const StaffListWriteSaved();
    } catch (error) {
      _rejected(error);
      return StaffListWriteFailed(error);
    }
  }

  void _rejected(Object error) {
    if (error is AccessRejected) _onAccessRejected?.call();
  }

  Future<ReorderStaffOutcome> reorderMembers(
    StaffSection section,
    List<StaffListMember> reordered,
  ) async {
    final current = _state.list;
    if (current == null) return const StaffReorderFailed();
    _replace(
      StaffListState(
        list: current.withSectionOrder(section.id, reordered),
        access: _state.access,
        pendingInvites: _state.pendingInvites,
      ),
    );
    try {
      await _gateway.reorderSection(
        section.id,
        reordered.map((member) => member.id).toList(growable: false),
      );
      return const StaffReordered();
    } catch (error) {
      _rejected(error);
      await load();
      return const StaffReorderFailed();
    }
  }

  Future<ReorderStaffOutcome> reorderSections(
    List<StaffSection> ordered,
  ) async {
    final current = _state.list;
    if (current == null || _state.savingSectionOrder) {
      return const StaffReorderFailed();
    }
    _replace(
      StaffListState(
        list: current.withSections(ordered),
        access: _state.access,
        pendingInvites: _state.pendingInvites,
        savingSectionOrder: true,
      ),
    );
    try {
      await _gateway.reorderSections([
        for (final section in ordered) section.id,
      ]);
      return const StaffReordered();
    } catch (error) {
      _rejected(error);
      await load();
      return const StaffReorderFailed();
    } finally {
      _replace(
        StaffListState(
          list: _state.list,
          access: _state.access,
          pendingInvites: _state.pendingInvites,
          loadError: _state.loadError,
        ),
      );
    }
  }

  void _replace(StaffListState next) {
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
