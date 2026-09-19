import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class AuthGateway {
  bool get isSignedIn;
  Stream<bool> get signedInChanges;
  Future<void> requestCode(String email);
  Future<void> verifyCode({required String email, required String code});
  Future<void> signOut();
}

final class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this._client);

  final SupabaseClient _client;

  @override
  bool get isSignedIn => _client.auth.currentSession != null;

  @override
  Stream<bool> get signedInChanges => _client.auth.onAuthStateChange
      .map((state) => state.session != null)
      .distinct();

  @override
  Future<void> requestCode(String email) {
    return _client.auth.signInWithOtp(email: email, shouldCreateUser: true);
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
  Future<void> signOut() => _client.auth.signOut();
}
