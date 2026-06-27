# Zexo — Implementation Plan

Tasks are ordered by build phase and designed for incremental, test-backed execution. Each
task lists the files it touches, an acceptance test, dependencies, and the requirements it
satisfies. Kiro executes these top-to-bottom; hooks validate each change before proceeding.

> Legend — `_Req:_` maps to `requirements.md`. `_Depends:_` lists prerequisite task numbers.

---

## Phase 1 — Scaffold + Auth (Week 1)

- [ ] 1. Initialise Flutter project and folder structure
  - Create the Flutter app with the `core/ features/ shared/` layout from `design.md`.
  - Add dependencies: `flutter_riverpod`, `go_router`, `supabase_flutter`, `sentry_flutter`,
    `geolocator`, `background_fetch`, `mapbox_gl`, `firebase_messaging`.
  - Files: `lib/main.dart`, `lib/core/`, `lib/features/`, `lib/shared/`, `pubspec.yaml`.
  - Test: `flutter analyze` passes; app boots to a placeholder route.
  - _Depends: none_ · _Req: 2_

- [ ] 2. Wire Riverpod and app-wide providers
  - Set up `ProviderScope`, an auth state provider, and a router that gates routes on auth.
  - Files: `lib/main.dart`, `lib/core/providers/`, `lib/core/router.dart`.
  - Test: unauthenticated launch shows onboarding; authenticated launch shows home.
  - _Depends: 1_ · _Req: 1, 2_

- [ ] 3. Initialise Sentry (Flutter)
  - Initialise Sentry in `main()` and wrap `runApp` to capture uncaught errors.
  - Files: `lib/core/telemetry/sentry_init.dart`, `lib/main.dart`.
  - Test: a thrown test error appears as a Sentry event (verified against DSN in dev).
  - _Depends: 1_ · _Req: 19.5_

- [ ] 4. Integrate Supabase Auth — Google OAuth only
  - Implement the native Google sign-in flow (google_sign_in) → exchange the ID token via
    `POST /auth/google`; persist the Supabase session. No phone/OTP.
  - Files: `lib/features/onboarding/data/auth_repository.dart`,
    `lib/features/onboarding/application/onboarding_controller.dart`.
  - Test: a completed Google flow yields a session; cancellation is a no-op; a rejected
    token surfaces an error.
  - _Depends: 2_ · _Req: 1_

- [ ] 5. Build onboarding screens
  - Google sign-in screen, display name, avatar upload to Supabase Storage,
    interest-tag multi-select (max 10), discovery-radius picker (500m–50km, default 5km),
    location-permission explainer dialog.
  - Files: `lib/features/onboarding/*`.
  - Test: tag selection blocks the 11th tag; radius constrained to range; avatar upload
    returns a Storage URL.
  - _Depends: 4_ · _Req: 2_

- [ ] 6. Profile setup persistence
  - Persist profile via `PUT /users/me`; load via `GET /users/me`.
  - Files: `lib/core/api/users_repository.dart`, `lib/features/onboarding/profile_controller.dart`.
  - Test: editing name/bio/tags round-trips through the API.
  - _Depends: 5_ · _Req: 2_

---

## Phase 2 — Location Engine + Backend (Week 1–2)

- [ ] 7. Scaffold FastAPI project for Railway
  - App factory, config (pydantic-settings), async DB pool, Sentry middleware, health route.
  - Files: `app/main.py`, `app/core/config.py`, `app/core/db.py`, `Procfile`/`railway.toml`.
  - Test: `GET /health` returns 200; Sentry captures a forced error.
  - _Depends: none_ · _Req: 19.5_

- [ ] 8. PostGIS + base migration (users, user_locations)
  - Enable PostGIS; create `users` and `user_locations` with GIST index on `fuzzy_geom`.
  - Files: `app/migrations/0001_postgis_users_locations.sql`.
  - Test: migration applies; `\d user_locations` shows the GIST index; PostGIS enabled.
  - _Depends: 7_ · _Req: 3, 18 · validated by `db.hook.kiro`_

