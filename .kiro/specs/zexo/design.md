# Zexo — Design

## Overview

Zexo is a proximity-first social discovery platform. The system comprises a Flutter mobile
client (iOS + Android), a FastAPI backend hosted on Railway, a PostgreSQL 16 + PostGIS
database on Supabase, Redis pub/sub on Upstash for real-time fan-out, and supporting
services (Supabase Auth, Supabase Storage, Mapbox, FCM, Sentry).

The defining design constraints are: **(1)** raw GPS never leaves the device boundary in a
persistable form — the server fuzzes coordinates ±150m before storage and only `fuzzy_geom`
is ever queried or exposed; **(2)** chat is ephemeral with a dual-expiry model (24h TTL OR
range exit); **(3)** discovery ranking blends distance with interest-tag overlap; and
**(4)** every table is protected by Row-Level Security.

This design satisfies the requirements in `requirements.md`. Each major section references
the requirement IDs it fulfils.

## Architecture

### System Context

```
                         ┌────────────────────────────┐
                         │      Flutter Client         │
                         │  (Riverpod, Mapbox GL,      │
                         │   geolocator, background_   │
                         │   fetch, FCM SDK, Sentry)   │
                         └───────────┬────────────────┘
                                     │ HTTPS (REST) + WSS
                                     ▼
        ┌────────────────────────────────────────────────────────┐
        │                  FastAPI (Railway)                       │
        │  Routers: auth, users, discover, threads, events         │
        │  Services: location-fuzzing, ranking, ws-manager         │
        │  Sentry middleware · JWT auth dependency                 │
        └───┬───────────────┬──────────────────┬──────────────────┘
            │               │                  │
            ▼               ▼                  ▼
   ┌─────────────────┐ ┌───────────┐   ┌────────────────┐
   │ Supabase        │ │ Upstash   │   │ Supabase Auth  │
   │ Postgres+PostGIS│ │ Redis     │   │ Supabase Store │
   │ RLS · pg_cron   │ │ pub/sub   │   │ FCM · Mapbox   │
   └─────────────────┘ └───────────┘   └────────────────┘
```

### Layered Responsibilities

| Layer | Responsibility |
| --- | --- |
| Flutter UI (features/) | Screens, widgets, navigation |
| Riverpod providers | Client state, async data, caching |
| Client services (core/) | Location capture, API client, WS client, FCM, Sentry |
| FastAPI routers | HTTP/WS endpoint definitions, request validation |
| FastAPI services | Business logic: fuzzing, ranking, expiry, ws-manager |
| Repositories | Parametrised SQL / PostGIS access |
| Postgres + PostGIS | Persistence, geospatial queries, RLS, cron jobs |
| Redis | Per-thread pub/sub channels for WS fan-out |

### Network Flow Summary

- **REST**: client → FastAPI → repository → Postgres. JWT validated per request.
- **Real-time chat**: client ⇄ `WS /ws/thread/:id` ⇄ ws-manager ⇄ Redis pub/sub ⇄ other
  client sessions. Persistence to `messages` happens on the publish path.
- **Location**: client polls every 30s (foreground) → `PUT /users/location` → fuzz service
  → `user_locations`.

---

## Components and Interfaces

### Backend modules (FastAPI)

```
app/
  main.py                # app factory, Sentry init, router registration
  core/
    config.py            # env settings (pydantic-settings)
    security.py          # JWT validation dependency
    db.py                # async pool / session
    redis.py             # Upstash client
  routers/
    auth.py
    users.py
    discover.py
    threads.py
    events.py
  services/
    location_service.py  # ±150m fuzzing, ST_DWithin helpers
    ranking_service.py   # distance × tag-overlap scoring
    ws_manager.py        # connection registry, Redis bridge, heartbeat
    expiry_service.py    # TTL + range-exit logic
    moderation.py        # block exclusion, report webhook stub
  repositories/
    users_repo.py
    locations_repo.py
    threads_repo.py
    messages_repo.py
    events_repo.py
  schemas/               # pydantic request/response models
  migrations/            # SQL migrations (PostGIS, tables, indexes, RLS, cron)
```

