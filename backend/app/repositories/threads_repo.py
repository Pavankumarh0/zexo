"""Data access for chat threads and messages."""

from __future__ import annotations

import asyncpg


async def open_or_get_thread(conn: asyncpg.Connection, me: str, peer: str) -> tuple[str, bool]:
    """Idempotently open a thread between two users. Returns (thread_id, created)."""
    existing = await conn.fetchrow(
        """
        SELECT id FROM chat_threads
        WHERE LEAST(user_a, user_b) = LEAST($1::uuid, $2::uuid)
          AND GREATEST(user_a, user_b) = GREATEST($1::uuid, $2::uuid)
        """,
        me,
        peer,
    )
    if existing:
        return str(existing["id"]), False

    row = await conn.fetchrow(
        "INSERT INTO chat_threads (user_a, user_b) VALUES ($1, $2) RETURNING id",
        me,
        peer,
    )
    return str(row["id"]), True


async def list_threads(conn: asyncpg.Connection, me: str) -> list[asyncpg.Record]:
    return await conn.fetch(
        """
        SELECT t.id,
               t.last_message_at,
               t.expires_at,
               CASE WHEN t.user_a = $1 THEN t.user_b ELSE t.user_a END AS peer_id,
               pu.display_name AS peer_display_name,
               pu.avatar_url   AS peer_avatar_url,
               pu.bio          AS peer_bio,
               pu.interest_tags AS peer_interest_tags,
               (
                   SELECT count(*) FROM messages m
                   WHERE m.thread_id = t.id
                     AND m.sender_id <> $1
                     AND m.read_at IS NULL
               ) AS unread_count
        FROM chat_threads t
        JOIN users pu ON pu.id = (CASE WHEN t.user_a = $1 THEN t.user_b ELSE t.user_a END)
        WHERE $1 IN (t.user_a, t.user_b)
          AND (t.expires_at IS NULL OR t.expires_at > now())
        ORDER BY t.last_message_at DESC NULLS LAST
        """,
        me,
    )


async def get_thread(conn: asyncpg.Connection, thread_id: str) -> asyncpg.Record | None:
    return await conn.fetchrow(
        "SELECT id, user_a, user_b, expires_at FROM chat_threads WHERE id = $1",
        thread_id,
    )


async def expire_thread(conn: asyncpg.Connection, thread_id: str) -> None:
    await conn.execute(
        """
        UPDATE chat_threads SET expires_at = now()
        WHERE id = $1 AND (expires_at IS NULL OR expires_at > now())
        """,
        thread_id,
    )


async def insert_message(
    conn: asyncpg.Connection, thread_id: str, sender_id: str, body: str
) -> asyncpg.Record:
    """Insert a message. `expires_at` defaults to now()+24h at the DB (Requirement 9.1)."""
    row = await conn.fetchrow(
        """
        INSERT INTO messages (thread_id, sender_id, body)
        VALUES ($1, $2, $3)
        RETURNING id, thread_id, sender_id, body, read_at, expires_at, created_at
        """,
        thread_id,
        sender_id,
        body,
    )
    await conn.execute("UPDATE chat_threads SET last_message_at = now() WHERE id = $1", thread_id)
    return row


async def mark_read(
    conn: asyncpg.Connection, thread_id: str, reader_id: str, up_to_message_id: str
) -> list[asyncpg.Record]:
    """Mark the other party's messages read up to a given message; return affected ids."""
    return await conn.fetch(
        """
        UPDATE messages SET read_at = now()
        WHERE thread_id = $1
          AND sender_id <> $2
          AND read_at IS NULL
          AND created_at <= (SELECT created_at FROM messages WHERE id = $3)
        RETURNING id, read_at
        """,
        thread_id,
        reader_id,
        up_to_message_id,
    )