- [ ] 9. Remaining migrations (threads, messages, events, rsvps, blocks)
  - Create `chat_threads`, `messages`, `events` (GIST on `geom`), `event_rsvps`
    (enum role/status, unique event/user), and a `blocks` table.
  - Files: `app/migrations/0002_chat.sql`, `0003_events.sql`, `0004_blocks.sql`.
  - Test: all migrations apply; unique and FK constraints enforced.
  - _Depends: 8_ · _Req: 8, 9, 11, 13, 16 · validated by `db.hook.kiro`_

- [ ] 10. RLS policies
  - Enable RLS on every table; add ownership/visibility policies for `users` and
    `user_locations`, and relationship-scoped policies for threads/messages/rsvps.
  - Files: `app/migrations/0005_rls.sql`.
  - Test: a user cannot select another user's `user_locations` row directly.
  - _Depends: 9_ · _Req: 18 · validated by `db.hook.kiro`_

- [ ] 11. JWT auth dependency
  - FastAPI dependency that validates Supabase JWTs and injects the current user.
  - Files: `app/core/security.py`.
  - Test: missing/invalid token → 401; valid token resolves the user.
  - _Depends: 7_ · _Req: 1_

- [ ] 12. Location fuzzing service + PUT /users/location
  - Apply ±150m random-bearing offset server-side; persist `geom` (transient) and
    `fuzzy_geom`; return only fuzzed values.
  - Files: `app/services/location_service.py`, `app/routers/users.py`,
    `app/repositories/locations_repo.py`.
  - Test: stored `fuzzy_geom` differs from input by ~150m; response never contains raw GPS.
  - _Depends: 11, 8_ · _Req: 3 · validated by `location.hook.kiro`_

- [ ] 13. Client location service — two-tier fallback + polling
  - Precise GPS with city-level fallback; foreground polling every 30s; pause when closed.
  - Files: `lib/core/location/location_service.dart`, `lib/core/location/background_poller.dart`.
  - Test: denial path falls back to city; poller emits ~every 30s in foreground.
  - _Depends: 6, 12_ · _Req: 3.4, 4.1, 4.2 · validated by `location.hook.kiro`_

- [ ] 14. Profile/visibility/me endpoints
  - Implement `GET/PUT /users/me`, `PUT /users/visibility`, `GET /users/:id`.
  - Files: `app/routers/users.py`, `app/repositories/users_repo.py`, `app/schemas/users.py`.
  - Test: tag count > 10 → 422; visibility toggle persists.
  - _Depends: 11_ · _Req: 2, 7_

---

## Phase 3 — Discovery Feed + Map (Week 2)

- [ ] 15. Ranking service
  - Implement distance-score × tag-overlap (Jaccard) scoring with configurable weights.
  - Files: `app/services/ranking_service.py`.
  - Test: identical distance but higher tag overlap ranks higher; both factors affect order.
  - _Depends: 12_ · _Req: 5.2 · validated by `feed.hook.kiro`_

- [ ] 16. GET /discover ranked feed
  - `ST_DWithin` candidate query (radius clamped 500m–50km), block + invisibility exclusion,
    ranking applied, cursor-based pagination.
  - Files: `app/routers/discover.py`, `app/repositories/users_repo.py`.
  - Test: results exclude invisible/blocked users; cursor returns the next page without
    overlap; p95 < 200ms on seed data.
  - _Depends: 15, 10_ · _Req: 4.4, 4.5, 5.1, 5.3, 5.7, 16.2, 19.1 · validated by `feed.hook.kiro`_

- [ ] 17. GET /discover/map bounding-box endpoint
  - Return users + events within a bbox using fuzzy coordinates / event geom.
  - Files: `app/routers/discover.py`, `app/repositories/events_repo.py`.
  - Test: entities inside the bbox returned; outside excluded; only fuzzy coords for users.
  - _Depends: 16_ · _Req: 6.3_

- [ ] 18. Discover cards UI
  - Swipe feed sorted by score; card with avatar, name, distance badge, shared-tag chips;
    pull-to-refresh; auto-refresh on >200m move; invisible toggle in top bar.
  - Files: `lib/features/discover/cards/*`, `lib/features/discover/discover_providers.dart`.
  - Test: moving >200m triggers a refresh; invisible toggle calls `PUT /users/visibility`.
  - _Depends: 16, 13_ · _Req: 5.4, 5.5, 5.6, 7_

