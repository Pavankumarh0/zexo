"""WebSocket connection manager with Redis pub/sub fan-out.

Maintains a per-thread registry of local WebSocket connections and bridges them to a Redis
channel so messages fan out across all app instances (design.md "Real-Time & Expiry
Infrastructure"). Message persistence happens on the publish path before fan-out.
"""

from __future__ import annotations

import asyncio
import json
import logging
from collections import defaultdict

from fastapi import WebSocket

from app.core import redis as redis_core

logger = logging.getLogger("zexo.ws")


class WsManager:
    def __init__(self) -> None:
        self._connections: dict[str, set[WebSocket]] = defaultdict(set)
        self._bridges: dict[str, asyncio.Task] = {}
        self._lock = asyncio.Lock()

    async def connect(self, thread_id: str, ws: WebSocket) -> None:
        await ws.accept()
        async with self._lock:
            self._connections[thread_id].add(ws)
            if thread_id not in self._bridges:
                self._bridges[thread_id] = asyncio.create_task(self._bridge(thread_id))

    async def disconnect(self, thread_id: str, ws: WebSocket) -> None:
        async with self._lock:
            self._connections[thread_id].discard(ws)
            if not self._connections[thread_id]:
                self._connections.pop(thread_id, None)
                bridge = self._bridges.pop(thread_id, None)
                if bridge:
                    bridge.cancel()

    async def publish(self, thread_id: str, frame: dict) -> None:
        """Publish a frame to all subscribers across instances via Redis."""
        await redis_core.publish(thread_id, json.dumps(frame))

    async def _bridge(self, thread_id: str) -> None:
        """Relay Redis channel messages to all locally-connected sockets for the thread."""
        try:
            async for payload in redis_core.subscribe(thread_id):
                await self._broadcast_local(thread_id, payload)
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # pragma: no cover - defensive; reported to Sentry
            logger.exception("ws bridge error on thread %s: %s", thread_id, exc)

    async def _broadcast_local(self, thread_id: str, payload: str) -> None:
        dead: list[WebSocket] = []
        for ws in list(self._connections.get(thread_id, ())):
            try:
                await ws.send_text(payload)
            except Exception:  # client gone mid-send
                dead.append(ws)
        for ws in dead:
            await self.disconnect(thread_id, ws)


manager = WsManager()
