import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/providers.dart';

/// Wraps Supabase Auth with **Google OAuth only** (steering: stack.md). No phone
/// OTP and no password storage. The native Google flow yields an ID token which
/// is exchanged for a Supabase session.
class AuthRepository {
  AuthRepository(this._client, this._googleWebClientId);

  final SupabaseClient _client;
  final String _googleWebClientId;

  /// Runs the native Google sign-in and establishes a Supabase session.
  ///
  /// Returns the [AuthResponse] on success, or `null` if the user cancelled.
  Future<AuthResponse?> signInWithGoogle() async {
    final googleSignIn = GoogleSignIn(
      // serverClientId must be the Google OAuth *Web* client ID so the ID token
      // is minted with an audience Supabase accepts.
      serverClientId: _googleWebClientId.isEmpty ? null : _googleWebClientId,
      scopes: const ['email', 'profile'],
    );

    final account = await googleSignIn.signIn();
    if (account == null) return null; // user cancelled

    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) {
      throw AuthException('Google did not return an ID token.');
    }

    return _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: auth.accessToken,
    );
  }

  Future<void> signOut() async {
    // Sign out of both Google and Supabase so the next sign-in is clean.
    try {
      await GoogleSignIn().signOut();
    } catch (_) {
      // ignore: best-effort
    }
    await _client.auth.signOut();
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  return AuthRepository(ref.watch(supabaseProvider), config.googleWebClientId);
});
