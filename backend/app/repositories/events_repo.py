"""Data access for events, RSVPs, and attendees."""

from __future__ import annotations

from datetime import datetime

import asyncpg

_EVENT_COLUMNS = """
    e.id, e.creator_id, e.title, e.description,
    ST_Y(e.geom)::double precision AS lat,
    ST_X(e.geom)::double precision AS lng,
    e.radius_m, e.capacity, e.tags, e.visibility,
    e.starts_at, e.ends_at, e.is_archived
"""


async def create_event(
    conn: asyncpg.Connection,
    creator_id: str,
    *,
    title: str,
    description: str | None,
    lat: float,
    lng: float,
    radius_m: float,
    capacity: int | None,
    tags: list[str],
    visibility: str,
    starts_at: datetime,
    ends_at: datetime,
) -> asyncpg.Record:
    row = await conn.fetchrow(
        f"""
        INSERT INTO events (creator_id, title, description, geom, radius_m, capacity,
                            tags, visibility, starts_at, ends_at)
        VALUES ($1, $2, $3, ST_SetSRID(ST_MakePoint($4, $5), 4326), $6, $7, $8, $9, $10, $11)
        RETURNING {_EVENT_COLUMNS}
        """,
        creator_id,
        title,
        description,
        lng,
        lat,
        radius_m,
        capacity,
        tags,
        visibility,
        starts_at,
        ends_at,
    )
    # Record creator as host (Requirement 11.4).
    await conn.execute(
        """
        INSERT INTO event_rsvps (event_id, user_id, role, status)
        VALUES ($1, $2, 'host', 'going')
        ON CONFLICT (event_id, user_id) DO UPDATE SET role = 'host'
        """,
        row["id"],
        creator_id,
    )
    return row


async def list_nearby(
    conn: asyncpg.Connection,
    me: str,
    *,
    lat: float,
    lng: float,
    radius_m: float,
    tags: list[str] | None,
    after_distance: float | None,
    after_id: str | None,
    limit: int,
) -> list[asyncpg.Record]:
    """Active events within radius, distance-sorted, keyset-paginated by (distance, id)."""
    return await conn.fetch(
        f"""
        SELECT {_EVENT_COLUMNS},
               ST_Distance(e.geom::geography, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography)
                   AS distance_m,
               (SELECT count(*) FROM event_rsvps r
                 WHERE r.event_id = e.id AND r.status = 'going') AS attendee_count
        FROM events e
        WHERE e.is_archived = false
          AND e.ends_at > now()
          AND ST_DWithin(e.geom::geography,
                         ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography, $4)
          AND ($5::text[] IS NULL OR e.tags && $5::text[])
          AND (
              $6::double precision IS NULL
              OR (ST_Distance(e.geom::geography,
                              ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography), e.id)
                 > ($6::double precision, $7::uuid)
          )
        ORDER BY distance_m ASC, e.id ASC
        LIMIT $8
        """,
        me,
        lng,
        lat,
        radius_m,
        tags,
        after_distance,
        after_id,
        limit,
    )


async def get_event(conn: asyncpg.Connection, event_id: str, me: str) -> asyncpg.Record | None:
    return await conn.fetchrow(
        f"""
        SELECT {_EVENT_COLUMNS},
               (SELECT count(*) FROM event_rsvps r
                 WHERE r.event_id = e.id AND r.status = 'going') AS attendee_count,
               (SELECT r.status FROM event_rsvps r
                 WHERE r.event_id = e.id AND r.user_id = $2) AS my_rsvp
        FROM events e
        WHERE e.id = $1
        """,
        event_id,
        me,
    )


async def update_event(
    conn: asyncpg.Connection, event_id: str, fields: dict
) -> asyncpg.Record | None:
    """Update only provided columns. Caller (router) enforces host/co-host authorisation,
    and RLS provides defence in depth."""
    if not fields:
        return await get_event(conn, event_id, fields.get("_me", event_id))
    sets = []
    values: list = []
    for i, (col, val) in enumerate(fields.items(), start=2):
        sets.append(f"{col} = ${i}")
        values.append(val)
    query = f"UPDATE events SET {', '.join(sets)} WHERE id = $1 RETURNING {_EVENT_COLUMNS}"
    return await conn.fetchrow(query, event_id, *values)


async def role_for(conn: asyncpg.Connection, event_id: str, user_id: str) -> str | None:
    row = await conn.fetchrow(
        "SELECT role FROM event_rsvps WHERE event_id = $1 AND user_id = $2",
        event_id,
        user_id,
    )
    return row["role"] if row else None


async def upsert_rsvp(
    conn: asyncpg.Connection, event_id: str, user_id: str, status: str
) -> asyncpg.Record:
    """Insert or update the caller's RSVP (unique per event/user — Requirement 13.2).
    Preserves an existing host/co-host role."""
    return await conn.fetchrow(
        """
        INSERT INTO event_rsvps (event_id, user_id, role, status)
        VALUES ($1, $2, 'guest', $3)
        ON CONFLICT (event_id, user_id) DO UPDATE SET status = EXCLUDED.status
        RETURNING event_id, user_id, role, status
        """,
        event_id,
        user_id,
        status,
    )


async def set_role(conn: asyncpg.Connection, event_id: str, user_id: str, role: str) -> None:
    await conn.execute(
        """
        INSERT INTO event_rsvps (event_id, user_id, role, status)
        VALUES ($1, $2, $3, 'going')
        ON CONFLICT (event_id, user_id) DO UPDATE SET role = EXCLUDED.role
        """,
        event_id,
        user_id,
        role,
    )


async def attendee_count(conn: asyncpg.Connection, event_id: str) -> int:
    return await conn.fetchval(
        "SELECT count(*) FROM event_rsvps WHERE event_id = $1 AND status = 'going'",
        event_id,
    )


async def list_attendees(conn: asyncpg.Connection, event_id: str) -> list[asyncpg.Record]:
    return await conn.fetch(
        """
        SELECT r.user_id, r.role, r.status, u.display_name, u.avatar_url
        FROM event_rsvps r
        JOIN users u ON u.id = r.user_id
        WHERE r.event_id = $1
        ORDER BY r.role, u.display_name
        """,
        event_id,
    )


async def going_count_excluding(conn: asyncpg.Connection, event_id: str, user_id: str) -> int:
    return await conn.fetchval(
        """
        SELECT count(*) FROM event_rsvps
        WHERE event_id = $1 AND status = 'going' AND user_id <> $2
        """,
        event_id,
        user_id,
    )


async def event_capacity(conn: asyncpg.Connection, event_id: str) -> int | None:
    return await conn.fetchval("SELECT capacity FROM events WHERE id = $1", event_id)
