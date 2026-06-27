#!/usr/bin/env python3
"""Apply Zexo SQL migrations to a PostgreSQL/PostGIS database (e.g. Supabase).

Usage:
    DATABASE_URL=postgresql://... python scripts/migrate.py            # apply pending
    DATABASE_URL=postgresql://... python scripts/migrate.py --status   # list state

Behaviour:
  * Creates a `_zexo_migrations` tracking table on first run.
  * Applies every `app/migrations/*.sql` not yet recorded, in filename order, each in its
    own transaction, recording the filename, a sha256 checksum, and a timestamp.
  * Re-running is safe: already-applied files are skipped; a changed checksum is reported.

Requires `asyncpg` (already in requirements.txt). Point DATABASE_URL at the Supabase
connection string (Project Settings → Database → Connection string → URI).
"""

from __future__ import annotations

import asyncio
import hashlib
import os
import sys
from pathlib import Path

import asyncpg

MIGRATIONS_DIR = Path(__file__).resolve().parent.parent / "app" / "migrations"
TRACKING_TABLE = "_zexo_migrations"


def _checksum(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _migration_files() -> list[Path]:
    return sorted(MIGRATIONS_DIR.glob("*.sql"))


async def _ensure_tracking(conn: asyncpg.Connection) -> None:
    await conn.execute(
        f"""
        CREATE TABLE IF NOT EXISTS {TRACKING_TABLE} (
            filename   text PRIMARY KEY,
            checksum   text NOT NULL,
            applied_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )


async def _applied(conn: asyncpg.Connection) -> dict[str, str]:
    rows = await conn.fetch(f"SELECT filename, checksum FROM {TRACKING_TABLE}")
    return {r["filename"]: r["checksum"] for r in rows}


async def run(status_only: bool) -> int:
    dsn = os.environ.get("DATABASE_URL")
    if not dsn:
        print("ERROR: set DATABASE_URL to your Postgres/Supabase connection string.")
        return 2

    files = _migration_files()
    if not files:
        print(f"No migrations found in {MIGRATIONS_DIR}")
        return 0

    conn = await asyncpg.connect(dsn)
    try:
        await _ensure_tracking(conn)
        applied = await _applied(conn)

        if status_only:
            print(f"Migrations in {MIGRATIONS_DIR}:")
            for f in files:
                checksum = _checksum(f.read_text())
                if f.name not in applied:
                    state = "PENDING"
                elif applied[f.name] != checksum:
                    state = "CHANGED (applied checksum differs!)"
                else:
                    state = "applied"
                print(f"  [{state:>10}] {f.name}")
            return 0

        pending = [f for f in files if f.name not in applied]
        if not pending:
            print("Database is up to date. Nothing to apply.")
            return 0

        for f in pending:
            sql = f.read_text()
            print(f"Applying {f.name} ...", end=" ", flush=True)
            async with conn.transaction():
                await conn.execute(sql)
                await conn.execute(
                    f"INSERT INTO {TRACKING_TABLE} (filename, checksum) VALUES ($1, $2)",
                    f.name,
                    _checksum(sql),
                )
            print("ok")

        print(f"Applied {len(pending)} migration(s).")
        return 0
    finally:
        await conn.close()


if __name__ == "__main__":
    status = "--status" in sys.argv
    raise SystemExit(asyncio.run(run(status)))
