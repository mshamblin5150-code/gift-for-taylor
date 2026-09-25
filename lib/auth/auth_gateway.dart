import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class AuthGateway {
  bool get isSignedIn;
  String? get currentUserId;
  Stream<bool> get signedInChanges;
  Future<void> requestCode(String email);
  Future<void> verifyCode({required String email, required String code});
  Future<void> signOut();
}

sealed class RequestCodeFailure implements Exception {
  const RequestCodeFailure(this.cause);

  final Object cause;

  @override
  String toString() => '$runtimeType: $cause';
}

final class InvalidEmailAddress extends RequestCodeFailure {
  const InvalidEmailAddress(super.cause);
}

final class SignInCodeDeliveryFailed extends RequestCodeFailure {
  const SignInCodeDeliveryFailed(super.cause);
}

final class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this._client, {this.onSignedOut});

  final SupabaseClient _client;
  final void Function()? onSignedOut;

  @override
  bool get isSignedIn => _client.auth.currentSession != null;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Stream<bool> get signedInChanges => _client.auth.onAuthStateChange
      .map((state) => state.session != null)
      .distinct();

  @override
  Future<void> requestCode(String email) async {
    try {
      await _client.auth.signInWithOtp(email: email, shouldCreateUser: true);
    } on AuthException catch (error, stackTrace) {
      final failure = error.code == 'email_address_invalid'
          ? InvalidEmailAddress(error)
          : SignInCodeDeliveryFailed(error);
      Error.throwWithStackTrace(failure, stackTrace);
    }
  }

  @override
  Future<void> verifyCode({required String email, required String code}) async {
    await _client.auth.verifyOTP(
      email: email,
      token: code,
      type: OtpType.email,
    );
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
    onSignedOut?.call();
  }
}
