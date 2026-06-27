"""Discovery feed and map schemas."""

from __future__ import annotations

from pydantic import BaseModel, Field

from app.schemas.users import PublicUserProfile


class DiscoverItem(BaseModel):
    user: PublicUserProfile
    distance_m: float
    shared_tags: list[str] = Field(default_factory=list)
    score: float


class DiscoverFeed(BaseModel):
    items: list[DiscoverItem]
    next_cursor: str | None = None


class MapUser(BaseModel):
    id: str
    fuzzy_lat: float
    fuzzy_lng: float


class MapEvent(BaseModel):
    id: str
    title: str
    lat: float
    lng: float
    tags: list[str] = Field(default_factory=list)


class MapResponse(BaseModel):
    users: list[MapUser]
    events: list[MapEvent]
