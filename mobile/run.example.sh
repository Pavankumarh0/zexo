#!/usr/bin/env bash
# Template for local runs. Copy to run-dev.sh (git-ignored) and fill in values.
#   cp run.example.sh run-dev.sh && $EDITOR run-dev.sh && bash run-dev.sh
set -euo pipefail

flutter run \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<supabase-anon-key> \
  --dart-define=API_BASE_URL=http://10.0.2.2:8000 \
  --dart-define=WS_BASE_URL=ws://10.0.2.2:8000 \
  --dart-define=GOOGLE_WEB_CLIENT_ID=<google-oauth-web-client-id> \
  --dart-define=MAPBOX_TOKEN=<optional-mapbox-token> \
  --dart-define=SENTRY_DSN=<optional-sentry-dsn>

# API_BASE_URL host tips:
#   Android emulator -> http://10.0.2.2:8000
#   iOS simulator    -> http://localhost:8000
#   Physical device  -> http://<your-LAN-IP>:8000