### Client modules (Flutter)

```
lib/
  main.dart
  core/
    api/api_client.dart
    ws/ws_client.dart
    location/location_service.dart      # two-tier GPS/city fallback, polling
    location/background_poller.dart      # background_fetch, stationary opt
    notifications/fcm_service.dart
    telemetry/sentry_init.dart
  features/
    onboarding/
    discover/      # cards + map
    chat/          # thread list + thread
    events/        # list, detail, create
    settings/
  shared/
    widgets/  models/  theme/
```

---

## Data Models

All tables use UUID primary keys and `timestamptz`. PostGIS geometry columns use SRID 4326
(WGS84). RLS is enabled on every table. *(Requirements 3, 18)*

### users *(Req 1, 2, 7)*

| Column | Type | Notes |
| --- | --- | --- |
| id | uuid PK | |
| phone | text UNIQUE | |
| email | text UNIQUE | |
| display_name | text | |
| bio | text | |
| avatar_url | text | Supabase Storage URL |
| interest_tags | text[] | max 10 enforced at API |
| is_visible | boolean | DEFAULT true |
| last_seen_at | timestamptz | |
| created_at | timestamptz | DEFAULT now() |

### user_locations *(Req 3, 4)*

| Column | Type | Notes |
| --- | --- | --- |
| id | uuid PK | |
| user_id | uuid FK → users(id) | ON DELETE CASCADE |
| geom | geometry(Point,4326) | raw GPS — NOT exposed/exported |
| fuzzy_geom | geometry(Point,4326) | ±150m offset; used for ALL queries |
| accuracy_m | float | |
| updated_at | timestamptz | DEFAULT now() |

`CREATE INDEX ON user_locations USING GIST(fuzzy_geom);`

### chat_threads *(Req 8, 9)*

| Column | Type | Notes |
| --- | --- | --- |
| id | uuid PK | |
| user_a | uuid FK → users(id) | |
| user_b | uuid FK → users(id) | |
| expires_at | timestamptz | set on range exit |
| last_message_at | timestamptz | |
| created_at | timestamptz | DEFAULT now() |

### messages *(Req 9)*

| Column | Type | Notes |
| --- | --- | --- |
| id | uuid PK | |
| thread_id | uuid FK → chat_threads(id) | ON DELETE CASCADE |
| sender_id | uuid FK → users(id) | |
| body | text NOT NULL | |
| read_at | timestamptz | NULL if unread |
| expires_at | timestamptz | 24h from created_at |
| created_at | timestamptz | DEFAULT now() |

### events *(Req 11, 12, 15)*

| Column | Type | Notes |
| --- | --- | --- |
| id | uuid PK | |
| creator_id | uuid FK → users(id) | |
| title | text NOT NULL | |
| description | text | |
| geom | geometry(Point,4326) | |
| radius_m | float | DEFAULT 500 |
| capacity | int | |
| tags | text[] | max 5 enforced at API |
| starts_at | timestamptz NOT NULL | |
| ends_at | timestamptz NOT NULL | |
| is_archived | boolean | DEFAULT false |
| created_at | timestamptz | DEFAULT now() |

`CREATE INDEX ON events USING GIST(geom);`

### event_rsvps *(Req 13, 14)*

| Column | Type | Notes |
| --- | --- | --- |
| id | uuid PK | |
| event_id | uuid FK → events(id) | ON DELETE CASCADE |
| user_id | uuid FK → users(id) | |
| role | enum('host','co-host','guest') | |
| status | enum('going','maybe','no') | |
| created_at | timestamptz | DEFAULT now() |

`UNIQUE(event_id, user_id)`

### Entity Relationships

```
users 1───* user_locations
users 1───* chat_threads (as user_a / user_b)
chat_threads 1───* messages
users 1───* events (creator)
events 1───* event_rsvps *───1 users
```

---

## API Contracts

All protected endpoints require `Authorization: Bearer <jwt>`. Errors use a consistent
envelope: `{ "error": { "code": string, "message": string } }`.

