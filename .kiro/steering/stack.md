---
inclusion: always
---

# Zexo — Technology Stack (Enforced)

This steering doc constrains the agent to the approved Zexo stack. Do NOT introduce
alternative frameworks, languages, or services without an explicit instruction to change
the stack. If a task seems to require something outside this list, stop and ask.

> **Backend = Firebase.** The original FastAPI + PostgreSQL/PostGIS + Supabase backend in
> `backend/` is **deprecated** and kept for reference only. New backend work happens in
> `functions/` (Cloud Functions) with Firestore.

## Approved Stack

| Concern | Technology | Notes |
| --- | --- | --- |
| Mobile app | **Flutter 3.x** | Single codebase for iOS + Android. No native-only or React Native code. |
| State management | **Riverpod** | Use Riverpod providers; do not add Bloc, Provider, GetX, or Redux. |
| Backend / API | **Firebase Cloud Functions (TypeScript, 2nd gen)** | HTTPS **callable** functions + Firestore/Auth/scheduled triggers. |
| Database | **Cloud Firestore** | NoSQL. Proximity via **geohash** (`geofire-common`) — Firestore has no native geo query. |
| Auth | **Firebase Auth** | **Google sign-in only** (no phone/OTP). Native Google flow → Firebase ID token; callables read `request.auth`. |
| Real-time | **Firestore real-time listeners** | Chat messages stream from `threads/{id}/messages`. No WebSocket/Redis. |
| Storage | **Firebase Cloud Storage** | Avatars, event cover images. |
| Maps | **Mapbox GL Flutter SDK** | Clusters, radius rings, drag-to-set geofence. |
| Push | **Firebase Cloud Messaging (FCM)** | Background message notifications. |
| Location | **flutter_geolocator + background_fetch** | Two-tier GPS/city fallback. |
| Scheduled jobs | **Scheduled Cloud Functions** | Message TTL purge + event archival (replaces pg_cron). |
| Access control | **Firestore Security Rules** | Replaces Postgres RLS. |
| CI/CD | **GitHub Actions** → `firebase deploy` (backend) + **Fastlane** (mobile) | |
| Error tracking | **Sentry** | Flutter client; Cloud Functions log to Cloud Logging. |

## Hard Rules

1. **No stack substitutions.** Do not swap Firestore for another DB, Cloud Functions for a
   custom server, Mapbox for Google Maps, or Riverpod for another state library.
2. **No native geo query exists in Firestore** — all proximity work uses **geohash range
   queries** (`geofire-common`) plus an exact haversine filter in function code. Never
   store or query against raw GPS.
3. **Firebase Auth only.** Do not hand-roll auth or custom JWT issuance. Callable functions
   trust `request.auth`; HTTP functions verify the Firebase ID token.
4. **Firestore listeners are the only real-time mechanism.** Do not introduce WebSockets,
   Redis, Kafka, RabbitMQ, or socket.io.
5. **Functions in TypeScript.** 2nd-gen functions; keep callables thin and put logic in
   `functions/src/lib`.
6. **Secrets via environment / Firebase config.** Never hardcode keys. Use
   `--dart-define` / env config (Flutter) and Firebase params/secrets (functions).

## Privacy & Data Stack Rules

- Coordinates are fuzzed **±150m server-side** in `updateLocation` before any write; only
  the fuzzed point (and its geohash) is stored in `userLocations`, and that collection is
  **functions-only** — clients can never read it. Discovery returns only fuzzed coordinates.
- **Firestore Security Rules** protect every collection; `userLocations` and `blocks` are
  locked to functions; chat `messages` are writable only by thread participants.
- **Scheduled Cloud Functions** handle message purge (hourly) and event archival (15 min).

## Versioning

- Pin Flutter to the 3.x line and Cloud Functions to the Node 20 runtime / TypeScript 5.x.
  Prefer current stable, well-maintained package versions; if unsure of the latest version,
  verify before adding a dependency.
