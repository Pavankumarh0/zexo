import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';

/// Wraps Supabase Auth flows (phone OTP + Google). We never issue our own tokens
/// or store passwords (steering: stack.md — Supabase Auth only).
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  /// Send a one-time passcode to the given phone number.
  Future<void> requestOtp(String phone) {
    return _client.auth.signInWithOtp(phone: phone);
  }

  /// Verify the SMS OTP and establish a session.
  Future<AuthResponse> verifyOtp({
    required String phone,
    required String token,
  }) {
    return _client.auth.verifyOTP(
      type: OtpType.sms,
      phone: phone,
      token: token,
    );
  }

  /// Sign in with a Google ID token obtained from the native Google flow.
  Future<AuthResponse> signInWithGoogle({
    required String idToken,
    String? accessToken,
  }) {
    return _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
  }

  Future<void> signOut() => _client.auth.signOut();
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseProvider));
});
