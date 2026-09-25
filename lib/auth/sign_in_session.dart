import 'package:flutter/foundation.dart';

import 'auth_gateway.dart';
import 'sign_in_failure_log.dart';

final class SignInSessionState {
  const SignInSessionState({this.codeRequested = false, this.busy = false});

  final bool codeRequested;
  final bool busy;

  SignInSessionState copyWith({bool? codeRequested, bool? busy}) =>
      SignInSessionState(
        codeRequested: codeRequested ?? this.codeRequested,
        busy: busy ?? this.busy,
      );
}

sealed class RequestCodeOutcome {
  const RequestCodeOutcome();
}

final class SignInCodeSent extends RequestCodeOutcome {
  const SignInCodeSent();
}

final class SignInEmailInvalid extends RequestCodeOutcome {
  const SignInEmailInvalid();
}

final class SignInCodeNotSent extends RequestCodeOutcome {
  const SignInCodeNotSent();
}

sealed class VerifyCodeOutcome {
  const VerifyCodeOutcome();
}

final class SignInCodeVerified extends VerifyCodeOutcome {
  const SignInCodeVerified();
}

final class SignInCodeInvalid extends VerifyCodeOutcome {
  const SignInCodeInvalid();
}

final class SignInSession extends ChangeNotifier {
  SignInSession(this._authGateway, this._failureLog);

  final AuthGateway _authGateway;
  final SignInFailureLog _failureLog;
  SignInSessionState _state = const SignInSessionState();
  bool _disposed = false;

  SignInSessionState get state => _state;

  void _replace(SignInSessionState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<RequestCodeOutcome> requestCode(String email) async {
    _replace(_state.copyWith(busy: true));
    try {
      await _authGateway.requestCode(email);
      _replace(_state.copyWith(codeRequested: true));
      return const SignInCodeSent();
    } on InvalidEmailAddress {
      return const SignInEmailInvalid();
    } catch (error, stackTrace) {
      await _failureLog.record(error, stackTrace);
      return const SignInCodeNotSent();
    } finally {
      _replace(_state.copyWith(busy: false));
    }
  }

  Future<VerifyCodeOutcome> verifyCode({
    required String email,
    required String code,
  }) async {
    _replace(_state.copyWith(busy: true));
    try {
      await _authGateway.verifyCode(email: email, code: code);
      return const SignInCodeVerified();
    } catch (_) {
      return const SignInCodeInvalid();
    } finally {
      _replace(_state.copyWith(busy: false));
    }
  }
}
