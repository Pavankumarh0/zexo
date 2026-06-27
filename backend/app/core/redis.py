"""Redis (Upstash) pub/sub helpers for WebSocket fan-out.

Each chat thread maps to a channel `thread:{id}`. Messages are persisted to Postgres on
the publish path; Redis only fans the already-persisted event out to subscribed app
instances (design.md "Real-Time & Expiry Infrastructure").
"""

from __future__ import annotations

from collections.abc import AsyncIterator

import redis.asyncio as redis

from app.core.config import get_settings

_client: redis.Redis | None = None


def thread_channel(thread_id: str) -> str:
    return f"thread:{thread_id}"


async def init_redis() -> redis.Redis:
    global _client
    if _client is None:
        settings = get_settings()
        _client = redis.from_url(settings.redis_url, decode_responses=True)
    return _client


async def close_redis() -> None:
    global _client
    if _client is not None:
        await _client.aclose()
        _client = None


def get_redis() -> redis.Redis:
    if _client is None:
        raise RuntimeError("Redis not initialised; call init_redis() on startup")
    return _client


async def publish(thread_id: str, payload: str) -> None:
    await get_redis().publish(thread_channel(thread_id), payload)


async def subscribe(thread_id: str) -> AsyncIterator[str]:
    """Yield raw message payloads published to a thread channel."""
    pubsub = get_redis().pubsub()
    await pubsub.subscribe(thread_channel(thread_id))
    try:
        async for message in pubsub.listen():
            if message is not None and message.get("type") == "message":
                yield message["data"]
    finally:
        await pubsub.unsubscribe(thread_channel(thread_id))
        await pubsub.aclose()
