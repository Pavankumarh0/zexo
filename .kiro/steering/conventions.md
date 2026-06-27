---
inclusion: always
---

# Zexo — Conventions (Naming, Structure, Code Style)

Apply these conventions to every change. They keep the Flutter client and FastAPI backend
consistent and reviewable.

## Repository / Folder Structure

### Flutter client (`lib/`)
```
lib/
  main.dart
  core/        # cross-cutting: api/, ws/, location/, notifications/, telemetry/, providers/, router.dart
  features/    # one folder per feature: onboarding/, discover/, chat/, events/, settings/
  shared/      # reusable: widgets/, models/, theme/
```
- Organise by **feature**, not by layer. Each feature owns its screens, widgets, and
  providers.
- Cross-feature reusable code lives in `shared/`; infrastructure/services in `core/`.

### FastAPI backend (`app/`)
```
app/
  main.py
  core/         # config, db, redis, security
  routers/      # one module per resource: auth, users, discover, threads, events
  services/     # business logic: location_service, ranking_service, ws_manager, expiry_service, moderation
  repositories/ # parametrised SQL / PostGIS access
  schemas/      # pydantic request/response models
  migrations/   # ordered SQL: NNNN_description.sql
```
- Keep routers thin: validation + delegation. Business logic lives in `services/`, data
  access in `repositories/`. No raw SQL in routers.

## Naming

| Item | Convention | Example |
| --- | --- | --- |
| Dart files | snake_case | `discover_card.dart` |
| Dart classes | PascalCase | `DiscoverCard`, `LocationService` |
| Dart vars/functions | lowerCamelCase | `fuzzyLat`, `refreshFeed()` |
| Riverpod providers | lowerCamelCase + `Provider` suffix | `discoverFeedProvider` |
| Python modules/files | snake_case | `ranking_service.py` |
| Python classes | PascalCase | `WsManager`, `RankingService` |
| Python funcs/vars | snake_case | `fuzz_coordinates()`, `radius_m` |
| DB tables/columns | snake_case | `user_locations`, `fuzzy_geom` |
| Migrations | `NNNN_snake_description.sql` | `0001_postgis_users_locations.sql` |
| API routes | kebab/lowercase, plural nouns | `/users/me`, `/threads/:id/expire` |
| Env vars | UPPER_SNAKE_CASE | `SUPABASE_URL`, `UPSTASH_REDIS_URL` |

## Code Style

- **Dart**: follow `flutter analyze` / `flutter_lints`. Format with `dart format`. Prefer
  `const` constructors, immutable models, and explicit types on public APIs.
- **Python**: target Python 3.12, full type hints, async/await for IO. Format with
  **black**, lint with **ruff**. Use pydantic models for all request/response bodies.
- Keep functions focused; extract helpers over deeply nested logic.
- No commented-out code or dead code in committed changes.

## API & Data Conventions

- All timestamps are **timestamptz** in UTC, serialised as ISO-8601.
- All IDs are **UUID**.
- Geometry columns are **geometry(Point, 4326)**; query via `ST_DWithin`/`ST_Distance` on
  `::geography`.
- List endpoints use **cursor-based pagination** (`cursor` + `next_cursor`); never raw
  offset for feed/discovery.
- Error envelope: `{ "error": { "code": string, "message": string } }`. Use correct HTTP
  status codes (401 auth, 403 forbidden, 409 conflict, 422 validation).
- Enforce limits at the API boundary: **10 interest tags/user**, **5 tags/event**, radius
  clamped **500m–50km** (default 5km).

## Privacy & Security Conventions

- Never store, log, return, or export raw `geom`. Only `fuzzy_geom` (fuzzy_lat/fuzzy_lng)
  may appear in responses.
- Every new table ships with **RLS enabled** and explicit policies in the same migration.
- Validate the Supabase JWT on every protected endpoint via the shared auth dependency.
- Apply bidirectional **block exclusion** in every feed, map, and attendee query.
- Secrets only from environment; never commit keys or DSNs.

## Testing & Commits

- Add/extend tests with behaviour changes: unit (services), integration (endpoints + RLS +
  PostGIS), realtime (WS round-trip), privacy (no `geom` leakage), performance (`/discover`
  p95 < 200ms).
- Commit messages: imperative mood, scoped prefix where useful — e.g.
  `feat(discover): cursor pagination`, `fix(chat): set message TTL`.
- Keep PRs scoped to a single task from `tasks.md` where practical; reference the task
  number and requirement IDs.
