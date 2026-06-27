---
inclusion: always
---

# Zexo — Technology Stack (Enforced)

This steering doc constrains the agent to the approved Zexo stack. Do NOT introduce
alternative frameworks, languages, or services without an explicit instruction to change
the stack. If a task seems to require something outside this list, stop and ask.

## Approved Stack

| Concern | Technology | Notes |
| --- | --- | --- |
| Mobile app | **Flutter 3.x** | Single codebase for iOS + Android. No native-only or React Native code. |
| State management | **Riverpod** | Use Riverpod providers; do not add Bloc, Provider, GetX, or Redux. |
| API server | **FastAPI (Python 3.12)** | Hosted on **Railway**. Async endpoints. |
| Database | **PostgreSQL 16 + PostGIS** | On **Supabase** cloud. SRID 4326 geometry. |
| Auth | **Supabase Auth** | **Google OAuth only** (no phone/OTP). Native Google sign-in → ID token → Supabase. JWT validated server-side. |
| Real-time | **FastAPI WebSockets + Redis pub/sub (Upstash)** | Per-thread channels `thread:{id}`. |
| Storage | **Supabase Storage** | Avatars, event cover images. |
| Maps | **Mapbox GL Flutter SDK** | Clusters, radius rings, drag-to-set geofence. |
| Push | **Firebase Cloud Messaging (FCM)** | Background message notifications only. |
| Location | **flutter_geolocator + background_fetch** | Two-tier GPS/city fallback. |
| CI/CD | **GitHub Actions → Railway** (API) + **Fastlane** (mobile) | |
| Error tracking | **Sentry** | Both Flutter and FastAPI. |

## Hard Rules

1. **No stack substitutions.** Do not swap FastAPI for Flask/Django, Postgres for another
   DB, Mapbox for Google Maps, or Riverpod for another state library.
2. **PostGIS is mandatory** for all geospatial work. Use `ST_DWithin` / `ST_Distance` on
   `geography`; never compute distance in application code when the DB can do it.
3. **Supabase Auth only.** Do not hand-roll auth, password storage, or custom JWT issuance.
   FastAPI validates Supabase-issued JWTs.
4. **Redis (Upstash) is the only real-time fan-out.** Do not introduce Kafka, RabbitMQ, or
   socket.io.
5. **Sentry everywhere.** Both apps initialise Sentry; WS disconnects and unhandled errors
   are reported.
6. **Secrets via environment variables.** Never hardcode keys, DSNs, or connection strings.
   Use pydantic-settings (backend) and `--dart-define` / env config (Flutter).

## Privacy & Data Stack Rules

- Coordinates are fuzzed **±150m server-side** before storage; only `fuzzy_geom` is queried
  or returned. Raw `geom` never leaves the device boundary in a persistable/exportable form.
- **Row-Level Security** is enabled on every Supabase table.
- **pg_cron** handles message purge (hourly) and event archival.

## Versioning

- Pin Flutter to the 3.x line and Python to 3.12. Prefer current stable, well-maintained
  package versions; if unsure of the latest version, verify before adding a dependency.
