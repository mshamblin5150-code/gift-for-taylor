import 'auth_gateway.dart';
import 'sign_in_failure_log.dart';

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

final class SignInSession {
  const SignInSession(this._authGateway, this._failureLog);

  final AuthGateway _authGateway;
  final SignInFailureLog _failureLog;

  Future<RequestCodeOutcome> requestCode(String email) async {
    try {
      await _authGateway.requestCode(email);
      return const SignInCodeSent();
    } on InvalidEmailAddress {
      return const SignInEmailInvalid();
    } catch (error, stackTrace) {
      await _failureLog.record(error, stackTrace);
      return const SignInCodeNotSent();
    }
  }

  Future<VerifyCodeOutcome> verifyCode({
    required String email,
    required String code,
  }) async {
    try {
      await _authGateway.verifyCode(email: email, code: code);
      return const SignInCodeVerified();
    } catch (_) {
      return const SignInCodeInvalid();
    }
  }
}
