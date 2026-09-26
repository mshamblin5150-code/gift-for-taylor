import 'package:flutter/foundation.dart';

import 'undelivered_invitation_log.dart';

sealed class UndeliveredInvitationsState {
  const UndeliveredInvitationsState();
}

final class UndeliveredInvitationsLoading extends UndeliveredInvitationsState {
  const UndeliveredInvitationsLoading();
}

final class UndeliveredInvitationsLoaded extends UndeliveredInvitationsState {
  UndeliveredInvitationsLoaded(List<UndeliveredInvitation> invitations)
    : invitations = List.unmodifiable(invitations);

  final List<UndeliveredInvitation> invitations;
}

final class UndeliveredInvitationsFailed extends UndeliveredInvitationsState {
  const UndeliveredInvitationsFailed();
}

final class UndeliveredInvitationsSession extends ChangeNotifier {
  UndeliveredInvitationsSession(this._log);

  final UndeliveredInvitationLog _log;
  UndeliveredInvitationsState _state = const UndeliveredInvitationsLoading();
  bool _disposed = false;

  UndeliveredInvitationsState get state => _state;

  Future<void> load() async {
    try {
      _replace(UndeliveredInvitationsLoaded(await _log.read()));
    } catch (_) {
      _replace(const UndeliveredInvitationsFailed());
    }
  }

  void _replace(UndeliveredInvitationsState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