### Auth *(Req 1)*

**POST /auth/verify-otp**
```jsonc
// req
{ "phone": "+14155550123", "otp": "123456" }
// res 200
{ "jwt": "<token>", "user": { "id": "uuid", "display_name": null, "is_new": true } }
```

**POST /auth/google**
```jsonc
// req
{ "id_token": "<google-id-token>" }
// res 200
{ "jwt": "<token>", "user": { "id": "uuid", "is_new": false } }
```

### Users *(Req 2, 3, 7)*

**GET /users/me** → `200 UserProfile`
```jsonc
{ "id":"uuid","display_name":"Mara","bio":"…","avatar_url":"https://…",
  "interest_tags":["climbing","jazz"],"is_visible":true,"radius_m":5000 }
```

**PUT /users/me**
```jsonc
// req (partial allowed)
{ "display_name":"Mara","bio":"…","interest_tags":["climbing","jazz"],"avatar_url":"https://…" }
// res 200 UserProfile  — 422 if interest_tags length > 10
```

**PUT /users/location** *(called every 30s)*
```jsonc
// req — raw client coordinates
{ "lat": 37.7749, "lng": -122.4194, "accuracy_m": 12.5, "source": "gps" }  // source: gps|city
// res 200 — only fuzzed values are ever echoed back
{ "updated_at":"2026-06-27T12:00:00Z","fuzzy_lat":37.7761,"fuzzy_lng":-122.4181 }
```

**PUT /users/visibility**
```jsonc
{ "is_visible": false }      // res 200 { "is_visible": false }
```

### Discovery *(Req 5, 6)*

**GET /discover?lat&lng&radius&tags&cursor&limit**
```jsonc
// res 200
{ "items":[
    { "user":{ "id":"uuid","display_name":"Ivy","avatar_url":"…",
               "interest_tags":["jazz","film"] },
      "distance_m": 320, "shared_tags":["jazz"], "score": 0.87 }
  ],
  "next_cursor": "eyJzIjowLjg3LCJpZCI6Ii4uLiJ9" }
```
- `radius` clamped to [500, 50000]; default 5000. *(Req 4.5, 19.2)*
- ranking: see Ranking Algorithm below. *(Req 5.2)*
- excludes invisible/blocked users. *(Req 5.7, 16.2)*

**GET /discover/map?bbox=minLng,minLat,maxLng,maxLat**
```jsonc
{ "users":[ { "id":"uuid","fuzzy_lat":37.77,"fuzzy_lng":-122.41 } ],
  "events":[ { "id":"uuid","lat":37.78,"lng":-122.40,"title":"Rooftop jam" } ] }
```

**GET /users/:id** → public `UserProfile` subset (no location, no contact fields).

### Threads & Chat *(Req 8, 9)*

**POST /threads** `{ "peer_id":"uuid" }` → `201 { "thread_id":"uuid","created":true }`
(idempotent reuse of existing thread).

**GET /threads** →
```jsonc
{ "items":[
  { "id":"uuid","peer":{ "id":"uuid","display_name":"Ivy","avatar_url":"…" },
    "last_message_at":"…","unread_count":2,"expires_at":"2026-06-28T12:00:00Z" } ] }
```

**WS /ws/thread/:id** — bidirectional frames:
```jsonc
// client → server
{ "type":"message","body":"hey!" }
{ "type":"read","up_to_message_id":"uuid" }
{ "type":"heartbeat","lat":37.77,"lng":-122.41 }
// server → client
{ "type":"message","id":"uuid","sender_id":"uuid","body":"hey!",
  "created_at":"…","expires_at":"…" }
{ "type":"read_receipt","message_id":"uuid","read_at":"…" }
{ "type":"thread_expired","reason":"range_exit|ttl" }
```

**POST /threads/:id/expire** → `200 { "expired": true, "reason":"range_exit" }`

### Events *(Req 11–15)*

