"""Chat thread, message, and WebSocket frame schemas."""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

from app.schemas.users import PublicUserProfile


class OpenThreadRequest(BaseModel):
    peer_id: str


class OpenThreadResponse(BaseModel):
    thread_id: str
    created: bool


class ThreadSummary(BaseModel):
    id: str
    peer: PublicUserProfile
    last_message_at: datetime | None = None
    unread_count: int = 0
    expires_at: datetime | None = None


class ThreadList(BaseModel):
    items: list[ThreadSummary]


class Message(BaseModel):
    id: str
    thread_id: str
    sender_id: str
    body: str
    read_at: datetime | None = None
    expires_at: datetime
    created_at: datetime


class ExpireResponse(BaseModel):
    expired: bool
    reason: Literal["range_exit", "ttl", "manual"]


# ----- WebSocket frames -----


class WSMessageIn(BaseModel):
    type: Literal["message"] = "message"
    body: str = Field(min_length=1, max_length=4000)


class WSReadIn(BaseModel):
    type: Literal["read"] = "read"
    up_to_message_id: str


class WSHeartbeatIn(BaseModel):
    type: Literal["heartbeat"] = "heartbeat"
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
