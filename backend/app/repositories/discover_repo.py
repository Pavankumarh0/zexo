"""Data access for discovery (nearby users) and the map bounding-box query.

Both delegate to SECURITY DEFINER functions (migration 0009) so callers never read raw
location rows directly and only fuzzy coordinates are returned.
"""

from __future__ import annotations

import asyncpg


async def nearby_users(
    conn: asyncpg.Connection,
    me: str,
    *,
    lat: float,
    lng: float,
    radius_m: float,
) -> list[asyncpg.Record]:
    return await conn.fetch(
        """
        SELECT user_id, display_name, avatar_url, interest_tags,
               fuzzy_lat, fuzzy_lng, distance_m
        FROM nearby_users($1, ST_SetSRID(ST_MakePoint($2, $3), 4326), $4)
        """,
        me,
        lng,
        lat,
        radius_m,
    )


async def map_users(
    conn: asyncpg.Connection,
    me: str,
    *,
    min_lng: float,
    min_lat: float,
    max_lng: float,
    max_lat: float,
) -> list[asyncpg.Record]:
    return await conn.fetch(
        "SELECT user_id, fuzzy_lat, fuzzy_lng FROM users_in_bbox($1, $2, $3, $4, $5)",
        me,
        min_lng,
        min_lat,
        max_lng,
        max_lat,
    )


async def map_events(
    conn: asyncpg.Connection,
    me: str,
    *,
    min_lng: float,
    min_lat: float,
    max_lng: float,
    max_lat: float,
) -> list[asyncpg.Record]:
    return await conn.fetch(
        "SELECT id, title, lat, lng, tags FROM events_in_bbox($1, $2, $3, $4, $5)",
        me,
        min_lng,
        min_lat,
        max_lng,
        max_lat,
    )