**POST /events**
```jsonc
// req
{ "title":"Rooftop jam","description":"…","lat":37.78,"lng":-122.40,
  "radius_m":500,"capacity":40,"tags":["jazz","film"],
  "starts_at":"2026-06-28T19:00:00Z","ends_at":"2026-06-28T22:00:00Z",
  "visibility":"public" }
// res 201 EventDetail   — 422 if tags > 5 or starts_at >= ends_at
```

**GET /events?lat&lng&radius&tags&date&cursor** → paginated event cards (distance-sorted).

**GET /events/:id** → `EventDetail` incl. `attendee_count`; full attendee list only for
host/co-host.

**PUT /events/:id** → host/co-host only, else `403`.

**POST /events/:id/rsvp** `{ "status":"going|maybe|no" }` → upsert RSVP `200`.

**GET /events/:id/attendees** → host/co-host: full list; others: count or `403`.

### Safety *(Req 16)*

**POST /users/:id/block** `{ "report": true, "reason":"harassment" }` →
`200 { "blocked": true }`. Forwards report to moderation webhook stub.

---

## Ranking Algorithm *(Req 5.1, 5.2)*

The discovery feed score blends a normalised distance score with interest-tag overlap so
that **both** factors materially affect ordering.

```
distance_score = 1 - (distance_m / radius_m)            # 0..1, nearer = higher
tag_overlap    = |shared_tags| / max(1, |user_tags ∪ candidate_tags|)   # Jaccard, 0..1
score = (W_DISTANCE * distance_score) + (W_TAG * tag_overlap)
        # default weights: W_DISTANCE = 0.6, W_TAG = 0.4
```

- Candidates outside `radius_m` are filtered by `ST_DWithin` before scoring.
- Results are ordered by `score DESC, distance_m ASC`.
- **Cursor pagination** encodes `(score, id)` of the last item; the next page selects rows
  ordered after that tuple. *(Req 5.3)*
- Exclusion filter removes invisible users and any user in a block relationship with the
  requester *before* scoring. *(Req 5.7, 16.2)*

### PostGIS query shape

```sql
SELECT u.id, u.display_name, u.avatar_url, u.interest_tags,
       ST_Distance(l.fuzzy_geom::geography, :origin::geography) AS distance_m
FROM users u
JOIN user_locations l ON l.user_id = u.id
WHERE u.is_visible = true
  AND u.id <> :me
  AND NOT EXISTS (SELECT 1 FROM blocks b
                  WHERE (b.blocker = :me AND b.blocked = u.id)
                     OR (b.blocker = u.id AND b.blocked = :me))
  AND ST_DWithin(l.fuzzy_geom::geography, :origin::geography, :radius_m)
ORDER BY distance_m ASC;   -- final score sort applied in service layer
```

The `ST_DWithin` predicate uses the GIST index on `fuzzy_geom`. *(Req 3.6, 18.4)*

---

## Location Fuzzing Pipeline *(Req 3)*

```
client raw (lat,lng) ──PUT /users/location──▶ location_service.fuzz()
   │                                              │
   │                                   apply random bearing θ∈[0,2π)
   │                                   and offset d≈150m (±jitter)
   ▼                                              ▼
[discarded after fuzzing]                fuzzy_geom = project(raw, θ, d)
                                                  │
                                                  ▼
                              INSERT geom(raw, transient), fuzzy_geom(persisted)
                              — only fuzzy_geom is read by any query/response
```

Rule enforced by `location.hook.kiro`: no code path may return or export `geom`; all
discovery reads use `fuzzy_geom`. *(Req 3.2, 3.3)*

---

## State Machines

### Location source (two-tier fallback) *(Req 3.4, 4)*

```
        permission granted + fix
  ┌──────────────────────────────────┐
  ▼                                   │
PRECISE_GPS ──fix lost / denied──▶ CITY_FALLBACK
  ▲                                   │
  └────────── precise fix regained ───┘

Polling cadence:
  FOREGROUND + MOVING    → 30s
  FOREGROUND + STATIONARY→ 5min   (accelerometer, Req 4.3)
  BACKGROUND/CLOSED      → paused  (Req 4.2)
```

### Chat thread lifecycle *(Req 8, 9)*