- [ ] 19. Discover map UI
  - Mapbox GL with fuzzy dot clusters, radius ring overlay, cluster expand, tap-to-peek
    bottom sheet with connect button; smooth card↔map transition.
  - Files: `lib/features/discover/map/*`.
  - Test: tapping a cluster expands dots; tapping a dot opens the peek sheet.
  - _Depends: 17, 18_ · _Req: 6_

---

## Phase 4 — Real-Time Chat (Week 3)

- [ ] 20. Redis pub/sub client (Upstash)
  - Connect to Upstash; helpers to publish/subscribe on `thread:{id}` channels.
  - Files: `app/core/redis.py`.
  - Test: a published message is received by a subscriber on the same channel.
  - _Depends: 7_ · _Req: 8.5_

- [ ] 21. WebSocket connection manager
  - `WS /ws/thread/:id` with auth, per-thread socket registry, Redis bridge, message persist
    with `expires_at = created_at + 24h`, read receipts, heartbeat handler.
  - Files: `app/services/ws_manager.py`, `app/routers/threads.py`, `app/repositories/messages_repo.py`.
  - Test: message round-trips between two sockets; every persisted message has `expires_at`;
    WS disconnect reports to Sentry.
  - _Depends: 20, 11, 9_ · _Req: 8.4, 9.1, 9.4, 19.5 · validated by `chat.hook.kiro`_

- [ ] 22. Range-expiry + force-expire
  - On heartbeat, compare sender coords against peer radius; expire on range exit; implement
    `POST /threads/:id/expire`; emit `thread_expired` with reason.
  - Files: `app/services/expiry_service.py`, `app/routers/threads.py`.
  - Test: a heartbeat outside range expires the thread; force-expire returns reason.
  - _Depends: 21_ · _Req: 9.2, 9.3, 9.7 · validated by `chat.hook.kiro`_

- [ ] 23. pg_cron message purge
  - Schedule a job to delete messages where `expires_at < now()` (runs hourly).
  - Files: `app/migrations/0006_pgcron_purge.sql`.
  - Test: a message past `expires_at` is removed within the job window.
  - _Depends: 9_ · _Req: 9.5, 19.4 · validated by `db.hook.kiro`_

- [ ] 24. Thread/POST + list endpoints
  - `POST /threads` (idempotent), `GET /threads` (sorted by last message, unread counts,
    expiry).
  - Files: `app/routers/threads.py`, `app/repositories/threads_repo.py`.
  - Test: re-opening a thread reuses the existing row.
  - _Depends: 21_ · _Req: 8.1, 8.2_

- [ ] 25. Chat list + thread UI
  - Thread list with expiry countdown chips and unread badges; message bubbles with read
    receipts, TTL banner, fade-on-expiry, out-of-range banner.
  - Files: `lib/features/chat/*`, `lib/core/ws/ws_client.dart`.
  - Test: countdown chip decrements; expired thread shows out-of-range banner.
  - _Depends: 22, 24_ · _Req: 8.3, 9.6_

- [ ] 26. FCM push on backgrounded new message
  - Send FCM when recipient has no active foreground WS on the thread; respect notification
    preference.
  - Files: `app/services/fcm.py`, `lib/core/notifications/fcm_service.dart`.
  - Test: backgrounded recipient receives a push; foregrounded recipient does not.
  - _Depends: 21_ · _Req: 10_

---

## Phase 5 — Events Module (Week 3–4)

- [ ] 27. POST /events with validation
  - Persist geofenced event; enforce ≤5 tags and `starts_at < ends_at`; record creator as
    host RSVP.
  - Files: `app/routers/events.py`, `app/repositories/events_repo.py`, `app/schemas/events.py`.
  - Test: 6 tags → 422; `starts_at >= ends_at` → 422; creator row has role `host`.
  - _Depends: 9, 11_ · _Req: 11_

- [ ] 28. GET /events + detail
  - `ST_DWithin` nearby query (distance-sorted, cursor paginated), tag/date filters, archived
    exclusion; `GET /events/:id` detail.
  - Files: `app/routers/events.py`, `app/repositories/events_repo.py`.
  - Test: archived events excluded; filters applied; pagination stable.
  - _Depends: 27_ · _Req: 12, 15.2_

