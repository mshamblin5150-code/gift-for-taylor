import 'package:flutter/foundation.dart';

import 'sign_in_failure_log.dart';

sealed class SignInFailuresState {
  const SignInFailuresState();
}

final class SignInFailuresLoading extends SignInFailuresState {
  const SignInFailuresLoading();
}

final class SignInFailuresLoaded extends SignInFailuresState {
  SignInFailuresLoaded(List<SignInFailureRecord> failures)
    : failures = List.unmodifiable(failures);

  final List<SignInFailureRecord> failures;
}

final class SignInFailuresFailed extends SignInFailuresState {
  const SignInFailuresFailed();
}

final class SignInFailuresSession extends ChangeNotifier {
  SignInFailuresSession(this._log);

  final SignInFailureLog _log;
  SignInFailuresState _state = const SignInFailuresLoading();
  bool _disposed = false;

  SignInFailuresState get state => _state;

  Future<void> load() async {
    try {
      _replace(SignInFailuresLoaded(await _log.read()));
    } catch (_) {
      _replace(const SignInFailuresFailed());
    }
  }

  void _replace(SignInFailuresState state) {
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