```
        POST /threads
            │
            ▼
        ┌────────┐  message sent / received   ┌────────┐
        │ ACTIVE │ ─────────────────────────▶ │ ACTIVE │
        └───┬────┘                             └───┬────┘
            │ range exit (heartbeat) OR              │ 24h TTL on oldest msg
            │ POST /threads/:id/expire               │
            ▼                                         ▼
        ┌──────────┐  pg_cron purge (≤1h)      ┌──────────┐
        │ EXPIRED  │ ────────────────────────▶ │ PURGED   │
        └──────────┘                            └──────────┘
```

`expires_at` on a message = `created_at + 24h`. A thread expires immediately on range exit;
expiry reason is surfaced to the client (`ttl` | `range_exit`). *(Req 9.1, 9.2, 9.5)*

### Message read state *(Req 9.4)*

```
UNREAD (read_at = NULL) ──recipient opens / WS "read" frame──▶ READ (read_at set)
                                                                  │ emits read_receipt
```

### Event lifecycle *(Req 11, 15)*

```
DRAFT ─POST /events─▶ PUBLISHED ─starts_at─▶ LIVE ─ends_at─▶ (cron) ARCHIVED
                          │                                       │
                          └────── PUT /events/:id (host/co-host) ─┘
```

---

## Real-Time & Expiry Infrastructure

- **ws_manager** maintains an in-process registry of `{thread_id: set[WebSocket]}` and
  subscribes each thread to a Redis channel `thread:{id}`. On publish, the message is
  persisted to `messages` then fanned out via Redis to all subscribed app instances.
  *(Req 8.4, 8.5)*
- **Heartbeat** frames carry the sender's current coordinates; ws_manager calls
  `expiry_service.check_range()` to compare against the peer's discovery radius and triggers
  immediate expiry on range exit. *(Req 9.2, 9.7)*
- **pg_cron** runs a purge job that deletes messages where `expires_at < now()` and an
  archival job that flips `is_archived` for events past `ends_at`. *(Req 9.5, 15.1)*
- **FCM**: on message persist, if the recipient has no active foreground WS on the thread,
  send a push. *(Req 10)*

---

## Cross-Cutting Concerns

| Concern | Approach | Requirements |
| --- | --- | --- |
| Auth | Supabase Auth issues JWT; FastAPI dependency validates per request | 1 |
| RLS | Enabled on all tables; policies for `users`, `user_locations` ownership/visibility | 18 |
| Privacy | ±150m server-side fuzz; only `fuzzy_geom` queried/returned | 3 |
| Performance | GIST indexes, `ST_DWithin`, cursor pagination → /discover p95 < 200ms | 19.1 |
| Safety | Bidirectional block exclusion in all spatial queries; report webhook | 16 |
| GDPR | Cascade deletes + purge job remove PII & location within 24h | 17 |
| Observability | Sentry in Flutter and FastAPI; capture WS disconnects | 19.5 |
| Battery | Stationary detection reduces poll cadence to 5min | 4.3 |

---

## Error Handling

- **Validation** (422): tag limits (10/user, 5/event), radius clamp, `starts_at < ends_at`.
- **Auth** (401): invalid/expired JWT or OTP. **Forbidden** (403): non-host event edits,
  attendee list for non-hosts.
- **Conflict** (409): capacity exceeded on "going" RSVP (or waitlist per policy).
- **WS**: on disconnect, ws_manager deregisters the socket, reports to Sentry, and the client
  auto-reconnects with backoff.

## Testing Strategy

- **Unit**: fuzzing offset distribution (~150m), ranking weights, expiry computation,
  tag-limit validators.
- **Integration**: `/discover` ranking + pagination + exclusion; `ST_DWithin` correctness;
  RLS policy enforcement; RSVP upsert uniqueness.
- **Realtime**: WS message round-trip via Redis; range-exit on heartbeat; FCM trigger when
  backgrounded.
- **Privacy/compliance**: assert `geom` never serialised; account-deletion purge cascade.
- **Performance**: load test `/discover` to validate p95 < 200ms.
