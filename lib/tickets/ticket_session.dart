import 'package:flutter/foundation.dart';
import 'package:schedule_rules/schedule_rules.dart';

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
  TicketFormSession(this._gateway, {this.onAccessRejected});

  final TicketGateway _gateway;
  final VoidCallback? onAccessRejected;
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
    } on AccessRejected {
      onAccessRejected?.call();
      return const TicketPutInFailed();
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
  TicketsSession(
    this._gateway, {
    required this.maintainer,
    this.ownStaffMemberId,
    this.onAccessRejected,
  }) : assert(maintainer || ownStaffMemberId != null);

  final TicketGateway _gateway;
  final bool maintainer;
  final String? ownStaffMemberId;
  final VoidCallback? onAccessRejected;
  TicketsState _state = const TicketsLoading();
  bool _disposed = false;

  TicketsState get state => _state;

  Future<void> load() async {
    _replace(const TicketsLoading());
    try {
      final tickets = maintainer
          ? await _gateway.readForMaintainer()
          : await _gateway.readMine(ownStaffMemberId!);
      _replace(TicketsLoaded(tickets));
    } on AccessRejected {
      onAccessRejected?.call();
      _replace(const TicketsFailed());
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
  TicketDetailLoaded(
    this.ticket,
    List<TicketThreadEntry> thread, {
    this.working = false,
  }) : thread = List.unmodifiable(thread);
  final Ticket ticket;
  final List<TicketThreadEntry> thread;
  final bool working;

  TicketDetailLoaded withWorking(bool value) =>
      TicketDetailLoaded(ticket, thread, working: value);
}

final class TicketDetailFailed extends TicketDetailState {
  const TicketDetailFailed();
}

sealed class TicketThreadCommandOutcome {
  const TicketThreadCommandOutcome();
}

final class TicketThreadCommandCompleted extends TicketThreadCommandOutcome {
  const TicketThreadCommandCompleted();
}

final class TicketThreadCommandRefused extends TicketThreadCommandOutcome {
  const TicketThreadCommandRefused(this.reason);
  final TicketThreadRefusal reason;
}

final class TicketThreadCommandFailed extends TicketThreadCommandOutcome {
  const TicketThreadCommandFailed();
}

final class TicketDetailSession extends ChangeNotifier {
  TicketDetailSession(
    this._gateway,
    this._ticket,
    this._maintainer, {
    this.onAccessRejected,
  });

  final TicketGateway _gateway;
  Ticket _ticket;
  final bool _maintainer;
  final VoidCallback? onAccessRejected;
  TicketDetailState _state = const TicketDetailLoading();
  bool _disposed = false;

  TicketDetailState get state => _state;

  Future<void> load() async {
    try {
      final ticket = _maintainer
          ? await _gateway.openForMaintainer(_ticket.id)
          : _ticket;
      _ticket = ticket;
      final thread = await _gateway.readThread(_ticket.id);
      _replace(TicketDetailLoaded(ticket, thread));
    } on AccessRejected {
      onAccessRejected?.call();
      _replace(const TicketDetailFailed());
    } catch (_) {
      _replace(const TicketDetailFailed());
    }
  }

  Future<TicketThreadCommandOutcome> askQuestion({
    required String question,
    String? suggestedAnswer,
  }) async => _runThreadCommand(() async {
    _ticket = await _gateway.askQuestion(
      _ticket.id,
      question: question,
      suggestedAnswer: suggestedAnswer,
    );
  });

  Future<TicketThreadCommandOutcome> answerQuestion(
    String questionId, {
    String? answer,
    required bool acceptSuggestion,
  }) async => _runThreadCommand(() async {
    _ticket = await _gateway.answerQuestion(
      _ticket.id,
      questionId,
      answer: answer,
      acceptSuggestion: acceptSuggestion,
    );
  });

  Future<TicketThreadCommandOutcome> _runThreadCommand(
    Future<void> Function() command,
  ) async {
    final current = _state;
    if (current is! TicketDetailLoaded || current.working) {
      return const TicketThreadCommandFailed();
    }
    _replace(current.withWorking(true));
    try {
      await command();
      final thread = await _gateway.readThread(_ticket.id);
      _replace(TicketDetailLoaded(_ticket, thread, working: true));
      return const TicketThreadCommandCompleted();
    } on TicketThreadRefused catch (failure) {
      return TicketThreadCommandRefused(failure.reason);
    } on AccessRejected {
      onAccessRejected?.call();
      return const TicketThreadCommandFailed();
    } catch (_) {
      return const TicketThreadCommandFailed();
    } finally {
      if (_state case final TicketDetailLoaded loaded) {
        _replace(loaded.withWorking(false));
      }
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
