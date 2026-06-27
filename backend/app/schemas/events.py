"""Event, RSVP, and attendee schemas."""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, model_validator

RsvpStatus = Literal["going", "maybe", "no"]
RsvpRole = Literal["host", "co-host", "guest"]
EventVisibility = Literal["public", "invite-only"]


class CreateEventRequest(BaseModel):
    title: str = Field(min_length=1, max_length=140)
    description: str | None = Field(default=None, max_length=2000)
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    radius_m: float = Field(default=500, ge=50, le=50_000)
    capacity: int | None = Field(default=None, gt=0)
    tags: list[str] = Field(default_factory=list)
    visibility: EventVisibility = "public"
    starts_at: datetime
    ends_at: datetime

    @model_validator(mode="after")
    def validate_event(self) -> CreateEventRequest:
        if len(self.tags) > 5:
            raise ValueError("An event may have at most 5 tags")
        if self.starts_at >= self.ends_at:
            raise ValueError("starts_at must be before ends_at")
        return self


class UpdateEventRequest(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=140)
    description: str | None = Field(default=None, max_length=2000)
    capacity: int | None = Field(default=None, gt=0)
    tags: list[str] | None = None
    visibility: EventVisibility | None = None
    starts_at: datetime | None = None
    ends_at: datetime | None = None

    @model_validator(mode="after")
    def validate_event(self) -> UpdateEventRequest:
        if self.tags is not None and len(self.tags) > 5:
            raise ValueError("An event may have at most 5 tags")
        if self.starts_at and self.ends_at and self.starts_at >= self.ends_at:
            raise ValueError("starts_at must be before ends_at")
        return self


class EventDetail(BaseModel):
    id: str
    creator_id: str
    title: str
    description: str | None = None
    lat: float
    lng: float
    radius_m: float
    capacity: int | None = None
    tags: list[str] = Field(default_factory=list)
    visibility: EventVisibility
    starts_at: datetime
    ends_at: datetime
    is_archived: bool
    attendee_count: int = 0
    distance_m: float | None = None
    my_rsvp: RsvpStatus | None = None


class EventList(BaseModel):
    items: list[EventDetail]
    next_cursor: str | None = None


class RsvpRequest(BaseModel):
    status: RsvpStatus


class RsvpResponse(BaseModel):
    event_id: str
    status: RsvpStatus
    role: RsvpRole


class Attendee(BaseModel):
    user_id: str
    display_name: str | None = None
    avatar_url: str | None = None
    role: RsvpRole
    status: RsvpStatus


class AttendeeList(BaseModel):
    event_id: str
    attendee_count: int
    # Populated only for host/co-host (Requirement 13.4); None otherwise.
    attendees: list[Attendee] | None = None
