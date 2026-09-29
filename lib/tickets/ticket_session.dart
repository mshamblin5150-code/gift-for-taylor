import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'ticket_gateway.dart';

typedef TicketTimerFactory = Timer Function(
  Duration delay,
  void Function() callback,
);

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
    } on Refused catch (failure) {
      if (failure.refusal case final TicketSubmissionRefusal reason) {
        return TicketPutInRefused(reason);
      }
      assert(
        false,
        'Unexpected Refusal family: ${failure.refusal.runtimeType}',
      );
      return const TicketPutInFailed();
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

sealed class TicketMutationOutcome {
  const TicketMutationOutcome();
}

final class TicketMutationSucceeded extends TicketMutationOutcome {
  const TicketMutationSucceeded();
}

final class TicketMutationRefused extends TicketMutationOutcome {
  const TicketMutationRefused(this.reason);
  final TicketMutationRefusal reason;
}

final class TicketMutationFailed extends TicketMutationOutcome {
  const TicketMutationFailed();
}

final class TicketDetailSession extends ChangeNotifier {
  TicketDetailSession(
    this._gateway,
    this._ticket,
    this._maintainer, {
    this.onAccessRejected,
    DateTime Function()? now,
    TicketTimerFactory? timerFactory,
  }) : _now = now ?? DateTime.now,
       _timerFactory = timerFactory ?? Timer.new;

  final TicketGateway _gateway;
  Ticket _ticket;
  final bool _maintainer;
  final VoidCallback? onAccessRejected;
  final DateTime Function() _now;
  final TicketTimerFactory _timerFactory;
  TicketDetailState _state = const TicketDetailLoading();
  Timer? _reopenExpiry;
  bool _disposed = false;

  TicketDetailState get state => _state;

  Future<void> load() async {
    try {
      final ticket = _maintainer
          ? await _gateway.openForMaintainer(_ticket.id)
          : await _gateway.openForSender(_ticket.id);
      _ticket = ticket;
      final thread = await _gateway.readThread(_ticket.id);
      _replace(TicketDetailLoaded(ticket, thread));
      _scheduleReopenRefresh(ticket);
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
    } on Refused catch (failure) {
      if (failure.refusal case final TicketThreadRefusal reason) {
        return TicketThreadCommandRefused(reason);
      }
      assert(
        false,
        'Unexpected Refusal family: ${failure.refusal.runtimeType}',
      );
      return const TicketThreadCommandFailed();
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

  Future<TicketMutationOutcome> linkToGitHub(GitHubIssueLink issue) =>
      _mutate((ticket) => _gateway.linkToGitHub(ticket.id, issue));

  Future<TicketMutationOutcome> close({
    required TicketState outcome,
    required String reason,
  }) => _mutate(
    (ticket) => _gateway.close(ticket.id, outcome: outcome, reason: reason),
  );

  Future<TicketMutationOutcome> reopen({required String note}) =>
      _mutate((ticket) => _gateway.reopen(ticket.id, note: note));

  Future<TicketMutationOutcome> redactText() =>
      _mutate((ticket) => _gateway.redactText(ticket.id));

  Future<TicketThreadCommandOutcome> redactThreadEntry(String entryId) =>
      _runThreadCommand(() async {
        await _gateway.redactThreadEntry(entryId);
      });

  Future<TicketMutationOutcome> _mutate(
    Future<Ticket> Function(Ticket ticket) action,
  ) async {
    final current = _state;
    if (current is! TicketDetailLoaded || current.working) {
      return const TicketMutationFailed();
    }
    _replace(current.withWorking(true));
    try {
      final ticket = await action(current.ticket);
      _ticket = ticket;
      _replace(TicketDetailLoaded(ticket, current.thread));
      _scheduleReopenRefresh(ticket);
      return const TicketMutationSucceeded();
    } on Refused catch (failure) {
      _replace(current);
      if (failure.refusal case final TicketMutationRefusal reason) {
        return TicketMutationRefused(reason);
      }
      assert(
        false,
        'Unexpected Refusal family: ${failure.refusal.runtimeType}',
      );
      return const TicketMutationFailed();
    } on AccessRejected {
      onAccessRejected?.call();
      _replace(current);
      return const TicketMutationFailed();
    } catch (_) {
      _replace(current);
      return const TicketMutationFailed();
    }
  }

  void _scheduleReopenRefresh(Ticket ticket) {
    _reopenExpiry?.cancel();
    if (_maintainer || !ticket.canReopen || ticket.reopenUntil == null) return;
    final delay = ticket.reopenUntil!.difference(_now().toUtc());
    _reopenExpiry = _timerFactory(
      delay.isNegative
          ? Duration.zero
          : delay + const Duration(milliseconds: 10),
      _refreshReopenVerdict,
    );
  }

  Future<void> _refreshReopenVerdict() async {
    try {
      final ticket = await _gateway.openForSender(_ticket.id);
      _ticket = ticket;
      final current = _state;
      final thread = current is TicketDetailLoaded
          ? current.thread
          : await _gateway.readThread(_ticket.id);
      _replace(TicketDetailLoaded(ticket, thread));
      _scheduleReopenRefresh(ticket);
    } on AccessRejected {
      onAccessRejected?.call();
    } catch (_) {
      // The SQL write path still enforces expiry; refresh again on next open.
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
    _reopenExpiry?.cancel();
    super.dispose();
  }
}
