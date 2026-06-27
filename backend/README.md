# Zexo API

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

## Database migrations

Apply the ordered SQL in `app/migrations/` against your Supabase Postgres (PostGIS enabled):

```bash
for f in app/migrations/*.sql; do psql "$DATABASE_URL" -f "$f"; done
```

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
