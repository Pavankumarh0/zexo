import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../config/app_config.dart';

/// Initialises Sentry (if a DSN is configured) and runs the app inside its zone.
/// When no DSN is set (e.g. local dev) the app simply runs without telemetry.
Future<void> initTelemetryAndRun(
  AppConfig config,
  Widget Function() appBuilder,
) async {
  if (config.sentryDsn.isEmpty) {
    runApp(appBuilder());
    return;
  }

  await SentryFlutter.init(
    (options) {
      options.dsn = config.sentryDsn;
      options.environment = config.environment;
      options.tracesSampleRate = config.isProduction ? 0.1 : 1.0;
    },
    appRunner: () => runApp(appBuilder()),
  );
}
