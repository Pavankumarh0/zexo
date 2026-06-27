"""Data access for users, locations, blocks (parametrised SQL / PostGIS)."""

from __future__ import annotations

import asyncpg


async def get_profile(conn: asyncpg.Connection, user_id: str) -> asyncpg.Record | None:
    return await conn.fetchrow(
        """
        SELECT id, display_name, bio, avatar_url, interest_tags, is_visible, radius_m
        FROM users WHERE id = $1
        """,
        user_id,
    )


async def get_public_profile(conn: asyncpg.Connection, user_id: str) -> asyncpg.Record | None:
    return await conn.fetchrow(
        """
        SELECT id, display_name, bio, avatar_url, interest_tags
        FROM users WHERE id = $1
        """,
        user_id,
    )


async def update_profile(
    conn: asyncpg.Connection,
    user_id: str,
    *,
    display_name: str | None,
    bio: str | None,
    avatar_url: str | None,
    interest_tags: list[str] | None,
    radius_m: float | None,
) -> asyncpg.Record | None:
    """Partial update — only non-None fields are written (COALESCE preserves existing)."""
    return await conn.fetchrow(
        """
        UPDATE users SET
            display_name  = COALESCE($2, display_name),
            bio           = COALESCE($3, bio),
            avatar_url    = COALESCE($4, avatar_url),
            interest_tags = COALESCE($5, interest_tags),
            radius_m      = COALESCE($6, radius_m)
        WHERE id = $1
        RETURNING id, display_name, bio, avatar_url, interest_tags, is_visible, radius_m
        """,
        user_id,
        display_name,
        bio,
        avatar_url,
        interest_tags,
        radius_m,
    )


async def upsert_fuzzy_location(
    conn: asyncpg.Connection,
    user_id: str,
    *,
    fuzzy_lat: float,
    fuzzy_lng: float,
    accuracy_m: float | None,
) -> asyncpg.Record:
    """Persist ONLY the fuzzed point. Raw GPS (`geom`) is never written (Requirement 3).

    The fuzz offset is applied by the service layer before this is called.
    """
    return await conn.fetchrow(
        """
        INSERT INTO user_locations (user_id, fuzzy_geom, accuracy_m, updated_at)
        VALUES ($1, ST_SetSRID(ST_MakePoint($2, $3), 4326), $4, now())
        ON CONFLICT (user_id) DO UPDATE SET
            fuzzy_geom = EXCLUDED.fuzzy_geom,
            accuracy_m = EXCLUDED.accuracy_m,
            updated_at = now()
        RETURNING updated_at,
                  ST_Y(fuzzy_geom)::double precision AS fuzzy_lat,
                  ST_X(fuzzy_geom)::double precision AS fuzzy_lng
        """,
        user_id,
        fuzzy_lng,
        fuzzy_lat,
        accuracy_m,
    )


async def set_visibility(conn: asyncpg.Connection, user_id: str, is_visible: bool) -> bool:
    row = await conn.fetchrow(
        "UPDATE users SET is_visible = $2 WHERE id = $1 RETURNING is_visible",
        user_id,
        is_visible,
    )
    return bool(row["is_visible"]) if row else is_visible


async def get_origin_and_radius(conn: asyncpg.Connection, user_id: str) -> asyncpg.Record | None:
    """Return the caller's own fuzzy origin point + configured radius for discovery."""
    return await conn.fetchrow(
        """
        SELECT ST_Y(l.fuzzy_geom)::double precision AS lat,
               ST_X(l.fuzzy_geom)::double precision AS lng,
               u.radius_m
        FROM users u
        LEFT JOIN user_locations l ON l.user_id = u.id
        WHERE u.id = $1
        """,
        user_id,
    )


async def add_block(
    conn: asyncpg.Connection,
    blocker: str,
    blocked: str,
    *,
    reason: str | None,
    reported: bool,
) -> None:
    await conn.execute(
        """
        INSERT INTO blocks (blocker, blocked, reason, reported)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (blocker, blocked) DO UPDATE SET
            reason = EXCLUDED.reason,
            reported = blocks.reported OR EXCLUDED.reported
        """,
        blocker,
        blocked,
        reason,
        reported,
    )


async def delete_account(conn: asyncpg.Connection, user_id: str) -> None:
    """GDPR erasure via the SECURITY DEFINER function (migration 0008)."""
    await conn.execute("SELECT delete_user_account($1)", user_id)
