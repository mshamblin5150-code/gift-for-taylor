import 'package:flutter/foundation.dart';

import 'ticket_gateway.dart';

enum TicketFormState { idle, sending }

sealed class PutInTicketOutcome {
  const PutInTicketOutcome();
}

final class TicketSent extends PutInTicketOutcome {
  const TicketSent();
}

final class TicketPutInRefused extends PutInTicketOutcome {
  const TicketPutInRefused(this.reason);
  final TicketSubmissionRefusal reason;
}

final class TicketPutInFailed extends PutInTicketOutcome {
  const TicketPutInFailed();
}

final class TicketFormSession extends ChangeNotifier {
  TicketFormSession(this._gateway);

  final TicketGateway _gateway;
  TicketFormState _state = TicketFormState.idle;
  bool _disposed = false;

  TicketFormState get state => _state;

  Future<PutInTicketOutcome> putIn({
    required TicketKind kind,
    required String text,
    required TicketContext context,
  }) async {
    if (_state == TicketFormState.sending) return const TicketPutInFailed();
    _replace(TicketFormState.sending);
    try {
      await _gateway.putIn(kind: kind, text: text, context: context);
      return const TicketSent();
    } on TicketSubmissionRefused catch (failure) {
      return TicketPutInRefused(failure.reason);
    } catch (_) {
      return const TicketPutInFailed();
    } finally {
      _replace(TicketFormState.idle);
    }
  }

  void _replace(TicketFormState state) {
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

sealed class TicketsState {
  const TicketsState();
}

final class TicketsLoading extends TicketsState {
  const TicketsLoading();
}

final class TicketsLoaded extends TicketsState {
  TicketsLoaded(List<Ticket> tickets) : tickets = List.unmodifiable(tickets);
  final List<Ticket> tickets;
}

final class TicketsFailed extends TicketsState {
  const TicketsFailed();
}

final class TicketsSession extends ChangeNotifier {
  TicketsSession(this._gateway);

  final TicketGateway _gateway;
  TicketsState _state = const TicketsLoading();
  bool _disposed = false;

  TicketsState get state => _state;

  Future<void> load() async {
    _replace(const TicketsLoading());
    try {
      _replace(TicketsLoaded(await _gateway.read()));
    } catch (_) {
      _replace(const TicketsFailed());
    }
  }

  void _replace(TicketsState state) {
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

sealed class TicketDetailState {
  const TicketDetailState();
}

final class TicketDetailLoading extends TicketDetailState {
  const TicketDetailLoading();
}

final class TicketDetailLoaded extends TicketDetailState {
  const TicketDetailLoaded(this.ticket);
  final Ticket ticket;
}

final class TicketDetailFailed extends TicketDetailState {
  const TicketDetailFailed();
}

final class TicketDetailSession extends ChangeNotifier {
  TicketDetailSession(this._gateway, this._ticket, this._maintainer);

  final TicketGateway _gateway;
  final Ticket _ticket;
  final bool _maintainer;
  TicketDetailState _state = const TicketDetailLoading();
  bool _disposed = false;

  TicketDetailState get state => _state;

  Future<void> load() async {
    try {
      final ticket = _maintainer
          ? await _gateway.openForMaintainer(_ticket.id)
          : _ticket;
      _replace(TicketDetailLoaded(ticket));
    } catch (_) {
      _replace(const TicketDetailFailed());
    }
  }

  void _replace(TicketDetailState state) {
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
