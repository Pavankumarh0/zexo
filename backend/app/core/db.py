"""Async PostgreSQL access via asyncpg.

Two connection paths:
  * `acquire(user_id=...)` — a pooled connection with `app.current_user_id` set for the
    request, so Row-Level Security policies apply to the authenticated caller.
  * `acquire_service()` — a connection WITHOUT a user context, used only for trusted server
    operations (migrations, cron-equivalent maintenance). Use sparingly.
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import asyncpg

from app.core.config import get_settings

_pool: asyncpg.Pool | None = None


async def init_pool() -> asyncpg.Pool:
    global _pool
    if _pool is None:
        settings = get_settings()
        _pool = await asyncpg.create_pool(
            dsn=settings.database_url,
            min_size=1,
            max_size=10,
            command_timeout=10,
        )
    return _pool


async def close_pool() -> None:
    global _pool
    if _pool is not None:
        await _pool.close()
        _pool = None


def _require_pool() -> asyncpg.Pool:
    if _pool is None:
        raise RuntimeError("DB pool not initialised; call init_pool() on startup")
    return _pool


@asynccontextmanager
async def acquire(user_id: str | None = None) -> AsyncIterator[asyncpg.Connection]:
    """Acquire a connection inside a transaction with the RLS user context set."""
    pool = _require_pool()
    async with pool.acquire() as conn:
        async with conn.transaction():
            # SET LOCAL is scoped to this transaction; read by app_current_user_id().
            await conn.execute(
                "SELECT set_config('app.current_user_id', $1, true)",
                str(user_id) if user_id else "",
            )
            yield conn


@asynccontextmanager
async def acquire_service() -> AsyncIterator[asyncpg.Connection]:
    """Acquire a connection with no user context (trusted server operations only)."""
    pool = _require_pool()
    async with pool.acquire() as conn:
        yield conn