- [ ] 29. RSVP flow + attendee visibility
  - `POST /events/:id/rsvp` upsert (unique per event/user, capacity rule); `GET /events/:id/attendees`
    full list for host/co-host only.
  - Files: `app/routers/events.py`, `app/repositories/events_repo.py`.
  - Test: second RSVP updates rather than duplicates; non-host gets count/403, host gets list.
  - _Depends: 27_ · _Req: 13_

- [ ] 30. Co-host invite via deep link
  - Generate/accept co-host invite deep link; set role `co-host`.
  - Files: `app/routers/events.py`, `lib/features/events/cohost_*`.
  - Test: accepting an invite sets the role to co-host with host-equivalent visibility.
  - _Depends: 29_ · _Req: 14_

- [ ] 31. Auto-archive cron
  - pg_cron job sets `is_archived = true` for events past `ends_at`.
  - Files: `app/migrations/0007_pgcron_archive.sql`.
  - Test: an event past `ends_at` is archived by the job.
  - _Depends: 9_ · _Req: 15.1 · validated by `db.hook.kiro`_

- [ ] 32. Events UI — list, map, detail, create
  - Events list (distance-sorted, tag/date filters), map with pins, detail (mini-map, RSVP
    selector, attendee count, co-host badge, share), create form with Mapbox drag-to-set
    radius and date-time pickers.
  - Files: `lib/features/events/*`.
  - Test: creating an event round-trips; RSVP selector updates status inline.
  - _Depends: 28, 29, 30_ · _Req: 11, 12, 13, 14_

- [ ] 33. PUT /events/:id host-only edit
  - Allow updates only by host/co-host; else 403.
  - Files: `app/routers/events.py`.
  - Test: non-host edit → 403; host edit persists.
  - _Depends: 27_ · _Req: 15.3_

---

## Phase 6 — Safety, Polish + Launch (Week 4–5)

- [ ] 34. Block/report + feed exclusion
  - `POST /users/:id/block` with optional report; bidirectional exclusion across feed, map,
    and attendee queries; forward report to moderation webhook stub.
  - Files: `app/routers/users.py`, `app/services/moderation.py`, `app/repositories/users_repo.py`.
  - Test: blocked users disappear from each other's `/discover` and `/discover/map`.
  - _Depends: 16, 9_ · _Req: 16_

- [ ] 35. Block-list management UI + settings
  - Settings: radius slider (500m–50km), visibility toggle, edit tags, notification prefs,
    block-list management, account (logout, delete), privacy policy link.
  - Files: `lib/features/settings/*`.
  - Test: removing a block re-includes the user; radius slider clamps to range.
  - _Depends: 34_ · _Req: 7, 16.4_

- [ ] 36. GDPR account deletion
  - Deletion endpoint that purges PII and location history within 24h via cascade + job;
    invalidate credentials.
  - Files: `app/routers/users.py`, `app/migrations/0008_deletion_job.sql`.
  - Test: after deletion, user rows and dependent locations/messages/RSVPs are gone.
  - _Depends: 10_ · _Req: 17_

- [ ] 37. Battery-optimised stationary polling
  - Reduce polling to 5min when the accelerometer detects no movement.
  - Files: `lib/core/location/background_poller.dart`.
  - Test: simulated stationary state lengthens the poll interval to 5min.
  - _Depends: 13_ · _Req: 4.3_

- [ ] 38. Polish — animations, empty states, privacy policy screen
  - Onboarding animation, empty-state illustrations (chat list, discover, events), privacy
    policy screen.
  - Files: `lib/features/**`, `lib/shared/widgets/*`.
  - Test: empty discover/chat/events show illustrated states.
  - _Depends: 35_ · _Req: 2_

- [ ] 39. CI/CD + release config
  - GitHub Actions → Railway (API deploy) and Fastlane (mobile); App/Play Store metadata and
    screenshots; production env vars; TestFlight + internal track build.
  - Files: `.github/workflows/*`, `fastlane/*`, store metadata.
  - Test: CI runs lint + tests; a build artifact is produced.
  - _Depends: all prior_ · _Req: 19_

- [ ] 40. Full regression pass
  - Run all unit/integration/realtime/privacy/performance tests; confirm `/discover` p95
    < 200ms and no `geom` leakage.
  - Files: test suites across `app/tests/` and `test/`.
  - Test: full suite green; privacy and performance assertions pass.
  - _Depends: 39_ · _Req: 19_
