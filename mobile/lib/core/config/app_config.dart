/// Application configuration sourced from `--dart-define` values at build time.
///
/// Never hardcode secrets (steering: stack.md). Provide values with, e.g.:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=API_BASE_URL=...
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.wsBaseUrl,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.googleWebClientId,
    required this.mapboxToken,
    required this.sentryDsn,
    required this.environment,
  });

  final String apiBaseUrl;
  final String wsBaseUrl;
  final String supabaseUrl;
  final String supabaseAnonKey;

  /// The Google OAuth **Web** client ID, required by google_sign_in to mint an
  /// ID token that Supabase will accept (`serverClientId`).
  final String googleWebClientId;

  final String mapboxToken;
  final String sentryDsn;
  final String environment;

  bool get isProduction => environment == 'production';

  factory AppConfig.fromEnvironment() {
    const apiBase = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:8000',
    );
    return AppConfig(
      apiBaseUrl: apiBase,
      wsBaseUrl: const String.fromEnvironment(
        'WS_BASE_URL',
        defaultValue: 'ws://localhost:8000',
      ),
      supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
      supabaseAnonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
      googleWebClientId: const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
      mapboxToken: const String.fromEnvironment('MAPBOX_TOKEN'),
      sentryDsn: const String.fromEnvironment('SENTRY_DSN'),
      environment: const String.fromEnvironment(
        'ZEXO_ENV',
        defaultValue: 'development',
      ),
    );
  }
}

/// Product-wide constants that mirror the backend non-functional constraints.
class AppConstants {
  const AppConstants._();

  static const double radiusMinM = 500;
  static const double radiusMaxM = 50000;
  static const double radiusDefaultM = 5000;

  static const int maxUserTags = 10;
  static const int maxEventTags = 5;

  /// Re-fetch the feed once the user has moved more than this many metres.
  static const double feedRefreshDeltaM = 200;

  /// Foreground location poll interval.
  static const Duration pollIntervalForeground = Duration(seconds: 30);

  /// Reduced cadence when the device is detected as stationary.
  static const Duration pollIntervalStationary = Duration(minutes: 5);
}
