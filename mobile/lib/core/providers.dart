import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api/api_client.dart';
import 'config/app_config.dart';

/// App configuration (overridden in [main] with the environment-built instance).
final appConfigProvider = Provider<AppConfig>((ref) {
  throw UnimplementedError('appConfigProvider must be overridden in main()');
});

/// The Supabase client singleton.
final supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Streams Supabase auth state so the router and UI react to sign-in/out.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseProvider).auth.onAuthStateChange;
});

/// True when a session exists.
final isAuthenticatedProvider = Provider<bool>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentSession != null;
});

/// The shared API client. Reads the current JWT lazily on each request.
final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  final supabase = ref.watch(supabaseProvider);
  return ApiClient(
    config: config,
    tokenProvider: () => supabase.auth.currentSession?.accessToken,
  );
});
