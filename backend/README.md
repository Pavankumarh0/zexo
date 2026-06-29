# Zexo API (DEPRECATED)

> ⚠️ **Deprecated.** The backend has been migrated to Firebase — see [`../functions`](../functions)
> (Cloud Functions + Firestore). This FastAPI/PostGIS service is kept for reference only and
> is no longer the source of truth.

Proximity-first social discovery backend. **FastAPI (Python 3.12) + PostgreSQL 16/PostGIS
(Supabase) + Redis pub/sub (Upstash)**, deployed on Railway.

This service implements the contracts in [`.kiro/specs/zexo`](../.kiro/specs/zexo) and obeys
the steering rules in [`.kiro/steering`](../.kiro/steering).

## Layout

```
app/
  main.py            # app factory, Sentry init, router registration, /health
  core/              # config, db pool, redis, JWT security
  routers/           # auth, users, discover, threads, events
  services/          # location fuzzing, ranking, ws manager, expiry, moderation
  repositories/      # parametrised SQL / PostGIS access
  schemas/           # pydantic request/response models
  migrations/        # ordered SQL (PostGIS, tables, GIST, RLS, pg_cron)
tests/               # unit + integration tests
```

## Local development

```bash
cd backend
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt -e ".[dev]"
cp .env.example .env   # fill in secrets
uvicorn app.main:app --reload --port 8000
```

Open http://localhost:8000/docs for the OpenAPI UI and http://localhost:8000/health.

## Connecting Supabase + writing the database

1. **Create a Supabase project** (or open your existing one).
2. **Enable the required extensions** — in the Supabase dashboard under
   *Database → Extensions*, enable `postgis`, `pgcrypto`, and `pg_cron`. (The migrations
   also `CREATE EXTENSION IF NOT EXISTS` them, but enabling via the dashboard avoids
   permission issues.)
3. **Grab the connection string** — *Project Settings → Database → Connection string → URI*.
   Use the **session** pooler/direct URI (port 5432) for migrations.
4. **Apply the migrations** with the included runner (idempotent, tracked in a
   `_zexo_migrations` table):

   ```bash
   cd backend
   pip install -r requirements.txt           # provides asyncpg
   export DATABASE_URL="postgresql://postgres:<pw>@db.<ref>.supabase.co:5432/postgres"
   make migrate            # apply all pending migrations
   make migrate-status     # show applied / pending / changed
   ```

   Or apply manually via the Supabase SQL editor by pasting each file in
   `app/migrations/` in numeric order (`0001` → `0009`).

5. **Set the API environment** (`.env`) — at minimum `DATABASE_URL`, `SUPABASE_URL`,
   `SUPABASE_JWT_SECRET`, `SUPABASE_SERVICE_ROLE_KEY`, and `REDIS_URL`. See `.env.example`.

### Authentication

Auth is **Google OAuth only** via Supabase Auth (no phone/OTP). Enable the Google provider
in *Supabase → Authentication → Providers → Google* and set the OAuth client ID/secret. The
mobile client performs the native Google sign-in and posts the ID token to `POST /auth/google`.

## Tests

The framework-independent core logic (location fuzzing, ranking) is covered by stdlib unit
tests that run without any third-party packages installed:

```bash
python -m unittest discover -s tests -p "test_*.py" -v
```

Full integration tests (endpoints, RLS, PostGIS) run with pytest once dependencies and a
test database are available:

```bash
pytest
```

## Key invariants (enforced by Kiro hooks)

- Coordinates are fuzzed **±150m server-side** before storage; only `fuzzy_geom` is ever
  queried or returned. Raw `geom` is never exposed.
- Discovery ranking weights **both** distance and interest-tag overlap; feed uses
  **cursor-based pagination** and excludes invisible/blocked users.
- Every message has a 24h `expires_at`; threads also expire on range exit.
- Every table has **RLS enabled**; all geometry columns have **GIST indexes**.
